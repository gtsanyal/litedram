// -----------------------------------------------------------------------------
// Winbond W66AP6NB pin-level characterization testbench.
//
// Drives the LPDDR4 pins directly, without LiteDRAM, so that the timing the
// encrypted behavioral model actually expects can be measured:
//   * CS polarity, CA latching
//   * Initialization timing checks (tINIT1/3/5, ZQ)
//   * MRR output format (which beats / DQ lanes carry the MR value)
//   * MPC READ-DQ-CALIBRATION pattern order (and whether CAS-2 is required)
//   * Read: tDQSCK, preamble shape, DQ/DQS alignment
//   * Write: tDQSS reference and where DQ is sampled (tDQS2DQ)
//
// Run with: make lpddr4-probe-caen   (VCS on CAEN, see Makefile)
// -----------------------------------------------------------------------------
`timescale 1ps/1ps

module tb_model_probe;

    localparam int TCK      = 1250;     // LPDDR4-1600 (FSP1, operating frequency)
    localparam int TCK_BOOT = 20000;    // 50 MHz boot clock (tCKb: 18..100 ns) for FSP0
    localparam int UI       = TCK / 2;
    localparam int RL       = 14;
    localparam int WL       = 8;

    // ------------------------------------------------------------------ pins
    // Clock starts at the boot frequency; switched after the FSP-OP change.
    int   ck_half = TCK_BOOT / 2;
    logic ck_t    = 1'b0;
    always #(ck_half) ck_t = ~ck_t;
    wire  ck_c = ~ck_t;

    logic        cke     = 1'b0;
    logic        cs      = 1'b0;
    logic        reset_n = 1'b0;
    logic [5:0]  ca      = '0;

    logic [15:0] dq_drv  = '0;  logic dq_oe  = 1'b0;
    logic [1:0]  dqs_drv = '0;  logic dqs_oe = 1'b0;
    logic [1:0]  dmi_drv = '0;  logic dmi_oe = 1'b0;

    wire  [15:0] dq;
    wire  [1:0]  dqs_t, dqs_c, dmi;

    assign dq    = dq_oe  ? dq_drv   : 'z;
    assign dqs_t = dqs_oe ? dqs_drv  : 'z;
    assign dqs_c = dqs_oe ? ~dqs_drv : 'z;
    assign dmi   = dmi_oe ? dmi_drv  : 'z;

    W66AP6NB dram (
        .ck(ck_t), .ck_n(ck_c), .cke(cke), .cs_n(cs), .ca(ca), .odt_ca(1'b0),
        .dq(dq), .dqs(dqs_t), .dqs_n(dqs_c), .dmi(dmi),
        .reset_n(reset_n), .zq(1'b0)
    );

    // -------------------------------------------------------- CA helpers
    // Bits are listed CA0..CA5 as in the JEDEC truth table.
    function automatic logic [5:0] cab(input bit b0, b1, b2, b3, b4, b5);
        return {b5, b4, b3, b2, b1, b0};
    endfunction

    time t_last_cmd;   // rising CK edge that latched the 2nd cycle of the last small command

    // One "small command": CS high on 1st rising edge, low on 2nd.
    // CA/CS are changed on falling edges so they are centered on rising edges.
    task automatic small_cmd(input logic [5:0] ca_hi, input logic [5:0] ca_lo);
        @(negedge ck_t); cs = 1'b1; ca = ca_hi;
        @(negedge ck_t); cs = 1'b0; ca = ca_lo;
        @(posedge ck_t); t_last_cmd = $time;
        @(negedge ck_t); ca = '0;
    endtask

    task automatic mrw(input int ma, input logic [7:0] op);
        small_cmd(cab(0,1,1,0,0,op[7]), ma[5:0]);                        // MRW-1
        small_cmd(cab(0,1,1,0,1,op[6]), op[5:0]);                        // MRW-2
        repeat (20) @(posedge ck_t);                                     // tMRD/tMRW
    endtask

    task automatic cas2(input logic [9:0] col);
        small_cmd(cab(0,1,0,0,1,col[8]), col[7:2]);
    endtask

    task automatic mrr(input int ma);
        small_cmd(cab(0,1,1,1,0,0), ma[5:0]);                            // MRR-1
        cas2(10'd0);
    endtask

    task automatic mpc(input logic [6:0] op, input bit with_cas2);
        small_cmd(cab(0,0,0,0,0,op[6]), op[5:0]);
        if (with_cas2) cas2(10'd0);
    endtask

    task automatic act(input int ba, input int row);
        logic [16:0] r; r = row;
        small_cmd(cab(1,0,r[12],r[13],r[14],r[15]), cab(ba[0],ba[1],ba[2],r[16],r[10],r[11]));
        small_cmd(cab(1,1,r[6],r[7],r[8],r[9]),     r[5:0]);
        repeat (20) @(posedge ck_t);                                     // tRCD
    endtask

    task automatic wr1(input int ba, input logic [9:0] col, input bit masked);
        small_cmd(cab(0,0,1,masked,0,0), cab(ba[0],ba[1],ba[2],0,col[9],0));
    endtask

    task automatic rd1(input int ba, input logic [9:0] col);
        small_cmd(cab(0,1,0,0,0,0), cab(ba[0],ba[1],ba[2],0,col[9],0));
    endtask

    task automatic pre_all();
        small_cmd(cab(0,0,0,0,1,1), '0);
        repeat (30) @(posedge ck_t);
    endtask

    // -------------------------------------------------------- read capture
    // Logs every DQ/DQS transition while enabled, relative to the last command.
    bit mon_en = 0;
    always @(dq or dqs_t or dqs_c) if (mon_en)
        $display("    [+%6.0f ps = %6.2f tCK] DQS_t=%b DQS_c=%b DQ=%h",
                 real'($time - t_last_cmd), real'($time - t_last_cmd)/TCK, dqs_t, dqs_c, dq);

    // Sample DQ in the middle of each UI following each DQS edge (DQ is
    // edge-aligned to DQS on reads).
    logic [15:0] beats [$];
    bit cap_en = 0;
    always @(dqs_t) if (cap_en && (dqs_t[0] === 1'b0 || dqs_t[0] === 1'b1))
        fork begin
            #(UI/2);
            if (cap_en) beats.push_back(dq);
        end join_none

    task automatic observe_read(input string what, input int ncycles = 40);
        $display("\n=== %s (last cmd edge @ %0t) ===", what, t_last_cmd);
        beats.delete();
        mon_en = 1; cap_en = 1;
        repeat (ncycles) @(posedge ck_t);
        mon_en = 0; cap_en = 0;
        $write("    beats(%0d):", beats.size());
        foreach (beats[i]) $write(" %h", beats[i]);
        $write("\n");
    endtask

    // -------------------------------------------------------- write driver
    // first DQS rising edge at: t_ref + WL*tCK + tdqss
    // beat i is driven so that its eye is centered at (DQS edge i + dq_center)
    task automatic drive_write(input time t_ref, input int tdqss, input int dq_center,
                               input logic [15:0] data [16]);
        time t0;
        t0 = t_ref + WL*TCK + tdqss;
        fork
            begin // DQS: 2tCK static preamble, 16 edges, 0.5tCK postamble
                #(t0 - 2*TCK - $time);
                dqs_oe = 1; dqs_drv = 2'b00;
                for (int i = 0; i < 16; i++) begin
                    #(t0 + i*UI - $time);
                    dqs_drv = (i % 2 == 0) ? 2'b11 : 2'b00;
                end
                #(t0 + 16*UI - $time);
                dqs_oe = 0;
            end
            begin // DQ/DMI
                for (int i = 0; i < 16; i++) begin
                    #(t0 + i*UI + dq_center - UI/2 - $time);
                    dq_oe = 1; dmi_oe = 1; dmi_drv = 2'b00;
                    dq_drv = data[i];
                end
                #(t0 + 16*UI + dq_center - UI/2 - $time);
                dq_oe = 0; dmi_oe = 0;
            end
        join
    endtask

    function automatic void make_pattern(input int k, output logic [15:0] d [16]);
        for (int i = 0; i < 16; i++) d[i] = 16'((k << 12) | (i << 8) | (8'h5A ^ i));
    endfunction

    // -------------------------------------------------------- sequence
    logic [15:0] pat [16];
    time t_wr;

    initial begin
        $timeformat(-9, 3, " ns", 12);
        $display("--- power-up: RESET_n low, CKE low");
        #(200_000_000);                       // tINIT1 = 200 us
        @(negedge ck_t); reset_n = 1'b1;
        $display("--- %t RESET_n high, waiting tINIT3 (2 ms)", $time);
        #(2_000_000_000);
        @(negedge ck_t); cke = 1'b1;
        $display("--- %t CKE high, waiting tINIT5 (2 us)", $time);
        #(2_000_000);

        // Program FSP1 (operating point for LPDDR4-1600) while running on FSP0 at the boot clock.
        mrw(13, 8'b0100_0000);              // FSP-WR=1, FSP-OP=0
        // MR1: BL16, 2tCK WR preamble, static RD preamble, nWR=16, 0.5tCK RD postamble
        mrw(1,  8'b0_010_0_1_00);
        // MR2: RL=14, WL=8 (set A)
        mrw(2,  8'b0_0_010_010);
        $display("--- %t FSP1 MRWs done; ZQ calibration", $time);
        mpc(7'b1001111, 0);  #(1_000_000);   // ZQCAL START, tZQCAL = 1 us
        mpc(7'b1010001, 0);  #(200_000);     // ZQCAL LATCH, tZQLAT = max(30 ns, 8 tCK)

        // Frequency change: switch operating point to FSP1, then change the clock.
        mrw(13, 8'b0100_1000);              // VRCG=1 (fast Vref settling) before the FSP change
        mrw(13, 8'b1100_1000);              // FSP-OP=1, FSP-WR=1, VRCG=1
        repeat (5) @(posedge ck_t);         // tCKFSPE
        @(negedge ck_t); ck_half = TCK / 2;
        $display("--- %t clock switched to %0d ps", $time, TCK);
        #(300_000);                         // tFC (long) + tCKFSPX
        mrw(13, 8'b1100_0000);              // VRCG back to normal
        #(200_000);                         // tVRCG_DISABLE

        // ---- MRR
        mrr(5);  observe_read("MRR MR5 (manufacturer ID)");
        mrr(8);  observe_read("MRR MR8 (density/type)");
        mrr(2);  observe_read("MRR MR2 (RL/WL just written)");
        mrr(32); observe_read("MRR MR32 (DQ calib pattern A)");
        mrr(40); observe_read("MRR MR40 (DQ calib pattern B)");

        // ---- MPC READ DQ CALIBRATION (OP = 1000011), with and without CAS-2
        mrw(32, 8'h5A); mrw(40, 8'h3C); mrw(15, 8'h00); mrw(20, 8'h00);
        mpc(7'b1000011, 1); observe_read("MPC READ-DQ-CAL + CAS-2 (MR32=5A, MR40=3C)");
        mrw(32, 8'h01); mrw(40, 8'h80);
        mpc(7'b1000011, 1); observe_read("MPC READ-DQ-CAL + CAS-2 (MR32=01, MR40=80) -> bit order");
        mrw(32, 8'h5A); mrw(40, 8'h3C);
        mpc(7'b1000011, 0); observe_read("MPC READ-DQ-CAL without CAS-2");

        // ---- write / read with different DQ placements
        act(0, 5);
        // (a) DQ centered on DQS pin edges (DDR3 style)
        make_pattern(1, pat); wr1(0, 10'h000, 0); cas2(10'h000); t_wr = t_last_cmd;
        drive_write(t_wr, TCK, 0, pat);
        repeat (30) @(posedge ck_t);
        // (b) DQ centered on DQS + tDQS2DQ (500 ps), as LPDDR4 requires
        make_pattern(2, pat); wr1(0, 10'h010, 0); cas2(10'h010); t_wr = t_last_cmd;
        drive_write(t_wr, TCK, 500, pat);
        repeat (30) @(posedge ck_t);
        // (c) tDQSS = 0.75 tCK, DQ at tDQS2DQ
        make_pattern(3, pat); wr1(0, 10'h020, 0); cas2(10'h020); t_wr = t_last_cmd;
        drive_write(t_wr, TCK*3/4, 500, pat);
        repeat (30) @(posedge ck_t);
        // (d) tDQSS = 1.25 tCK, DQ at tDQS2DQ
        make_pattern(4, pat); wr1(0, 10'h030, 0); cas2(10'h030); t_wr = t_last_cmd;
        drive_write(t_wr, TCK*5/4, 500, pat);
        repeat (30) @(posedge ck_t);

        $display("\nexpected (a): beat i = 1<i>(5A^i), (b): 2<i>.., (c): 3<i>.., (d): 4<i>..");
        rd1(0, 10'h000); cas2(10'h000); observe_read("READ col 0x000 (a: DQ centered on raw DQS)");
        rd1(0, 10'h010); cas2(10'h010); observe_read("READ col 0x010 (b: DQ at DQS+tDQS2DQ)");
        rd1(0, 10'h020); cas2(10'h020); observe_read("READ col 0x020 (c: tDQSS=0.75)");
        rd1(0, 10'h030); cas2(10'h030); observe_read("READ col 0x030 (d: tDQSS=1.25)");

        pre_all();
        $display("\n--- probe done @ %t", $time);
        $finish;
    end

endmodule
