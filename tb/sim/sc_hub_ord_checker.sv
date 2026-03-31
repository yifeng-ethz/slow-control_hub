module sc_hub_ord_checker #(
  parameter int unsigned ORDER_DOMAINS = 16
) (
  input  logic        clk,
  input  logic        rst,
  input  logic        monitor_enable,
  input  logic        sample_valid,
  input  logic [1:0]  sample_order_mode,
  input  logic [3:0]  sample_order_domain,
  input  logic [7:0]  sample_order_epoch,
  input  logic        sample_retire_valid
);
  import sc_hub_sim_pkg::*;

  int unsigned observed_txns;
  int unsigned observed_retires;
  int unsigned epoch_violations;
  int unsigned domain_violations;
  int unsigned relaxed_txns;
  int unsigned sample_retire_without_issue;
  int unsigned invalid_domain_count;
  int unsigned unsupported_mode_count;
  logic [7:0] last_epoch   [0:ORDER_DOMAINS-1];
  logic       domain_seen  [0:ORDER_DOMAINS-1];

  function automatic bit valid_domain(input logic [3:0] domain_id);
    return (domain_id < ORDER_DOMAINS);
  endfunction

  task automatic track_issue(
    input logic [1:0] order_mode,
    input logic [3:0] order_domain,
    input logic [7:0] order_epoch
  );
    if (!monitor_enable) begin
      return;
    end
    if (!valid_domain(order_domain)) begin
      invalid_domain_count += 1;
      return;
    end
    observed_txns += 1;
    if (order_mode == SC_ORDER_RELAXED) begin
      relaxed_txns += 1;
    end else if (order_mode == SC_ORDER_INVALID) begin
      domain_violations += 1;
    end else if ((order_mode != SC_ORDER_RELEASE) && (order_mode != SC_ORDER_ACQUIRE)) begin
      unsupported_mode_count += 1;
    end
    if (order_mode != SC_ORDER_RELAXED) begin
      if (domain_seen[order_domain] && (order_epoch < last_epoch[order_domain])) begin
        epoch_violations += 1;
      end
      last_epoch[order_domain]  = order_epoch;
      domain_seen[order_domain] = 1'b1;
    end
  endtask

  task automatic track_retire();
    if (monitor_enable) begin
      if (observed_txns == 0 || observed_retires >= observed_txns) begin
        sample_retire_without_issue += 1;
      end
      observed_retires += 1;
    end
  endtask

  always_ff @(posedge clk) begin
    if (rst) begin
      observed_txns        <= 0;
      observed_retires     <= 0;
      epoch_violations     <= 0;
      domain_violations    <= 0;
      relaxed_txns         <= 0;
      sample_retire_without_issue <= 0;
      unsupported_mode_count <= 0;
      invalid_domain_count <= 0;
      for (int unsigned idx = 0; idx < ORDER_DOMAINS; idx++) begin
        last_epoch[idx] <= 8'h00;
        domain_seen[idx] <= 1'b0;
      end
    end else if (monitor_enable) begin
      if (sample_valid) begin
        if (sample_order_mode != SC_ORDER_RELAXED) begin
          if (!valid_domain(sample_order_domain)) begin
            invalid_domain_count <= invalid_domain_count + 1'b1;
          end else if (domain_seen[sample_order_domain] &&
                       (sample_order_epoch < last_epoch[sample_order_domain])) begin
            epoch_violations <= epoch_violations + 1'b1;
          end
          if (sample_order_mode == SC_ORDER_INVALID) begin
            domain_violations <= domain_violations + 1'b1;
          end else if (sample_order_domain < ORDER_DOMAINS) begin
            last_epoch[sample_order_domain] <= sample_order_epoch;
            domain_seen[sample_order_domain] <= 1'b1;
          end
        end
        if (sample_order_mode == SC_ORDER_RELAXED) begin
          relaxed_txns <= relaxed_txns + 1'b1;
        end else if ((sample_order_mode != SC_ORDER_RELEASE) && (sample_order_mode != SC_ORDER_ACQUIRE)) begin
          unsupported_mode_count <= unsupported_mode_count + 1'b1;
        end
        observed_txns <= observed_txns + 1'b1;
      end
      if (sample_retire_valid) begin
        if (observed_retires >= observed_txns) begin
          sample_retire_without_issue <= sample_retire_without_issue + 1'b1;
        end
        observed_retires <= observed_retires + 1'b1;
      end
    end
  end

  task automatic report_summary();
    int unsigned active_domains;

    active_domains = 0;
    for (int unsigned idx = 0; idx < ORDER_DOMAINS; idx++) begin
      if (domain_seen[idx]) begin
        active_domains++;
      end
    end
    $display("sc_hub_ord_checker: observed_txns=%0d observed_retires=%0d relaxed_txns=%0d",
             observed_txns,
             observed_retires,
             relaxed_txns);
    $display("sc_hub_ord_checker: epoch_violations=%0d domain_violations=%0d invalid_domain=%0d",
             epoch_violations,
             domain_violations,
             invalid_domain_count);
    $display("sc_hub_ord_checker: unsupported_mode=%0d sample_retire_without_issue=%0d active_domains=%0d",
             unsupported_mode_count,
             sample_retire_without_issue,
             active_domains);

    if (sample_retire_without_issue != 0) begin
      $error("sc_hub_ord_checker: retires without tracked issue observed (%0d)",
             sample_retire_without_issue);
    end
    if (observed_retires > observed_txns) begin
      $error("sc_hub_ord_checker: retire count exceeded issue count (retire=%0d txns=%0d)",
             observed_retires,
             observed_txns);
    end
    if (unsupported_mode_count != 0) begin
      $warning("sc_hub_ord_checker: encountered unsupported order mode encoding");
    end

    // A29-A33 checks require core-side issue/retire visibility by domain and epoch;
    // this monitor only validates sampled sequence ordering when provided externally.
  endtask
endmodule
