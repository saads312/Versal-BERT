//
// Simple testbench for NoC Matrix Multiply
// Tests 2x2 systolic array with small matrices
//

`timescale 1ns / 1ps

module noc_mm_tb;

parameter D_W = 8;
parameter D_W_ACC = 32;
parameter N1 = 2;
parameter N2 = 2;
parameter MATRIXSIZE_W = 24;

reg clk_pl;
reg rstn_pl;

reg start;
wire done;
wire error;

reg [MATRIXSIZE_W-1:0] M1, M2, M3;
reg [63:0] addr_matrix_a;
reg [63:0] addr_matrix_b;
reg [63:0] addr_matrix_d;

// Clock generation
initial begin
    clk_pl = 0;
    forever #1.667 clk_pl = ~clk_pl;  // 300 MHz
end

// Test sequence
initial begin
    $display("========================================");
    $display("NoC Matrix Multiply Testbench");
    $display("========================================");

    // Initialize
    rstn_pl = 0;
    start = 0;

    // Matrix dimensions: 4x4 * 4x4 = 4x4
    M1 = 24'd4;
    M2 = 24'd4;
    M3 = 24'd4;

    // DDR addresses (would be real in hardware)
    addr_matrix_a = 64'h0000_0000_1000_0000;
    addr_matrix_b = 64'h0000_0000_2000_0000;
    addr_matrix_d = 64'h0000_0000_3000_0000;

    // Reset
    #100;
    rstn_pl = 1;
    #100;

    // Start operation
    $display("[%0t] Starting matrix multiply: %0dx%0d * %0dx%0d",
             $time, M1, M2, M2, M3);
    start = 1;
    #10;
    start = 0;

    // Wait for completion
    wait(done);
    #100;

    if (error) begin
        $display("[%0t] ERROR: Operation failed!", $time);
        $finish;
    end else begin
        $display("[%0t] SUCCESS: Matrix multiply completed!", $time);
    end

    #1000;
    $display("========================================");
    $display("Simulation Complete");
    $display("========================================");
    $finish;
end

// DUT instantiation
noc_mm_wrapper #(
    .D_W(D_W),
    .D_W_ACC(D_W_ACC),
    .N1(N1),
    .N2(N2),
    .MATRIXSIZE_W(MATRIXSIZE_W)
) dut (
    .clk_pl(clk_pl),
    .rstn_pl(rstn_pl),
    .start(start),
    .done(done),
    .error(error),
    .M1(M1),
    .M2(M2),
    .M3(M3),
    .addr_matrix_a(addr_matrix_a),
    .addr_matrix_b(addr_matrix_b),
    .addr_matrix_d(addr_matrix_d)
);

// Waveform dump
initial begin
    $dumpfile("noc_mm_tb.vcd");
    $dumpvars(0, noc_mm_tb);
end

endmodule
