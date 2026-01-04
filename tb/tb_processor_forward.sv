`timescale 1ns/1ps

// Testbench for the 2-stage pipelined processor WITH forwarding enabled
module processor_tb_forward;

  parameter int WIDTH = 32;
  parameter string MEM_FILE = "program_single.hex"; // run program with no software-level NOPs
  parameter int CLK_PERIOD = 10;          // ns (pipelined design)
  parameter int TIMEOUT_CYCLES = 5000;
  parameter int EXPECTED_A0 = 144;        // F12 = 144

  reg  clock = 0;
  reg  reset = 1;
  reg  memEn = 0;
  reg  [WIDTH-1:0] memData = 0;
  reg  [WIDTH-1:0] memAddr = 0;
  wire [WIDTH-1:0] gp, a7, a0;

  // DUT: pipelined processor + forwarding
  processor #(.WIDTH(WIDTH), .ENABLE_FORWARDING(1'b1)) dut (
    .clock(clock),
    .reset(reset),
    .memEn(memEn),
    .memData(memData),
    .memAddr(memAddr),
    .gp(gp),
    .a7(a7),
    .a0(a0)
  );

  integer i;
  integer cycles;

  always #(CLK_PERIOD/2) clock = ~clock;

  initial begin
    cycles = 0;

    #1;
    $display("[%0t] Loading memory from %s ...", $time, MEM_FILE);
    $readmemh(MEM_FILE, dut.mainMemory);

    for (i = 0; i < 32; i = i + 1)
      dut.registers[i] = 32'b0;

    reset = 1;
    repeat (2) @(posedge clock);
    reset = 0;
    $display("[%0t] Released reset, processor running.", $time);
  end

  always @(posedge clock) begin
    if (!reset) cycles <= cycles + 1;

    if (!reset && (a0 == EXPECTED_A0)) begin
      $display("[%0t] PASS (forwarding): a0 = %0d (0x%08x) after %0d cycles", $time, a0, a0, cycles);
      $finish;
    end

    if (cycles > TIMEOUT_CYCLES) begin
      $display("[%0t] TIMEOUT after %0d cycles. a0=%0d", $time, cycles, a0);
      $finish;
    end
  end

endmodule
