// -----------------------------------------------------------------------------
// End-to-end LPDDR4 testbench, Kintex-7 soft PHY:
//   LiteDRAM controller -> K7LPDDR4PHY (Xilinx unisim OSERDESE2/ISERDESE2/
//   IDELAYE2/ODELAYE2/IOBUF*) -> pads -> Winbond W66AP6NB model
//
// As on the Antmicro LPDDR4 Test Board, the design only receives the 100 MHz
// oscillator and a reset; the PLL (PLLE2_ADV unisim) generates all clocks.
// Simulate together with glbl.v (top-level `glbl`, Xilinx GSR/GTS).
//
// Plusargs: +SEED=<n>  +NRANDOM=<n>  +DUMP
// -----------------------------------------------------------------------------
`timescale 1ps/1fs

`include "lpddr4_bios.svh"
`include "lpddr4_traffic.svh"

module tb_lpddr4_k7;
    import lpddr4_pkg::*;

    // ------------------------------------------------------------------ board clock / reset
    logic clk100 = 1'b0;
    logic rst    = 1'b1;
    always #(CLK100_PERIOD_PS/2) clk100 = ~clk100;

    // Controller clock (from the PLL inside the design), used by the TB to drive CSRs/native port.
    wire sys_clk = dut.sys_clk;
    lpddr4_tb_if tbif (sys_clk);

    // ------------------------------------------------------------------ LPDDR4 pads
    wire        clk_p, clk_n, cke, odt, reset_n, cs;
    wire [5:0]  ca;
    wire [15:0] dq;
    wire [1:0]  dqs_p, dqs_n, dmi;

    // ------------------------------------------------------------------ DUT (FPGA design)
    lpddr4_k7_top dut (
        .clk100             (clk100),
        .rst                (rst),

        .ddram_clk_p        (clk_p),
        .ddram_clk_n        (clk_n),
        .ddram_cke          (cke),
        .ddram_odt          (odt),
        .ddram_reset_n      (reset_n),
        .ddram_cs           (cs),
        .ddram_ca           (ca),
        .ddram_dq           (dq),
        .ddram_dqs_p        (dqs_p),
        .ddram_dqs_n        (dqs_n),
        .ddram_dmi          (dmi),

        .cmd_valid          (tbif.cmd_valid),
        .cmd_ready          (tbif.cmd_ready),
        .cmd_first          (1'b1),
        .cmd_last           (1'b1),
        .cmd_payload_we     (tbif.cmd_we),
        .cmd_payload_addr   (tbif.cmd_addr),
        .wdata_valid        (tbif.wdata_valid),
        .wdata_ready        (tbif.wdata_ready),
        .wdata_first        (1'b1),
        .wdata_last         (1'b1),
        .wdata_payload_data (tbif.wdata_data),
        .wdata_payload_we   (tbif.wdata_we),
        .rdata_valid        (tbif.rdata_valid),
        .rdata_ready        (tbif.rdata_ready),
        .rdata_first        (1'b1),
        .rdata_last         (1'b1),
        .rdata_payload_data (tbif.rdata_data),

        .csr_adr            (tbif.csr_adr),
        .csr_we             (tbif.csr_we),
        .csr_re             (tbif.csr_re),
        .csr_dat_w          (tbif.csr_dat_w),
        .csr_dat_r          (tbif.csr_dat_r)
    );

    // ------------------------------------------------------------------ DRAM (one x16 channel)
    // LPDDR4 CS is active high despite the model's `cs_n` port name; the board's `odt`
    // pin is the DRAM ODT_CA input.
    W66AP6NB dram (
        .ck      (clk_p),
        .ck_n    (clk_n),
        .cke     (cke),
        .cs_n    (cs),
        .ca      (ca),
        .odt_ca  (odt),
        .dq      (dq),
        .dqs     (dqs_p),
        .dqs_n   (dqs_n),
        .dmi     (dmi),
        .reset_n (reset_n),
        .zq      (1'b0)
    );

    // ------------------------------------------------------------------ test
    lpddr4_bios    bios;
    lpddr4_traffic traffic;

    initial begin
        int seed, nrandom;
        $timeformat(-9, 3, " ns", 14);
        if (!$value$plusargs("SEED=%d", seed))       seed    = 1;
        if (!$value$plusargs("NRANDOM=%d", nrandom)) nrandom = 200;
        void'($urandom(seed));
        if ($test$plusargs("DUMP")) begin
            $dumpfile("tb_lpddr4_k7.vcd");
            $dumpvars(1, tb_lpddr4_k7);
        end

        bios    = new(tbif);
        traffic = new(tbif);

        // Board reset, then wait for the PLL to lock and the design to come out of reset.
        #(1us);
        rst = 1'b0;
        wait (dut.main_locked === 1'b1);
        $display("[%t] TB: PLL locked", $realtime);
        repeat (64) @(posedge sys_clk);

        bios.init();
        bios.train();
        if (bios.errors != 0) begin
            $display("[%t] TEST FAILED: training/initialization errors: %0d", $realtime, bios.errors);
            $finish;
        end

        bios.handover();
        fork traffic.monitor(); join_none
        traffic.directed();
        traffic.masked();
        traffic.streaming(32);
        traffic.random_ops(nrandom);

        $display("[%t] TRAFFIC: %0d writes, %0d reads, %0d errors", $realtime,
                 traffic.writes, traffic.reads, traffic.errors);
        $display("[%t] TRAINING: rd bitslip=%p rd IDELAY=%p | wr DQS ODELAY=%p wr bitslip=%p wr DQ ODELAY=%p (taps of %0.1f ps)",
                 $realtime, bios.rd_bitslip, bios.rd_dq_tap, bios.wr_dqs_tap, bios.wr_bitslip, bios.wr_dq_tap, TAP_PS);
        if (traffic.errors == 0 && bios.errors == 0)
            $display("[%t] TEST PASSED", $realtime);
        else
            $display("[%t] TEST FAILED", $realtime);
        $finish;
    end

    initial begin
        #(60ms);
        $fatal(1, "Global timeout");
    end

endmodule
