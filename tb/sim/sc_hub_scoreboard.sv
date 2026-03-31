module sc_hub_scoreboard (
  input logic clk,
  input logic rst
);
  import sc_hub_sim_pkg::*;

  int unsigned checks_run;
  int unsigned checks_failed;

  initial begin
    checks_run    = 0;
    checks_failed = 0;
  end

  task automatic expect_header_ok(input sc_reply_t reply, input int unsigned expected_length);
    checks_run++;
    if (!reply.header_valid || reply.echoed_length != expected_length[15:0] || reply.response != 2'b00) begin
      checks_failed++;
      $error("sc_hub_scoreboard: header mismatch length=%0d echoed=%0d valid=%0b rsp=%0b",
             expected_length, reply.echoed_length, reply.header_valid, reply.response);
    end
  endtask

  task automatic report_summary();
    $display("sc_hub_scoreboard: checks_run=%0d checks_failed=%0d", checks_run, checks_failed);
  endtask
endmodule
