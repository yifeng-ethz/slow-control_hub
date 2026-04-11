# Verification Signoff

## Scope

This note records the current standalone verification status of
`slow-control_hub` after the protocol/spec alignment work, the long-run UVM
promotion, and the standalone timing-closure updates.

All UCDB merges in this note use runs from the same current RTL revision. Mixed
UCDB merges across different RTL revisions are explicitly rejected as invalid for
cumulative signoff, because the merged total can become non-monotonic.

This note is a signoff record for the promoted standalone stress subset that was
actually rerun on the current tree. It is not yet a claim that the entire
`tb/DV_PLAN.md` matrix has been rerun to completion.

## External Closure Rubric

This repo now follows a more defensible public signoff model instead of treating
raw code coverage as the only objective.

- Coverage closure is tied to a verification plan and spec-derived intent, not
  to a single numeric code-coverage threshold. Public Siemens Verification
  Academy guidance makes that linkage explicit.
  Source: <https://verificationacademy.com/cookbook/coverage/>
- Verification signoff should be based on defined entry/exit criteria in a live
  verification plan, not ad-hoc simulation volume. Synopsys uses that model in
  its public verification-engagement guidance.
  Source: <https://www.synopsys.com/content/dam/synopsys/services/whitepapers/delivering-functional-verification-engagements.pdf>
- Once simulation coverage plateaus, the next step should be unreachable
  analysis / justification, not blind runtime growth. Cadence/Broadcom public
  guidance on MDV plus UNR matches that approach.
  Source: <https://community.cadence.com/cadence_blogs_8/b/fv/posts/leveraging-jasper-unr-app-and-metrics-driven-verification-to-achieve-coverage-signoff>

Practical application here:

- keep a small current-tree core suite for routine regression
- measure marginal gain of added long cases before promoting them
- treat uncovered residual space after the plateau as a future UNR/formal task,
  not as a reason to run arbitrary longer simulations forever

## Environment

- Simulator: Questa 23.1 with ETH floating license chain
- Coverage compile switches: `+cover=sbecft` and `-coverage`
- Structural metrics captured: statements, branches, conditions, expressions,
  FSM states, FSM transitions, toggles
- Functional metrics captured: command/reply covergroups from
  `tb/uvm/sc_hub_cov_collector.sv`
- Coverage-trend runs must be serialized per case. Parallel runs can race on the
  shared `modelsim.ini`/work setup and invalidate the run infrastructure even
  when the DUT is fine.

Trend artifacts copied into the repo:

- `doc/coverage_artifacts/T341_trend.csv`
- `doc/coverage_artifacts/T356_trend.csv`
- `doc/coverage_artifacts/T357_trend.csv`
- `doc/coverage_artifacts/T343_trend.csv`
- `doc/coverage_artifacts/T351_trend.csv`
- `doc/coverage_artifacts/suite_core_trend.csv`
- `doc/coverage_artifacts/suite_extended_trend.csv`
- corresponding `.png` plots for each trend

## Executed Cases

### Directed sanity

| Case | Evidence | Result |
|------|----------|--------|
| `smoke_basic` | `tb/sim_runs/smoke_basic.log` | PASS, `checks_run=2`, `checks_failed=0` |
| `T550` | `tb/sim_runs/T550.log` | PASS, SWB-style write observed, `ext_pkt_wr=1`, `ext_word_wr=3`, `pkt_drop=0`, `checks_failed=0` |

### Coverage-enabled promoted UVM runs

All measured promoted UVM runs completed with:

- `pending_cmd_depth=0`
- `miss_count=0`
- `overflow_count=0`
- `checks_failed=0`
- `UVM_ERROR=0`
- `UVM_FATAL=0`

Measured promoted cases on the current tree:

- `T341`
- `T356`
- `T357`
- `T343`
- `T351`

## Per-Case Final Coverage

The final row of each trend run is used below.

| Case | Final txn | Wall s | Total | Stmt | Branch | Cond | Expr | FSM state | FSM trans | Toggle | Covergroups | Cmd cg | Rsp cg |
|------|----------:|-------:|------:|-----:|-------:|-----:|-----:|----------:|----------:|-------:|------------:|-------:|-------:|
| `T341` | 768 | 6.598 | 41.27 | 53.71 | 41.11 | 20.26 | 26.31 | 75.00 | 42.55 | 21.04 | 50.15 | 47.81 | 52.50 |
| `T356` | 768 | 7.199 | 43.10 | 53.69 | 42.92 | 23.28 | 15.94 | 83.33 | 45.07 | 24.92 | 55.63 | 59.84 | 51.43 |
| `T357` | 768 | 6.086 | 50.48 | 55.69 | 45.71 | 23.29 | 34.73 | 91.66 | 55.31 | 30.96 | 66.48 | 67.27 | 65.71 |
| `T343` | 768 | 7.771 | 37.48 | 50.89 | 40.27 | 20.16 | 13.04 | 70.00 | 33.80 | 21.54 | 50.15 | 47.81 | 52.50 |
| `T351` | 768 | 63.219 | 29.59 | 49.19 | 33.08 | 16.28 | 13.68 | 54.16 | 23.40 | 10.67 | 36.22 | 37.27 | 35.18 |

## Coverage Trend vs Wall Time

For plateau analysis, `delta_total_pct_per_s` is used as a practical proxy for
"new information gained per wall-clock second". It is not literal Fisher
information, but it is the right engineering proxy here: new observable
coverage per unit runtime.

### `T341`

| Interval | Delta total % | Delta wall s | Gain %/s | Assessment |
|----------|---------------:|-------------:|---------:|------------|
| `64 -> 128` | 0.42 | 0.292 | 1.438 | still productive |
| `128 -> 256` | 0.41 | 0.698 | 0.587 | useful |
| `256 -> 512` | 0.06 | 1.377 | 0.044 | plateau begins |
| `512 -> 768` | 0.04 | 1.384 | 0.029 | plateau |

Interpretation:

- good short AXI4/OoO broadener
- useful as the fastest core-suite starter case
- little value beyond about `256` transactions if time is tight

### `T356`

| Interval | Delta total % | Delta wall s | Gain %/s | Assessment |
|----------|---------------:|-------------:|---------:|------------|
| `64 -> 128` | 1.96 | 0.416 | 4.712 | very high value |
| `128 -> 256` | 0.37 | 0.793 | 0.467 | still useful |
| `256 -> 512` | 0.04 | 1.793 | 0.022 | plateau |
| `512 -> 768` | 0.01 | 1.313 | 0.008 | hard plateau |

Interpretation:

- best Avalon mixed-traffic grower early in the run
- clearly saturates after about `256` transactions
- keep the deep `768` point only for publication/signoff artifacts, not for
  routine regression

### `T357`

| Interval | Delta total % | Delta wall s | Gain %/s | Assessment |
|----------|---------------:|-------------:|---------:|------------|
| `64 -> 128` | 0.46 | 0.417 | 1.103 | productive |
| `128 -> 256` | 0.51 | 0.567 | 0.899 | productive |
| `256 -> 512` | 0.21 | 1.203 | 0.175 | slower, still useful |
| `512 -> 768` | 0.17 | 1.180 | 0.144 | still useful |

Interpretation:

- strongest single deep case in the current measured set
- still adds toggle-heavy and ordering-heavy value late in the run
- keep as the long AXI4 signoff case

### `T343`

`T343` is a valid functional-retention case, but not a good coverage-growth
case.

- final total coverage is only `37.48%`
- as an extension after the core suite, it adds only `+0.13%` total in `7.771 s`
- suite-level gain is only `0.017 %/s`

Interpretation:

- keep for targeted ordering+atomic interaction coverage
- do not promote it into the routine core suite for coverage-growth reasons

### `T351`

`T351` is even less efficient as a coverage-growth case.

- final total coverage is only `29.59%`
- as an extension after the core suite, it adds only `+0.34%` total in `63.219 s`
- suite-level gain is only `0.005 %/s`

Interpretation:

- useful as a performance/latency-model characterization sweep
- not suitable as a routine coverage signoff case

## Cumulative Suite Trend

### Core suite

Merged current-tree coverage using the final UCDB from each case in this order:
`T341 -> T356 -> T357`.

| Step | Added case | Case wall s | Cum wall s | Delta total % | Delta %/s | Suite total % | Stmt | Branch | Cond | Expr | FSM state | FSM trans | Toggle | Covergroups |
|------|------------|------------:|-----------:|--------------:|----------:|--------------:|-----:|-------:|-----:|-----:|----------:|----------:|-------:|------------:|
| 1 | `T341` | 6.598 | 6.598 | 41.27 | 6.255 | 41.27 | 53.71 | 41.11 | 20.26 | 26.31 | 75.00 | 42.55 | 21.04 | 50.15 |
| 2 | `T356` | 7.199 | 13.797 | 5.47 | 0.760 | 46.74 | 56.32 | 44.85 | 24.22 | 32.32 | 79.31 | 49.12 | 25.09 | 62.72 |
| 3 | `T357` | 6.086 | 19.883 | 6.55 | 1.076 | 53.29 | 58.02 | 48.68 | 26.98 | 38.38 | 93.10 | 59.64 | 31.38 | 70.09 |

### Extended suite

Adding the exploratory cases after the core suite gives:

| Step | Added case | Case wall s | Cum wall s | Delta total % | Delta %/s | Suite total % |
|------|------------|------------:|-----------:|--------------:|----------:|--------------:|
| 4 | `T343` | 7.771 | 27.654 | 0.13 | 0.017 | 53.42 |
| 5 | `T351` | 63.219 | 90.873 | 0.34 | 0.005 | 53.76 |

Interpretation:

- `T341 + T356 + T357` is the high-value current-tree core suite
- that core suite reaches `53.29%` total structural coverage in `19.883 s`
- adding `T343` and `T351` costs another `70.990 s` for only `+0.47%` total
- the cumulative suite is therefore at a clear plateau after the core suite

## Signoff Decision

### Current status

PASS for the measured promoted standalone stress subset on the current RTL
revision.

What is actually closed by the evidence above:

- promoted mixed long-run Avalon and AXI4 standalone cases rerun on the current tree
- scoreboard, packet monitor, and ordering checker clean on all measured cases
- coverage instrumentation is stable when runs are serialized
- plateau behavior is measured well enough to choose a rational regression set

What is not yet closed by this note:

- the full `tb/DV_PLAN.md` execution matrix
- formal/UNR analysis for uncovered residual space
- a complete feature-to-bin closure table covering every planned test family

### Recommended regression policy

Routine current-tree regression:

- `T341` short
- `T356` truncated at `256`
- `T357` deep

Targeted, non-routine cases:

- `T343` for ordering+atomic interaction retention
- `T351` for AXI4 latency-profile / OoO characterization

## Open Items

- Extend the current-tree coverage-trend flow to more promoted `T300+` cases only
  where the expected marginal gain justifies the runtime.
- Add unreachable-bin analysis or formal closure for the remaining uncovered
  structural space, following the plateau evidence above.
- Link future signoff updates back into the `DV_PLAN.md` feature matrix so the
  closure argument remains spec-traceable.
