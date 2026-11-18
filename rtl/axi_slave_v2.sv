`timescale 1ns/1ps
//==============================================================================
// AXI4-Lite Slave (Subordinate)  --  v2  (AXI4-Lite slave)
//
// What it is : 16 x 32-bit register file behind an AXI4-Lite slave port.
// Address map: 0x00 .. 0x3F  (word index = addr[5:2]).
//              Anything >= 0x40 returns SLVERR and changes nothing.
// Rules it follows (ARM IHI 0022H.c, A3.3 / B1):
//   * READY outputs depend ONLY on internal registers (no combinational path
//     from any input to any output).
//   * AW and W are accepted independently, in ANY order and with any delay.
//   * BVALID rises only AFTER both the AW and the W handshake are complete.
//   * RVALID rises only AFTER the AR handshake is complete.
//   * VALID, once raised, stays up until the handshake.
//   * One write and one read outstanding at a time. While a write response is
//     pending the slave de-asserts AWREADY and WREADY, so extra write data can
//     never be swallowed.
// Synthesis : plain synthesizable RTL (no delays, no initial blocks).
//==============================================================================
module axi_slave_v2 #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int STRB_WIDTH = DATA_WIDTH/8,
    parameter int NUM_REGS   = 16
)(
    input  logic                  aclk,
    input  logic                  aresetn,

    // Write address channel
    input  logic                  s_awvalid,
    output logic                  s_awready,
    input  logic [ADDR_WIDTH-1:0] s_awaddr,

    // Write data channel
    input  logic                  s_wvalid,
    output logic                  s_wready,
    input  logic [DATA_WIDTH-1:0] s_wdata,
    input  logic [STRB_WIDTH-1:0] s_wstrb,

    // Write response channel
    output logic                  s_bvalid,
    input  logic                  s_bready,
    output logic [1:0]            s_bresp,

    // Read address channel
    input  logic                  s_arvalid,
    output logic                  s_arready,
    input  logic [ADDR_WIDTH-1:0] s_araddr,

    // Read data channel
    output logic                  s_rvalid,
    input  logic                  s_rready,
    output logic [DATA_WIDTH-1:0] s_rdata,
    output logic [1:0]            s_rresp
);

    localparam int IDX_W = $clog2(NUM_REGS);

    logic [DATA_WIDTH-1:0] regs [NUM_REGS];

    // "Pending" flags: a request has been accepted but not yet executed.
    logic                  aw_pend, w_pend, ar_pend;
    logic [ADDR_WIDTH-1:0] awaddr_q, araddr_q;
    logic [DATA_WIDTH-1:0] wdata_q;
    logic [STRB_WIDTH-1:0] wstrb_q;

    // READY depends only on state, never on VALID inputs.
    assign s_awready = !aw_pend && !s_bvalid;
    assign s_wready  = !w_pend  && !s_bvalid;
    assign s_arready = !ar_pend && !s_rvalid;

    // Address decode
    wire                 w_in_range = (awaddr_q[ADDR_WIDTH-1 : IDX_W+2] == '0);
    wire [IDX_W-1:0]     w_idx      = awaddr_q[IDX_W+1 : 2];
    wire                 r_in_range = (araddr_q[ADDR_WIDTH-1 : IDX_W+2] == '0);
    wire [IDX_W-1:0]     r_idx      = araddr_q[IDX_W+1 : 2];

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            aw_pend  <= 1'b0;
            w_pend   <= 1'b0;
            ar_pend  <= 1'b0;
            s_bvalid <= 1'b0;
            s_rvalid <= 1'b0;
            s_bresp  <= 2'b00;
            s_rresp  <= 2'b00;
            s_rdata  <= '0;
            awaddr_q <= '0;
            araddr_q <= '0;
            wdata_q  <= '0;
            wstrb_q  <= '0;
            for (int i = 0; i < NUM_REGS; i++) regs[i] <= '0;
        end else begin
            //---------------- write path ----------------
            // 1) capture address and data independently
            if (s_awvalid && s_awready) begin
                aw_pend  <= 1'b1;
                awaddr_q <= s_awaddr;
            end
            if (s_wvalid && s_wready) begin
                w_pend  <= 1'b1;
                wdata_q <= s_wdata;
                wstrb_q <= s_wstrb;
            end
            // 2) once BOTH are captured, execute and raise BVALID (one cycle later)
            if (aw_pend && w_pend && !s_bvalid) begin
                aw_pend  <= 1'b0;
                w_pend   <= 1'b0;
                s_bvalid <= 1'b1;
                if (w_in_range) begin
                    s_bresp <= 2'b00;                       // OKAY
                    for (int j = 0; j < STRB_WIDTH; j++)
                        if (wstrb_q[j]) regs[w_idx][8*j +: 8] <= wdata_q[8*j +: 8];
                end else begin
                    s_bresp <= 2'b10;                       // SLVERR, no state change
                end
            end else if (s_bvalid && s_bready) begin
                s_bvalid <= 1'b0;
            end

            //---------------- read path ----------------
            if (s_arvalid && s_arready) begin
                ar_pend  <= 1'b1;
                araddr_q <= s_araddr;
            end
            // RVALID rises only after the AR handshake has completed
            if (ar_pend && !s_rvalid) begin
                ar_pend  <= 1'b0;
                s_rvalid <= 1'b1;
                if (r_in_range) begin
                    s_rdata <= regs[r_idx];
                    s_rresp <= 2'b00;                       // OKAY
                end else begin
                    s_rdata <= '0;
                    s_rresp <= 2'b10;                       // SLVERR
                end
            end else if (s_rvalid && s_rready) begin
                s_rvalid <= 1'b0;
            end
        end
    end
endmodule
