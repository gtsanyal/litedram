// -----------------------------------------------------------------------------
// LPDDR4 PHY IO macro (behavioral model)
//
// This file is part of LiteDRAM.
// SPDX-License-Identifier: BSD-2-Clause
//
// Behavioral model of the analog/IO part of LPDDR4StrobePHY (litedram/phy/lpddr4/
// strobephy.py). It plays the role that IDELAY/ISERDES/IN_FIFO primitives play
// for FPGA PHYs, or the IO hard macro of an ASIC PHY:
//
//   * Pad drivers: CK_t/CK_c, CA, CS, CKE, RESET_n, ODT_CA, tristate DQ/DMI,
//     differential DQS_t/DQS_c.
//   * TX delay line (per byte) on DQ/DMI and their output enable, used to place
//     the write DQ eye at DQS + tDQS2DQ (write DQ-DQS training).
//   * Differential DQS receiver and RX delay line (per byte) that centers the
//     strobe in the edge-aligned read DQ eye.
//   * DQS-strobed read capture with a self-closing DQS gate and an asynchronous
//     FIFO into the controller (sys) clock domain.
//
// The only non-synthesizable constructs are the delay lines (#delays) and the
// receiver model; everything else is written as RTL.
// -----------------------------------------------------------------------------
`timescale 1ps/1fs

module lpddr4_phy_io #(
    parameter int NBYTES   = 2,
    parameter int TAP_PS   = 25,
    parameter int TAP_BITS = 6
) (
    input  wire                         clk_ui,     // sys8x_ddr: one rising edge per UI
    input  wire                         sys_clk,

    // Serialized signals from the PHY core
    input  wire                         ck,
    input  wire                         cke,
    input  wire                         cs,
    input  wire [5:0]                   ca,
    input  wire                         reset_n,
    input  wire                         odt,
    input  wire [8*NBYTES-1:0]          dq_o,
    input  wire [NBYTES-1:0]            dq_oe,
    input  wire [NBYTES-1:0]            dmi_o,
    input  wire [NBYTES-1:0]            dqs_o,
    input  wire [NBYTES-1:0]            dqs_oe,

    // Delay line settings
    input  wire [TAP_BITS*NBYTES-1:0]   wdq_taps,
    input  wire [TAP_BITS*NBYTES-1:0]   rdqs_taps,

    // Read capture
    input  wire [NBYTES-1:0]            gate,       // one UI-wide pulse per read burst
    input  wire                         rx_rst,     // asynchronous
    input  wire                         pop,        // sys_clk domain
    output wire [128*NBYTES-1:0]        rx_data,    // 16 beats x 8 bits per byte, beat 0 in LSBs
    output wire [NBYTES-1:0]            rx_empty,

    // LPDDR4 pads
    output wire                         ck_t,
    output wire                         ck_c,
    output wire                         cke_pad,
    output wire                         cs_pad,
    output wire [5:0]                   ca_pad,
    output wire                         reset_n_pad,
    output wire                         odt_ca,
    inout  wire [8*NBYTES-1:0]          dq,
    inout  wire [NBYTES-1:0]            dqs_t,
    inout  wire [NBYTES-1:0]            dqs_c,
    inout  wire [NBYTES-1:0]            dmi
);

    // ---------------------------------------------------------------- CA / CK
    assign ck_t        = ck;
    assign ck_c        = ~ck;
    assign cke_pad     = cke;
    assign cs_pad      = cs;
    assign ca_pad      = ca;
    assign reset_n_pad = reset_n;
    assign odt_ca      = odt;

    // ---------------------------------------------------------------- per byte
    for (genvar b = 0; b < NBYTES; b++) begin : g_byte
        wire [TAP_BITS-1:0] wtap = wdq_taps [b*TAP_BITS +: TAP_BITS];
        wire [TAP_BITS-1:0] rtap = rdqs_taps[b*TAP_BITS +: TAP_BITS];

        // TX delay line (transport delay) on DQ, DMI and their output enable.
        logic [7:0] dq_d  = '0;
        logic       dmi_d = 1'b0;
        logic       oe_d  = 1'b0;
        always @(dq_o[b*8 +: 8]) dq_d  <= #(wtap*TAP_PS) dq_o[b*8 +: 8];
        always @(dmi_o[b])       dmi_d <= #(wtap*TAP_PS) dmi_o[b];
        always @(dq_oe[b])       oe_d  <= #(wtap*TAP_PS) dq_oe[b];

        assign dq[b*8 +: 8] = oe_d      ? dq_d      : 8'bz;
        assign dmi[b]       = oe_d      ? dmi_d     : 1'bz;
        assign dqs_t[b]     = dqs_oe[b] ?  dqs_o[b] : 1'bz;
        assign dqs_c[b]     = dqs_oe[b] ? ~dqs_o[b] : 1'bz;

        // Differential DQS receiver: only a valid differential level is resolved;
        // Hi-Z or non-complementary inputs give X (must be masked by the gate).
        wire dqs_rx = (dqs_t[b] === 1'b1 && dqs_c[b] === 1'b0) ? 1'b1 :
                      (dqs_t[b] === 1'b0 && dqs_c[b] === 1'b1) ? 1'b0 : 1'bx;

        // RX delay line on the strobe (undefined until the receiver sees a valid level).
        logic dqs_dly = 1'bx;
        always @(dqs_rx) dqs_dly <= #(rtap*TAP_PS) dqs_rx;

        lpddr4_dqs_rx u_rx (
            .clk_ui  (clk_ui),
            .sys_clk (sys_clk),
            .rst     (rx_rst),
            .gate    (gate[b]),
            .dqs     (dqs_dly),
            .dq      (dq[b*8 +: 8]),
            .pop     (pop),
            .data    (rx_data[b*128 +: 128]),
            .empty   (rx_empty[b])
        );
    end

endmodule


// -----------------------------------------------------------------------------
// DQS-strobed capture of one byte lane.
//
// Gate: every `gate` pulse (sampled on clk_ui) schedules one 16-beat burst. The
// gated strobe runs while (opens != closes); `closes` advances on the 8th
// falling strobe edge of a burst, i.e. when the strobe is already low, so the
// gate closes without glitches and stays open across back-to-back bursts.
//
// Capture: DQ is registered on the rising strobe edge (even beats), and on
// each falling edge the {odd, even} pair is accumulated. The 8th pair completes
// a burst, which is written into an asynchronous FIFO (gray-coded pointers).
// -----------------------------------------------------------------------------
module lpddr4_dqs_rx #(
    parameter int AW = 4                    // FIFO depth = 2**AW bursts
) (
    input  wire         clk_ui,
    input  wire         sys_clk,
    input  wire         rst,
    input  wire         gate,
    input  wire         dqs,
    input  wire [7:0]   dq,
    input  wire         pop,
    output logic [127:0] data,
    output wire         empty
);

    function automatic logic [AW:0] bin2gray(input logic [AW:0] v);
        return v ^ (v >> 1);
    endfunction

    // ---------------------------------------------------------------- gate
    logic [3:0] opens, closes;
    always @(posedge clk_ui or posedge rst)
        if (rst)       opens <= '0;
        else if (gate) opens <= opens + 4'd1;

    wire gate_en = (opens != closes);
    wire dqs_g   = dqs & gate_en;

    // ---------------------------------------------------------------- capture (write side)
    logic [7:0]    rise_q;
    logic [2:0]    pair;
    logic [111:0]  acc;
    logic [127:0]  mem [2**AW];
    logic [AW:0]   wptr, wptr_gray;

    always @(posedge dqs_g or posedge rst)
        if (rst) rise_q <= '0;
        else     rise_q <= dq;

    always @(negedge dqs_g or posedge rst) begin
        if (rst) begin
            pair      <= '0;
            acc       <= '0;
            closes    <= '0;
            wptr      <= '0;
            wptr_gray <= '0;
        end else if (pair == 3'd7) begin
            mem[wptr[AW-1:0]] <= {dq, rise_q, acc};
            wptr      <= wptr + 1'b1;
            wptr_gray <= bin2gray(wptr + 1'b1);
            closes    <= closes + 4'd1;
            pair      <= '0;
        end else begin
            acc[pair*16 +: 16] <= {dq, rise_q};
            pair <= pair + 3'd1;
        end
    end

    // ---------------------------------------------------------------- read side (sys_clk)
    logic [AW:0] wg_s1, wg_s2, rptr;
    always @(posedge sys_clk or posedge rst)
        if (rst) begin
            wg_s1 <= '0;
            wg_s2 <= '0;
        end else begin
            wg_s1 <= wptr_gray;
            wg_s2 <= wg_s1;
        end

    assign empty = (bin2gray(rptr) == wg_s2);

    always @(posedge sys_clk or posedge rst)
        if (rst) begin
            rptr <= '0;
            data <= '0;
        end else if (pop) begin
            if (!empty) begin
                data <= mem[rptr[AW-1:0]];
                rptr <= rptr + 1'b1;
            end else begin
                data <= '0;
            end
        end

endmodule
