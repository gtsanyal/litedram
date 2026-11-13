// -----------------------------------------------------------------------------
// End-to-end LPDDR4 testbench, Kintex-7 soft PHY:
//   LiteDRAM controller -> K7LPDDR4PHY (Xilinx unisim OSERDESE2/ISERDESE2/
//   IDELAYE2/ODELAYE2/IOBUF*) -> pads -> Winbond W66AP6NB model
//
// As on the Antmicro LPDDR4 Test Board, the design only receives the 100 MHz
// oscillator and a reset; the PLL (PLLE2_ADV unisim) generates all clocks.
// Simulate together with glbl.v (top-level `glbl`, Xilinx GSR/GTS).
//
// Board model: FPGA pads (f_*) and DRAM pins are connected through per-pin transport
// delays (PCB flight time + skew), randomized from the seed:
//   CK/CA/CS/CKE/ODT/RESET_n: common 100..600 ps, CA/CS per-pin skew +-30 ps
//   per byte lane: DQS 100..600 ps (independent of CK), DQ/DMI = DQS +- 40 ps per bit
// and the board reset is released at 1 us + 0..40 ns (moves PLL lock vs. everything else).
//
// Plusargs: +SEED=<n>  +NRANDOM=<n>  +DUMP  +BOARD_IDEAL (all delays 0, reset at 1 us)
//           +DUMP_START_NS=<t> +DUMP_END_NS=<t>  dump the pads + PHY ports in a window,
//           then stop (for debugging without a multi-ms VCD)
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

    // ------------------------------------------------------------------ LPDDR4 pins
    // DRAM side
    wire        clk_p, clk_n, cke, odt, reset_n, cs;
    wire [5:0]  ca;
    wire [15:0] dq;
    wire [1:0]  dqs_p, dqs_n, dmi;
    // FPGA side
    wire        f_clk_p, f_clk_n, f_cke, f_odt, f_reset_n, f_cs;
    wire [5:0]  f_ca;
    wire [15:0] f_dq;
    wire [1:0]  f_dqs_p, f_dqs_n, f_dmi;

    // ------------------------------------------------------------------ board (PCB) model
    int ck_dly_ps;                   // CK, CKE, ODT, RESET_n
    int ca_dly_ps [6];
    int cs_dly_ps;
    int dqs_dly_ps [2];
    int dq_dly_ps  [16];
    int dmi_dly_ps [2];

    // FPGA output enables (IOBUF T: 1 = FPGA not driving)
    wire [15:0] f_dq_t = {
        dut.main_k7lpddr4phy_dq_t15, dut.main_k7lpddr4phy_dq_t14, dut.main_k7lpddr4phy_dq_t13,
        dut.main_k7lpddr4phy_dq_t12, dut.main_k7lpddr4phy_dq_t11, dut.main_k7lpddr4phy_dq_t10,
        dut.main_k7lpddr4phy_dq_t9,  dut.main_k7lpddr4phy_dq_t8,  dut.main_k7lpddr4phy_dq_t7,
        dut.main_k7lpddr4phy_dq_t6,  dut.main_k7lpddr4phy_dq_t5,  dut.main_k7lpddr4phy_dq_t4,
        dut.main_k7lpddr4phy_dq_t3,  dut.main_k7lpddr4phy_dq_t2,  dut.main_k7lpddr4phy_dq_t1,
        dut.main_k7lpddr4phy_dq_t0};
    wire [1:0] f_dqs_t = {dut.main_k7lpddr4phy_dqs_t1, dut.main_k7lpddr4phy_dqs_t0};
    wire [1:0] f_dmi_t = {dut.main_k7lpddr4phy_dmi_t1, dut.main_k7lpddr4phy_dmi_t0};

    lpddr4_board_dly u_ck_p  (.a(f_clk_p),   .b(clk_p),   .d_ps(ck_dly_ps));
    lpddr4_board_dly u_ck_n  (.a(f_clk_n),   .b(clk_n),   .d_ps(ck_dly_ps));
    lpddr4_board_dly u_cke   (.a(f_cke),     .b(cke),     .d_ps(ck_dly_ps));
    lpddr4_board_dly u_odt   (.a(f_odt),     .b(odt),     .d_ps(ck_dly_ps));
    lpddr4_board_dly u_rst   (.a(f_reset_n), .b(reset_n), .d_ps(ck_dly_ps));
    lpddr4_board_dly u_cs    (.a(f_cs),      .b(cs),      .d_ps(cs_dly_ps));
    for (genvar i = 0; i < 6; i++) begin : g_ca
        lpddr4_board_dly u (.a(f_ca[i]), .b(ca[i]), .d_ps(ca_dly_ps[i]));
    end
    for (genvar i = 0; i < 16; i++) begin : g_dq
        lpddr4_board_bidir u (.a(f_dq[i]), .b(dq[i]), .a_t(f_dq_t[i]), .d_ps(dq_dly_ps[i]));
    end
    for (genvar i = 0; i < 2; i++) begin : g_dqs
        lpddr4_board_bidir up (.a(f_dqs_p[i]), .b(dqs_p[i]), .a_t(f_dqs_t[i]), .d_ps(dqs_dly_ps[i]));
        lpddr4_board_bidir un (.a(f_dqs_n[i]), .b(dqs_n[i]), .a_t(f_dqs_t[i]), .d_ps(dqs_dly_ps[i]));
        lpddr4_board_bidir um (.a(f_dmi[i]),   .b(dmi[i]),   .a_t(f_dmi_t[i]), .d_ps(dmi_dly_ps[i]));
    end

    function automatic int skew(input int base, input int max_ps);
        return base + int'($urandom_range(2*max_ps)) - max_ps;
    endfunction

    // +CK_EXTRA_PS=<n> / +BYTE0_EXTRA_PS=<n> / +BYTE1_EXTRA_PS=<n>: added on top (long traces)
    task automatic board_setup(input bit ideal);
        int ck_x, bx [2];
        if (ideal) begin
            ck_dly_ps = 0; cs_dly_ps = 0;
            foreach (ca_dly_ps[i])  ca_dly_ps[i]  = 0;
            foreach (dqs_dly_ps[i]) dqs_dly_ps[i] = 0;
            foreach (dq_dly_ps[i])  dq_dly_ps[i]  = 0;
            foreach (dmi_dly_ps[i]) dmi_dly_ps[i] = 0;
        end else begin
            ck_dly_ps = $urandom_range(600, 100);
            cs_dly_ps = skew(ck_dly_ps, 30);
            foreach (ca_dly_ps[i])  ca_dly_ps[i]  = skew(ck_dly_ps, 30);
            foreach (dqs_dly_ps[i]) dqs_dly_ps[i] = $urandom_range(600, 100);
            foreach (dq_dly_ps[i])  dq_dly_ps[i]  = skew(dqs_dly_ps[i/8], 40);
            foreach (dmi_dly_ps[i]) dmi_dly_ps[i] = skew(dqs_dly_ps[i], 40);
        end
        if (!$value$plusargs("CK_EXTRA_PS=%d", ck_x))    ck_x  = 0;
        if (!$value$plusargs("BYTE0_EXTRA_PS=%d", bx[0])) bx[0] = 0;
        if (!$value$plusargs("BYTE1_EXTRA_PS=%d", bx[1])) bx[1] = 0;
        ck_dly_ps += ck_x; cs_dly_ps += ck_x;
        foreach (ca_dly_ps[i])  ca_dly_ps[i]  += ck_x;
        foreach (dqs_dly_ps[i]) dqs_dly_ps[i] += bx[i];
        foreach (dq_dly_ps[i])  dq_dly_ps[i]  += bx[i/8];
        foreach (dmi_dly_ps[i]) dmi_dly_ps[i] += bx[i];
        $display("TB: board delays (ps): CK %0d CS %0d CA %p | DQS %p | DMI %p | DQ %p",
                 ck_dly_ps, cs_dly_ps, ca_dly_ps, dqs_dly_ps, dmi_dly_ps, dq_dly_ps);
    endtask

    // ------------------------------------------------------------------ tDQSS checker
    // The Winbond model does not check tDQSS (it captures DQ with DQS whatever the CK phase),
    // so check it here at the DRAM pins: at the operating frequency every write DQS rising edge
    // must be within +-0.25 tCK of a CK rising edge (tDQSS = 0.75..1.25 tCK). Checked once
    // training is done: write leveling and the write bitslip sweep move DQS on purpose.
    realtime ck_rise_t = 0, ck_period = 0;
    int      tdqss_errors = 0, tdqss_checked = 0;
    bit      tdqss_en = 1'b0;
    realtime tdqss_worst = 0;
    always @(posedge clk_p) begin ck_period = $realtime - ck_rise_t; ck_rise_t = $realtime; end
    for (genvar i = 0; i < 2; i++) begin : g_tdqss
        realtime ph;
        logic    prev = 1'bz;
        // only 0->1 strobe edges (not the z->1 of the DQS driver turning on)
        always @(dqs_p[i]) begin
            if (tdqss_en && prev === 1'b0 && dqs_p[i] === 1'b1 &&
                g_dqs[i].up.a_t_d === 1'b0 && ck_period > 2400 && ck_period < 2600 &&
                dut.main_k7lpddr4phy_k7lpddr4phy_k7lpddr4phy_wlevel_en_storage !== 1'b1) begin
                ph = $realtime - ck_rise_t;
                if (ph > ck_period/2) ph -= ck_period;
                tdqss_checked++;
                if ((ph < 0 ? -ph : ph) > (tdqss_worst < 0 ? -tdqss_worst : tdqss_worst)) tdqss_worst = ph;
                if (ph > 0.25*ck_period || ph < -0.25*ck_period) begin
                    if (tdqss_errors < 10)
                        $display("[%t] TB: ERROR: tDQSS: DQS[%0d] rises %0.0f ps from CK (limit +-%0.0f ps)",
                                 $realtime, i, ph, 0.25*ck_period);
                    tdqss_errors++;
                end
            end
            prev = dqs_p[i];
        end
    end

    // ------------------------------------------------------------------ CA bus monitor
    // Decodes mode register commands at the DRAM pins (after the PCB delays) on CK rising edges,
    // per the JESD209-4 command truth table (CS high on the 1st of the 2 ticks):
    //   MRW-1: CA[4:0]=L L H H L (CA0..CA4 = L H H L L), CA5=OP7 | 2nd tick: MA[5:0]
    //   MRW-2: CA0..CA4 = L H H L H,                     CA5=OP6 | 2nd tick: OP[5:0]
    //   MRR-1: CA0..CA4 = L H H H L,                     CA5=V   | 2nd tick: MA[5:0]
    // Pushes (MA, OP) / MA into lpddr4_ca_mon for the BIOS to check.
    typedef enum { MON_IDLE, MON_MRW1, MON_MRW2, MON_MRR1, MON_OTHER } mon_t;
    mon_t       mon_state = MON_IDLE;
    logic [5:0] mon_ma;
    logic       mon_op7, mon_op6;
    bit         mon_have_mrw1 = 0;
    always @(posedge clk_p) begin
        case (mon_state)
            MON_MRW1: begin mon_ma = ca; mon_have_mrw1 = 1; end
            MON_MRW2: if (mon_have_mrw1) begin
                          lpddr4_ca_mon::mrw_q.push_back('{int'(mon_ma), {mon_op7, mon_op6, ca}});
                          mon_have_mrw1 = 0;
                      end
            MON_MRR1: lpddr4_ca_mon::mrr_q.push_back(int'(ca));
            default: ;
        endcase
        mon_state = MON_IDLE;
        if (cs === 1'b1) begin
            case (ca[4:0])
                5'b00110: begin mon_state = MON_MRW1; mon_op7 = ca[5]; end
                5'b10110: begin mon_state = MON_MRW2; mon_op6 = ca[5]; end
                5'b01110:       mon_state = MON_MRR1;
                default: begin  mon_state = MON_OTHER; mon_have_mrw1 = 0; end
            endcase
        end
    end

    // ------------------------------------------------------------------ DUT (FPGA design)
    lpddr4_k7_top dut (
        .clk100             (clk100),
        .rst                (rst),

        .ddram_clk_p        (f_clk_p),
        .ddram_clk_n        (f_clk_n),
        .ddram_cke          (f_cke),
        .ddram_odt          (f_odt),
        .ddram_reset_n      (f_reset_n),
        .ddram_cs           (f_cs),
        .ddram_ca           (f_ca),
        .ddram_dq           (f_dq),
        .ddram_dqs_p        (f_dqs_p),
        .ddram_dqs_n        (f_dqs_n),
        .ddram_dmi          (f_dmi),

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
        board_setup($test$plusargs("BOARD_IDEAL"));
        if ($test$plusargs("DUMP")) begin
            $dumpfile("tb_lpddr4_k7.vcd");
            $dumpvars(1, tb_lpddr4_k7);
        end

        bios    = new(tbif);
        traffic = new(tbif);

        // Board reset, then wait for the PLL to lock and the design to come out of reset.
        #(1us);
        if (!$test$plusargs("BOARD_IDEAL")) #($urandom_range(40000));
        $display("[%t] TB: board reset released", $realtime);
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

        tdqss_en = 1'b1;
        bios.handover();
        fork traffic.monitor(); join_none
        traffic.directed();
        traffic.masked();
        traffic.streaming(32);
        traffic.random_ops(nrandom);

        $display("[%t] TRAFFIC: %0d writes, %0d reads, %0d errors", $realtime,
                 traffic.writes, traffic.reads, traffic.errors);
        $display("[%t] TRAINING: CK ODELAY=%0d rd bitslip=%p rd IDELAY=%p | wr DQS ODELAY=%p wr bitslip=%p wr DQ ODELAY=%p (taps of %0.1f ps)",
                 $realtime, bios.ck_tap, bios.rd_bitslip, bios.rd_dq_tap, bios.wr_dqs_tap, bios.wr_bitslip, bios.wr_dq_tap, TAP_PS);
        $display("[%t] TB: tDQSS: %0d write DQS edges checked, worst %0.0f ps from CK, %0d errors",
                 $realtime, tdqss_checked, tdqss_worst, tdqss_errors);
        if (traffic.errors == 0 && bios.errors == 0 && tdqss_errors == 0)
            $display("[%t] TEST PASSED", $realtime);
        else
            $display("[%t] TEST FAILED", $realtime);
        $finish;
    end

    initial begin
        longint t0, t1;
        if ($value$plusargs("DUMP_START_NS=%d", t0) && $value$plusargs("DUMP_END_NS=%d", t1)) begin
            $dumpfile("tb_lpddr4_k7_window.vcd");
            $dumpvars(1, tb_lpddr4_k7);
            $dumpvars(1, dut);
            $dumpoff;
            #(t0 * 1ns);
            $dumpon;
            #((t1 - t0) * 1ns);
            $dumpoff;
            $display("[%t] TB: dump window done", $realtime);
            $finish;
        end
    end

    initial begin
        #(60ms);
        $fatal(1, "Global timeout");
    end

endmodule

// PCB trace, one direction (transport delay: pulses are not filtered).
module lpddr4_board_dly (input wire a, output logic b, input int d_ps);
    always @(a) b <= #(d_ps) a;
endmodule

// PCB trace, bidirectional. Direction from the FPGA output enable `a_t` (IOBUF T, 1 = FPGA not
// driving): FPGA -> DRAM while the FPGA drives, DRAM -> FPGA otherwise; the far end sees the
// FPGA turn on/off `d_ps` later, as on a real line.
module lpddr4_board_bidir (inout wire a, inout wire b, input wire a_t, input int d_ps);
    logic a_t_d = 1'b1;
    logic a2b = 1'bz, b2a = 1'bz;
    always @(a_t)        a_t_d <= #(d_ps) a_t;
    always @(a or a_t)   a2b   <= #(d_ps) (a_t ? 1'bz : a);
    always @(b or a_t_d) b2a   <= #(d_ps) (a_t_d ? b : 1'bz);
    assign b = a2b;
    assign a = b2a;
endmodule
