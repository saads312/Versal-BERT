`timescale 1ps / 1ps

module softmax_top
#(
    parameter integer D_W = 8,
    parameter integer D_W_ACC = 32,
    parameter integer MATRIXSIZE_W = 16,
    parameter integer LAYERS = 12,
    parameter integer HEADS = 12,
    parameter integer BATCHES = 1,
    parameter integer N = 32,
    parameter QB_MEM = "data/softmax/qb.mem",
    parameter QC_MEM = "data/softmax/qc.mem",
    parameter QLN2_MEM = "data/softmax/qln2.mem",
    parameter QLN2_INV_MEM = "data/softmax/qln2_inv.mem",
    parameter SREQ_MEM = "data/softmax/Sreq.mem"
)
(
    input  wire                      clk,
    input  wire                      rst,

    input  wire signed [D_W_ACC-1:0] qin_tdata,
    input  wire                      qin_tlast,
    output wire                      qin_tready,
    input  wire                      qin_tvalid,

    output wire signed [D_W-1:0]     qout_tdata,
    output wire                      qout_tlast,
    input  wire                      qout_tready,
    output wire                      qout_tvalid
);

localparam [MATRIXSIZE_W-1:0] _N = N;
localparam integer FP_BITS = 30;
localparam integer MAX_BITS = 30;
localparam integer OUT_BITS = 6;

wire [MATRIXSIZE_W-1:0] qout_col_cntr;
wire [MATRIXSIZE_W-1:0] qout_row_cntr;

reg signed [D_W_ACC-1:0] qin_tdata_reg;
reg qin_tvalid_reg = 0;

wire signed [D_W_ACC-1:0] qb_rom_rddata;
wire signed [D_W_ACC-1:0] qc_rom_rddata;
wire signed [D_W_ACC-1:0] qln2_rom_rddata;
wire signed [D_W_ACC-1:0] qln2_inv_rom_rddata;
wire signed [D_W_ACC-1:0] Sreq_rom_rddata;

wire in_tready_s0;
wire in_tready_s1;

reg [$clog2(HEADS):0] head_cntr;
reg [$clog2(BATCHES):0] batch_cntr;
reg [$clog2(LAYERS)-1:0] layer;

always @(posedge clk) begin
    if (rst) begin
        head_cntr <= 0;
        batch_cntr <= 0;
        layer <= 0;
    end else begin
        if (qout_tvalid & qout_tlast & qout_tready) begin
            head_cntr <= head_cntr + 1;
            if (head_cntr == HEADS-1) begin
                head_cntr <= 0;
                batch_cntr <= batch_cntr + 1;
                if (batch_cntr == BATCHES-1) begin
                    batch_cntr <= 0;
                    layer <= layer + 1;
                    if (layer == LAYERS-1) begin
                        layer <= 0;
                    end
                end
            end
        end
    end
end

assign qout_tlast = (qout_row_cntr == _N-1) && (qout_col_cntr == _N-1);

// register everyone at least once when in_tready_s0 is low
assign qin_tready = in_tready_s0 | ~qin_tvalid_reg;

// now I need everyone to be valid after first pass
assign in_tready_s0 = in_tready_s1 & qin_tvalid_reg;

// s1 stage
assign in_tready_s1 = qout_tready | ~qout_tvalid;

always @(posedge clk) begin
    if (rst) begin
        qin_tdata_reg <= 0;
        qin_tvalid_reg <= 0;
    end else begin
        if (qin_tready) begin
            qin_tdata_reg <= qin_tdata;
            qin_tvalid_reg <= qin_tvalid;
        end
    end
end

rom #(.D_W(D_W_ACC), .DEPTH(LAYERS), .INIT(QB_MEM))
qb_rom
(
    .clk    ( clk             ),
    .rdaddr ( layer           ),
    .rddata ( qb_rom_rddata   )
);

rom #(.D_W(D_W_ACC), .DEPTH(LAYERS), .INIT(QC_MEM))
qc_rom
(
    .clk    ( clk             ),
    .rdaddr ( layer           ),
    .rddata ( qc_rom_rddata   )
);

rom #(.D_W(D_W_ACC), .DEPTH(LAYERS), .INIT(QLN2_MEM))
qln2_rom
(
    .clk    ( clk             ),
    .rdaddr ( layer           ),
    .rddata ( qln2_rom_rddata )
);

rom #(.D_W(D_W_ACC), .DEPTH(LAYERS), .INIT(QLN2_INV_MEM))
qln2_inv_rom
(
    .clk    ( clk             ),
    .rdaddr ( layer           ),
    .rddata ( qln2_inv_rom_rddata )
);

rom #(.D_W(D_W_ACC), .DEPTH(LAYERS), .INIT(SREQ_MEM))
Sreq_rom
(
    .clk    ( clk             ),
    .rdaddr ( layer           ),
    .rddata ( Sreq_rom_rddata )
);

counter #(
    .MATRIXSIZE_W (MATRIXSIZE_W)
)
counter_softmax (
    .clk                (clk),
    .rst                (rst),
    .enable_pixel_count (qout_tvalid & qout_tready),
    .enable_slice_count (1'b1),
    .WIDTH              (_N),
    .HEIGHT             (_N),
    .pixel_cntr         (qout_col_cntr),
    .slice_cntr         (qout_row_cntr)
);

softmax #(
    .D_W      ( D_W      ),
    .D_W_ACC  ( D_W_ACC  ),
    .N        ( N        ),
    .FP_BITS  ( FP_BITS  ),
    .MAX_BITS ( MAX_BITS ),
    .OUT_BITS ( OUT_BITS )
)
softmax_unit (
    .clk       ( clk                 ),
    .rst       ( rst                 ),
    .enable    ( in_tready_s1        ),
    .in_valid  ( qin_tvalid_reg      ),
    .qin       ( qin_tdata_reg       ),
    .qb        ( qb_rom_rddata       ),
    .qc        ( qc_rom_rddata       ),
    .qln2      ( qln2_rom_rddata     ),
    .qln2_inv  ( qln2_inv_rom_rddata ),
    .Sreq      ( Sreq_rom_rddata     ),
    .out_valid ( qout_tvalid         ),
    .qout      ( qout_tdata          )
);

endmodule
