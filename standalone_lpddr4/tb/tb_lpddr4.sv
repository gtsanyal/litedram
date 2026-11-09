// -----------------------------------------------------------------------------
// End-to-end LPDDR4 testbench:
//   LiteDRAM controller -> LPDDR4StrobePHY -> pads -> Winbond W66AP6NB model
//
// Flow:
//   1. Boot clock (50 MHz CK), JEDEC reset/initialization, FSP1 programming,
//      ZQ calibration, FSP-OP switch, clock switch to 800 MHz (LPDDR4-1600).
//   2. PHY training through CSRs: read gate, read DQS delay, MRR checks,
//      write DQ delay (tDQS2DQ).
//   3. Hand-over to the LiteDRAM controller and native-port traffic with a
//      scoreboard (directed, masked writes, back-to-back reads, random).
//
// Plusargs: +SEED=<n>  +NRANDOM=<n>  +DUMP (VCD of the pads and lpddr4_top)
// -----------------------------------------------------------------------------
`timescale 1ps/1fs

`include "lpddr4_bios.svh"
`include "lpddr4_traffic.svh"

module tb_lpddr4;
    import lpddr4_pkg::*;

    // ------------------------------------------------------------------ clocks / reset
    wire sys_clk, sys8x_clk, sys8x_ddr_clk, rst;
    lpddr4_crg crg (
        .sys_clk       (sys_clk),
        .sys8x_clk     (sys8x_clk),
        .sys8x_ddr_clk (sys8x_ddr_clk),
        .rst           (rst)
    );

    lpddr4_tb_if tbif (sys_clk);

    // ------------------------------------------------------------------ LPDDR4 pads
    wire        ck_t, ck_c, cke, cs, reset_n, odt_ca;
    wire [5:0]  ca;
    wire [15:0] dq;
    wire [1:0]  dqs_t, dqs_c, dmi;

    // ------------------------------------------------------------------ DUT
    lpddr4_top dut (
        .rst                (rst),
        .sys_clk            (sys_clk),
        .sys8x_clk          (sys8x_clk),
        .sys8x_ddr_clk      (sys8x_ddr_clk),

        .ddram_ck_t         (ck_t),
        .ddram_ck_c         (ck_c),
        .ddram_cke          (cke),
        .ddram_cs           (cs),
        .ddram_ca           (ca),
        .ddram_reset_n      (reset_n),
        .ddram_odt_ca       (odt_ca),
        .ddram_dq           (dq),
        .ddram_dqs_t        (dqs_t),
        .ddram_dqs_c        (dqs_c),
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
    // Note: the vendor's W66BP2NQ dual-channel wrapper connects channel B to the
    // channel A pins, so the single-channel die model is instantiated directly.
    // LPDDR4 CS is active high despite the model's `cs_n` port name.
    W66AP6NB dram (
        .ck      (ck_t),
        .ck_n    (ck_c),
        .cke     (cke),
        .cs_n    (cs),
        .ca      (ca),
        .odt_ca  (odt_ca),
        .dq      (dq),
        .dqs     (dqs_t),
        .dqs_n   (dqs_c),
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
            $dumpfile("tb_lpddr4.vcd");
            $dumpvars(1, tb_lpddr4);         // pads
            $dumpvars(0, tb_lpddr4.dut);
        end

        bios    = new(tbif);
        traffic = new(tbif);

        crg.release_reset();

        // 1. Initialization
        bios.init_boot();
        crg.set_fast(1'b1);
        bios.init_fast();

        // 2. Training
        bios.train();
        if (bios.errors != 0) begin
            $display("[%t] TEST FAILED: training/initialization errors: %0d", $realtime, bios.errors);
            $finish;
        end

        // 3. Controller traffic
        bios.handover();
        fork traffic.monitor(); join_none
        traffic.directed();
        traffic.masked();
        traffic.streaming(32);
        traffic.random_ops(nrandom);

        $display("[%t] TRAFFIC: %0d writes, %0d reads, %0d errors", $realtime,
                 traffic.writes, traffic.reads, traffic.errors);
        $display("[%t] PHY training: gate=%p rdqs=%p wdq=%p (taps of %0d ps)", $realtime,
                 bios.gate, bios.rdqs, bios.wdq, TAP_PS);
        if (traffic.errors == 0 && bios.errors == 0)
            $display("[%t] TEST PASSED", $realtime);
        else
            $display("[%t] TEST FAILED", $realtime);
        $finish;
    end

    initial begin
        #(50ms);
        $fatal(1, "Global timeout");
    end

endmodule
