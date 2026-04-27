module sc_hub_freelist_monitor #(
  parameter int unsigned FREE_POOLS = 4,
  parameter int unsigned RAM_DEPTH  = 65536
) (
  input  logic        clk,
  input  logic        rst,
  input  logic        monitor_enable,
  input  logic        sample_done
);
  int unsigned last_free_count [0:FREE_POOLS-1];
  int unsigned sample_count    [0:FREE_POOLS-1];
  int unsigned mismatched_count;
  int unsigned overflow_count;
  int unsigned invalid_pool_count;
  int unsigned sample_cycles;
  bit        pool_seen       [0:FREE_POOLS-1];

  // A34-A37 require full RTL free-list visibility. At this harness boundary we only
  // observe externally sampled free_count values and validate quiesce boundaries.

  initial begin
    mismatched_count   = 0;
    overflow_count     = 0;
    invalid_pool_count = 0;
    sample_cycles      = 0;
    for (int unsigned idx = 0; idx < FREE_POOLS; idx++) begin
      last_free_count[idx] = 0;
      sample_count[idx]    = 0;
      pool_seen[idx]       = 1'b0;
    end
  end

  task automatic sample_pool_count(
    input int unsigned pool_id,
    input int unsigned free_count
  );
    if (!monitor_enable) begin
      return;
    end
    if (pool_id >= FREE_POOLS) begin
      invalid_pool_count += 1;
      return;
    end
    pool_seen[pool_id]      = 1'b1;
    last_free_count[pool_id] = free_count;
    sample_count[pool_id]    = sample_count[pool_id] + 1;
    if (free_count > RAM_DEPTH) begin
      overflow_count = overflow_count + 1;
    end
  endtask

  task automatic sample_quiesce_check();
    if (!monitor_enable || !sample_done) begin
      return;
    end
    for (int unsigned idx = 0; idx < FREE_POOLS; idx++) begin
      if (!pool_seen[idx]) begin
        mismatched_count = mismatched_count + 1;
      end else if (last_free_count[idx] != RAM_DEPTH) begin
        mismatched_count = mismatched_count + 1;
      end
    end
  endtask

  always @(posedge clk) begin
    if (rst) begin
      mismatched_count   <= 0;
      overflow_count     <= 0;
      invalid_pool_count <= 0;
      sample_cycles      <= 0;
      for (int unsigned idx = 0; idx < FREE_POOLS; idx++) begin
        last_free_count[idx] <= 0;
        sample_count[idx]    <= 0;
        pool_seen[idx]       <= 1'b0;
      end
    end else if (monitor_enable) begin
      sample_cycles <= sample_cycles + 1'b1;
    end
  end

  task automatic report_summary();
    int unsigned unsampled_pools;
    int unsigned total_samples;

    unsampled_pools = 0;
    total_samples   = 0;
    for (int unsigned idx = 0; idx < FREE_POOLS; idx++) begin
      if (!pool_seen[idx]) begin
        unsampled_pools += 1;
      end else begin
        total_samples += sample_count[idx];
      end
    end

    $display("sc_hub_freelist_monitor: mismatched=%0d overflow=%0d invalid_pool=%0d sample_cycles=%0d",
             mismatched_count,
             overflow_count,
             invalid_pool_count,
             sample_cycles);
    $display("sc_hub_freelist_monitor: unsampled_pools=%0d total_samples=%0d",
             unsampled_pools,
             total_samples);

    if (invalid_pool_count != 0) begin
      $error("sc_hub_freelist_monitor: invalid pool sample IDs seen (%0d)", invalid_pool_count);
    end
    if (overflow_count != 0) begin
      $error("sc_hub_freelist_monitor: free_count overflow observed (%0d)", overflow_count);
    end
    if (mismatched_count != 0) begin
      $error("sc_hub_freelist_monitor: free_count mismatch at quiesce check (%0d)", mismatched_count);
    end
  endtask
endmodule
