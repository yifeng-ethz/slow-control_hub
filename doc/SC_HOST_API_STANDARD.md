# SC Host API Standard

## Scope

This note defines the replacement software contract for FEB slow control. It is
intended to replace `FEBSlowcontrolInterface` as the standard host-side API for
`sc_hub` based access.

The model should follow the same robustness goals already used in
`online_dpv2/online/switching_pc/tools/sc_tool.cpp`:

- explicit packet fields
- explicit transport policy
- explicit parsed reply/result object
- preserved raw evidence for every failed or suspicious transaction
- no hidden bit overlays and no silent truncation

## Why `FEBSlowcontrolInterface` Is No Longer A Good Standard

The legacy helper mixes too many responsibilities in one class:

- packet building
- policy decisions
- MMIO transport
- queue draining
- reply parsing
- FEB selection and status reporting

That design creates three recurring problems:

- protocol limits are confused with deployment workarounds
- raw bit overlays such as `MSTR_bar` leak into callers
- failures lose context because the API mostly returns only one integer status

The new standard must separate those responsibilities.

## Design Goals

The replacement API must satisfy these requirements:

1. Protocol truth is represented directly.
2. Transport workarounds are explicit policy, not hard-coded packet limits.
3. Every transaction preserves raw sent and raw received words.
4. Every parser decision is reproducible from stored evidence.
5. The API can report partial success, malformed reply, timeout, and transport
   stall as different outcomes.
6. The caller never composes packet headers with raw bit masks.
7. The API supports both debug CLI tools and production MIDAS FE code.

## Required Layering

The standard host architecture should be split into five layers.

### 1. Protocol layer

Pure packet model, independent of MMIO or MIDAS.

Responsibilities:

- define packet field enums and widths
- encode/decode SC request and reply words
- validate framing, declared length, trailer position, and reply semantics
- decode extended response code and all v2 overlay fields

### 2. Transport policy layer

Explicit deployment policy, independent of packet format.

Responsibilities:

- max chunk size used on a given deployment path
- retry policy
- timeout budget
- whether reply suppression is allowed
- whether broadcasts are allowed on this path

The important rule is:

- protocol maximum and deployment maximum must be separate fields

### 3. MMIO transport layer

Pure read/write access to SWB BAR registers and memories.

Responsibilities:

- write command words into SC main
- trigger SC main
- poll completion
- drain SC secondary words
- report raw transport-level failures

This layer must not parse SC packets.

### 4. Transaction/client layer

Owns request execution and reply matching.

Responsibilities:

- split large requests according to transport policy
- assign transaction identity
- issue requests through MMIO transport
- parse and match replies
- return a complete result object

### 5. Presentation layer

MIDAS FE, CLI, and tests.

Responsibilities:

- convert `TransactionResult` into MIDAS status bits, logs, and user-facing text
- never re-parse packet words ad hoc
- never re-encode protocol fields with custom helper logic

## Proposed C++ Header Contract

The new standard should look like this at the API level.

```cpp
namespace sc {

enum class CommandKind : uint8_t {
    Read,
    Write,
    ReadNonIncrement,
    WriteNonIncrement,
};

enum class DetectorClass : uint8_t {
    All,
    MuPix,
    SciFi,
    Tile,
};

enum class OrderMode : uint8_t {
    Relaxed,
    Ordered,
    Release,
    Acquire,
};

enum class ResponseCode : uint8_t {
    Ok,
    SlaveError,
    DecodeError,
    Unknown,
};

enum class ResultKind : uint8_t {
    Success,
    Timeout,
    TransportBusy,
    TransportFault,
    MalformedReply,
    ReplyMismatch,
    PolicyRejected,
};

struct Request {
    CommandKind command;
    uint8_t fpga_id;
    uint32_t start_address;   // 24-bit protocol field, stored in 32 bits
    uint16_t length;          // protocol field width
    bool suppress_reply;
    bool mask_m;
    bool mask_s;
    bool mask_t;
    OrderMode order_mode;
    uint8_t order_domain;
    uint8_t order_epoch;
    bool atomic;
    uint32_t atomic_mask;
    uint32_t atomic_data;
    std::vector<uint32_t> payload;
};

struct TransportPolicy {
    uint16_t protocol_max_words;
    uint16_t transport_chunk_words;
    uint32_t main_done_timeout_cycles;
    uint32_t reply_timeout_cycles;
    bool allow_broadcast;
    bool allow_reply_suppressed_reads;
};

struct Reply {
    bool is_reply;
    CommandKind command;
    uint8_t fpga_id;
    uint32_t start_address;
    uint16_t declared_length;
    uint16_t observed_payload_words;
    ResponseCode response;
    bool ack_bit;
    bool trailer_seen;
    bool framing_ok;
    std::vector<uint32_t> payload;
    std::vector<uint32_t> raw_words;
};

struct TransactionTrace {
    std::vector<uint32_t> request_words;
    std::vector<uint32_t> secondary_words_seen;
    uint32_t sc_main_status_before;
    uint32_t sc_main_status_after;
    uint32_t polls_to_done;
    uint32_t polls_to_reply;
};

struct TransactionResult {
    ResultKind kind;
    ResponseCode response;
    Request request;
    Reply reply;
    TransactionTrace trace;
    std::string summary;
};

class MmioTransport {
public:
    virtual ~MmioTransport() = default;
    virtual bool SubmitMainPacket(const std::vector<uint32_t>& words,
                                  uint32_t timeout_cycles,
                                  uint32_t* polls_to_done) = 0;
    virtual bool DrainSecondary(std::vector<uint32_t>* words,
                                uint32_t timeout_cycles,
                                uint32_t* polls_to_reply) = 0;
};

class Client {
public:
    Client(MmioTransport& transport, TransportPolicy policy);
    TransactionResult Execute(const Request& request);
};

} // namespace sc
```

## Contract Rules

The standard API must enforce these rules.

### Rule 1: no raw header overlays

Callers must never pass raw `MSTR_bar` style masks.

Instead, the request object must carry named fields:

- `mask_m`
- `mask_s`
- `mask_t`
- `suppress_reply`
- `order_mode`
- `atomic`

### Rule 2: preserve protocol width

The API must preserve:

- 24-bit start address
- 16-bit protocol length

If transport policy wants smaller chunks, that must happen after request
construction and must be visible in the returned trace.

### Rule 3: preserve raw evidence

Every completed or failed transaction result must include:

- raw request words
- raw reply words or drained secondary words
- parser outcome
- transport-level wait counts

This is mandatory for post-mortem debugging.

### Rule 4: distinguish failure classes

The API must not collapse all failures into one integer status.

At minimum it must distinguish:

- timeout waiting for SC main completion
- timeout waiting for reply
- malformed reply framing
- reply mismatch to request identity
- transport busy / blocked
- protocol response `SLVERR`
- protocol response `DECERR`

### Rule 5: exact reply accounting

The result object must report both:

- declared payload length
- observed payload words

If they differ, the result must be marked suspicious even if the caller chooses
not to fail hard.

### Rule 6: transport policy is explicit

If a deployment still wants a `255` word cap, it must be set as:

- `transport_chunk_words = 255`

and never be described as a packet-format limit.

## Migration Guidance

The migration path should be:

1. keep `FEBSlowcontrolInterface` as a compatibility wrapper only
2. implement the new protocol and transport classes underneath
3. make the old wrapper translate into the new `Request` / `TransactionResult`
4. move MIDAS FE and CLI tools to the new client directly
5. remove raw `MSTR_bar` call sites

## Minimum Robustness Requirements

Any new implementation claiming compliance with this standard must:

- reject silent address truncation
- reject silent length truncation
- reject silent raw bit overlays
- retain raw request and reply words in the final result
- expose response code and framing status to the caller
- make chunking policy configurable
- support both incrementing and nonincrementing access
- be usable by both debug tools and production frontends

## Reference Implementation Direction

The immediate software model should take `sc_tool.cpp` as the behavioral
reference for robustness, not `FEBSlowcontrolInterface`.

That does not mean copying `sc_tool.cpp` directly into production. It means the
new shared library should preserve the same engineering principles:

- explicit state
- explicit parser decisions
- complete evidence capture
- no hidden magic in helper layers
