// -----------------------------------------------------------------------------
// lpddr4_bios (Kintex-7 PHY): plays the role of the LiteX BIOS.
//
// Everything here goes through the same CSRs the CPU uses on the board, so the
// sequence can be ported 1:1 to the BIOS C code.
//
// Initialization (JESD209-4 with frequency set points):
//   1. PHY starts in boot mode (50 MHz CK from the OSERDESE2, tCKb >= 18 ns).
//   2. RESET_n/CKE sequence, FSP1 programming (operating point), ZQ calibration.
//   3. FSP-OP switch, then the frequency change in power-down (CKE low):
//      boot_mode=0 -> the same OSERDESE2 now emits the 400 MHz CK.
//
// Training (K7LPDDR4PHY: clock-based read capture, IDELAY/ODELAY 78 ps taps):
//   1. Read leveling with MPC READ-DQ-CALIBRATION: DQ IDELAY taps x read bitslip.
//   2. Write leveling (MR2 OP7): DQS ODELAY so that DQS rises with CK (tDQSS).
//   3. Write latency + write DQ-DQS training: write bitslip x DQ ODELAY taps
//      (DRAM samples DQ at DQS + tDQS2DQ).
// -----------------------------------------------------------------------------

import lpddr4_pkg::*;

// Mode register commands decoded from the CA bus at the DRAM pins by the testbench monitor
// (tb_lpddr4_k7.sv), so the BIOS can check that each MRW/MRR arrived with the intended MA/OP.
package lpddr4_ca_mon;
    typedef struct { int ma; logic [7:0] op; } mrw_t;
    mrw_t mrw_q [$];
    int   mrr_q [$];
endpackage

class lpddr4_bios;

    localparam logic [6:0] MPC_READ_DQ_CAL = 7'b1000011;
    localparam logic [6:0] MPC_ZQCAL_START = 7'b1001111;
    localparam logic [6:0] MPC_ZQCAL_LATCH = 7'b1010001;
    localparam logic [5:0] SPECIAL_MPC = 6'd0;
    localparam logic [5:0] SPECIAL_MRR = 6'd1;
    localparam logic [7:0] DQ_CAL_A = 8'h5A;
    localparam logic [7:0] DQ_CAL_B = 8'h3C;

    localparam int PI_STRIDE = CSR_SDRAM_DFII_PI1_COMMAND_ADDR - CSR_SDRAM_DFII_PI0_COMMAND_ADDR;

    virtual lpddr4_tb_if vif;
    int errors;

    // Training results (per byte)
    int rd_bitslip [NBYTES];
    int rd_dq_tap  [NBYTES];
    int wr_dqs_tap [NBYTES];
    int ck_tap;
    int wr_bitslip [NBYTES];
    int wr_dq_tap  [NBYTES];

    function new(virtual lpddr4_tb_if vif);
        this.vif    = vif;
        this.errors = 0;
    endfunction

    // ------------------------------------------------------------------ CSR access
    task automatic csr_write(input int adr, input logic [31:0] value);
        @(negedge vif.sys_clk);
        vif.csr_adr   = adr[13:0];
        vif.csr_dat_w = value;
        vif.csr_we    = 1'b1;
        @(negedge vif.sys_clk);
        vif.csr_we    = 1'b0;
    endtask

    task automatic csr_read(input int adr, output logic [31:0] value);
        @(negedge vif.sys_clk);
        vif.csr_adr = adr[13:0];
        vif.csr_re  = 1'b1;
        @(negedge vif.sys_clk);
        vif.csr_re  = 1'b0;
        value = vif.csr_dat_r;
    endtask

    task automatic wait_cycles(input int n);
        repeat (n) @(posedge vif.sys_clk);
    endtask

    // ------------------------------------------------------------------ DFII
    task automatic dfii_control(input logic [3:0] flags);
        csr_write(CSR_SDRAM_DFII_CONTROL_ADDR, flags);
    endtask

    task automatic dfii_command(input int phase, input logic [5:0] cmd,
                                input logic [16:0] address, input logic [5:0] bank);
        int base = phase * PI_STRIDE;
        csr_write(CSR_SDRAM_DFII_PI0_ADDRESS_ADDR  + base, address);
        csr_write(CSR_SDRAM_DFII_PI0_BADDRESS_ADDR + base, bank);
        csr_write(CSR_SDRAM_DFII_PI0_COMMAND_ADDR  + base, cmd);
        csr_write(CSR_SDRAM_DFII_PI0_COMMAND_ISSUE_ADDR + base, 1);
    endtask

    task automatic dfii_set_wrdata(input logic [DFI_DATABITS*NPHASES-1:0] data);
        for (int p = 0; p < NPHASES; p++)
            csr_write(CSR_SDRAM_DFII_PI0_WRDATA_ADDR + p*PI_STRIDE, data[p*DFI_DATABITS +: DFI_DATABITS]);
    endtask

    task automatic dfii_get_rddata(output logic [DFI_DATABITS*NPHASES-1:0] data);
        logic [31:0] v;
        for (int p = 0; p < NPHASES; p++) begin
            csr_read(CSR_SDRAM_DFII_PI0_RDDATA_ADDR + p*PI_STRIDE, v);
            data[p*DFI_DATABITS +: DFI_DATABITS] = v;
        end
    endtask

    // tMRW / tMRD / tMRWCKEL = max(14 ns, 10 tCK) and tVRCG_ENABLE = 200 ns; in boot mode
    // tCK = 20 ns, so 10 tCK = 200 ns. 300 ns also covers the CSR -> pad pipeline latency.
    // (BIOS C code: cdelay of the same length after every MRW.)
    task automatic mrw(input int ma, input logic [7:0] op);
        lpddr4_ca_mon::mrw_q.delete();
        dfii_command(0, DFII_COMMAND_RAS | DFII_COMMAND_CAS | DFII_COMMAND_WE | DFII_COMMAND_CS, op, ma[5:0]);
        #(300ns);
        check_pins_mrw(ma, op);
    endtask

    // The MRW must have reached the DRAM pins exactly once, with this MA and OP.
    task automatic check_pins_mrw(input int ma, input logic [7:0] op);
        if (lpddr4_ca_mon::mrw_q.size() != 1 || lpddr4_ca_mon::mrw_q[0].ma != ma || lpddr4_ca_mon::mrw_q[0].op !== op) begin
            $display("[%t] BIOS: ERROR: MRW MR%0d=%h not seen at the DRAM pins (monitor saw %0d MRW: %p)",
                     $realtime, ma, op, lpddr4_ca_mon::mrw_q.size(), lpddr4_ca_mon::mrw_q);
            errors++;
        end
        lpddr4_ca_mon::mrw_q.delete();
    endtask

    task automatic mpc(input logic [6:0] op, input bit rddata = 1'b0);
        dfii_command(RDPHASE, DFII_COMMAND_WE | DFII_COMMAND_CS | (rddata ? DFII_COMMAND_RDDATA : 6'h0),
                     op, SPECIAL_MPC);
    endtask

    task automatic mrr_cmd(input int ma);
        dfii_command(RDPHASE, DFII_COMMAND_WE | DFII_COMMAND_CS | DFII_COMMAND_RDDATA, ma, SPECIAL_MRR);
    endtask

    // MRR and return OP (DQ[7:0], first beat); also checks the MRR reached the pins with this MA.
    task automatic mrr(input int ma, output logic [7:0] op);
        logic [DFI_DATABITS*NPHASES-1:0] d;
        lpddr4_ca_mon::mrr_q.delete();
        mrr_cmd(ma);
        wait_cycles(READ_LATENCY + 8);
        dfii_get_rddata(d);
        op = lane(d, 0, 0);
        if (lpddr4_ca_mon::mrr_q.size() != 1 || lpddr4_ca_mon::mrr_q[0] != ma) begin
            $display("[%t] BIOS: ERROR: MRR MR%0d not seen at the DRAM pins (monitor saw %p)",
                     $realtime, ma, lpddr4_ca_mon::mrr_q);
            errors++;
        end
        lpddr4_ca_mon::mrr_q.delete();
    endtask

    task automatic activate(input int bank, input int row);
        dfii_command(0, DFII_COMMAND_RAS | DFII_COMMAND_CS, row, bank);
    endtask

    task automatic write_cmd(input int bank, input int col);
        dfii_command(WRPHASE, DFII_COMMAND_CAS | DFII_COMMAND_WE | DFII_COMMAND_CS | DFII_COMMAND_WRDATA, col, bank);
    endtask

    task automatic read_cmd(input int bank, input int col);
        dfii_command(RDPHASE, DFII_COMMAND_CAS | DFII_COMMAND_CS | DFII_COMMAND_RDDATA, col, bank);
    endtask

    task automatic precharge_all();
        dfii_command(0, DFII_COMMAND_RAS | DFII_COMMAND_WE | DFII_COMMAND_CS, 17'h400, 0);
    endtask

    // ------------------------------------------------------------------ PHY delay controls
    // Delays and bitslips are changed with reset/increment pulses on the bytes
    // selected by dly_sel (IDELAYE2/ODELAYE2 in VARIABLE mode, LD/CE).
    task automatic dly_sel(input logic [NBYTES-1:0] mask);
        csr_write(CSR_DDRPHY_DLY_SEL_ADDR, mask);
    endtask

    task automatic pulse(input int adr, input int n = 1);
        repeat (n) csr_write(adr, 1);
    endtask

    task automatic set_rdly_dq     (input int byte_i, input int taps); dly_sel(1 << byte_i); pulse(CSR_DDRPHY_RDLY_DQ_RST_ADDR);         pulse(CSR_DDRPHY_RDLY_DQ_INC_ADDR, taps);      endtask
    task automatic set_rd_bitslip  (input int byte_i, input int n);    dly_sel(1 << byte_i); pulse(CSR_DDRPHY_RDLY_DQ_BITSLIP_RST_ADDR); pulse(CSR_DDRPHY_RDLY_DQ_BITSLIP_ADDR, n);  endtask
    task automatic set_wdly_dq     (input int byte_i, input int taps); dly_sel(1 << byte_i); pulse(CSR_DDRPHY_WDLY_DQ_RST_ADDR);         pulse(CSR_DDRPHY_WDLY_DQ_INC_ADDR, taps);      endtask
    task automatic set_wr_bitslip  (input int byte_i, input int n);    dly_sel(1 << byte_i); pulse(CSR_DDRPHY_WDLY_DQ_BITSLIP_RST_ADDR); pulse(CSR_DDRPHY_WDLY_DQ_BITSLIP_ADDR, n);  endtask
    // DQS ODELAY: reset loads the 90 degree value (HALF_SYS8X_TAPS); set absolute value.
    task automatic set_wdly_dqs    (input int byte_i, input int taps);
        dly_sel(1 << byte_i);
        pulse(CSR_DDRPHY_WDLY_DQS_RST_ADDR);
        if (taps < HALF_SYS8X_TAPS) $fatal(1, "DQS ODELAY below its reset value is not reachable with inc pulses");
        pulse(CSR_DDRPHY_WDLY_DQS_INC_ADDR, taps - HALF_SYS8X_TAPS);
    endtask

    // ------------------------------------------------------------------ helpers
    static function automatic logic [7:0] lane(input logic [DFI_DATABITS*NPHASES-1:0] d, input int beat, input int b);
        return d[(beat/2)*DFI_DATABITS + (beat%2)*DATABITS + 8*b +: 8];
    endfunction

    static function automatic int window_center(input bit pass[], output int first, output int last);
        int best_len = 0, len = 0, start = 0;
        first = -1; last = -1;
        for (int i = 0; i < pass.size(); i++) begin
            if (pass[i]) begin
                if (len == 0) start = i;
                len++;
                if (len > best_len) begin best_len = len; first = start; last = i; end
            end else len = 0;
        end
        return (best_len == 0) ? -1 : (first + last) / 2;
    endfunction

    static function automatic string pass_map(input bit pass[]);
        string s = "";
        foreach (pass[i]) s = {s, pass[i] ? "#" : "."};
        return s;
    endfunction

    // ------------------------------------------------------------------ Initialization
    task automatic init();
        $display("[%t] BIOS: init at the boot clock (PHY boot mode, %0d ns CK)", $realtime,
                 BOOT_CLK_DIV * SYS_CLK_PERIOD_PS / 1000);
        dfii_control(4'h0);                                      // software control, RESET_n=0, CKE=0
        #(200us);                                                // tINIT1
        dfii_control(DFII_CONTROL_RESET_N | DFII_CONTROL_ODT);
        #(2ms);                                                  // tINIT3
        dfii_control(DFII_CONTROL_RESET_N | DFII_CONTROL_ODT | DFII_CONTROL_CKE);
        #(2us);                                                  // tINIT5

        mrw(13, MR13_VALUE | 8'h40);                             // FSP-WR=1: program the operating point
        mrw(1,  MR1_VALUE);
        mrw(2,  MR2_VALUE);
        mrw(3,  MR3_VALUE);
        mrw(11, MR11_VALUE);
        mrw(12, MR12_VALUE);
        mrw(14, MR14_VALUE);

        mpc(MPC_ZQCAL_START);
        #(1us);                                                  // tZQCAL
        mpc(MPC_ZQCAL_LATCH);
        #(200ns);                                                // tZQLAT

        mrw(13, MR13_VALUE | 8'h48);                             // VRCG=1 before the FSP change
        mrw(13, MR13_VALUE | 8'hC8);                             // FSP-OP=1
        #(200ns);

        // Frequency change in power-down: CKE low, switch CK, CKE high.
        dfii_control(DFII_CONTROL_RESET_N | DFII_CONTROL_ODT);   // CKE low (tCKELCK with boot CK)
        #(200ns);
        csr_write(CSR_DDRPHY_BOOT_MODE_ADDR, 0);                 // CK: 50 MHz -> 400 MHz (same OSERDESE2)
        #(200ns);                                                // tCKCKEH / tCKFSPX
        dfii_control(DFII_CONTROL_RESET_N | DFII_CONTROL_ODT | DFII_CONTROL_CKE);
        #(300ns);                                                // tXP + tFC
        mrw(13, MR13_VALUE | 8'hC0);                             // VRCG back to normal
        #(200ns);
        $display("[%t] BIOS: running at the operating frequency (FSP1)", $realtime);
    endtask

    // ------------------------------------------------------------------ Read leveling
    task automatic dq_cal_read(output logic [NBYTES-1:0] pass);
        logic [DFI_DATABITS*NPHASES-1:0] d;
        mpc(MPC_READ_DQ_CAL, 1'b1);
        wait_cycles(READ_LATENCY + 8);
        dfii_get_rddata(d);
        for (int b = 0; b < NBYTES; b++) begin
            pass[b] = 1'b1;
            for (int beat = 0; beat < 16; beat++) begin
                logic bitv = (beat < 8) ? DQ_CAL_A[beat] : DQ_CAL_B[beat-8];
                if (lane(d, beat, b) !== {8{bitv}}) pass[b] = 1'b0;
            end
        end
    endtask

    task automatic train_read();
        bit pass [NBYTES][BITSLIPS][];
        logic [NBYTES-1:0] p;
        int best_len [NBYTES];
        $display("[%t] BIOS: read leveling (READ-DQ-CAL; %0d bitslips x %0d IDELAY taps of %0.1f ps)",
                 $realtime, BITSLIPS, DELAYS, TAP_PS);
        foreach (pass[b, s]) pass[b][s] = new[DELAYS];
        for (int s = 0; s < BITSLIPS; s++) begin
            for (int b = 0; b < NBYTES; b++) set_rd_bitslip(b, s);
            dly_sel('1);
            pulse(CSR_DDRPHY_RDLY_DQ_RST_ADDR);
            for (int t = 0; t < DELAYS; t++) begin
                if (t > 0) begin dly_sel('1); pulse(CSR_DDRPHY_RDLY_DQ_INC_ADDR); end
                dq_cal_read(p);
                for (int b = 0; b < NBYTES; b++) pass[b][s][t] = p[b];
            end
        end
        for (int b = 0; b < NBYTES; b++) begin
            best_len[b] = 0; rd_bitslip[b] = -1;
            for (int s = 0; s < BITSLIPS; s++) begin
                int first, last, c;
                c = window_center(pass[b][s], first, last);
                if (c >= 0) $display("[%t] BIOS:   byte%0d bitslip %2d |%s| [%0d..%0d]",
                                     $realtime, b, s, pass_map(pass[b][s]), first, last);
                if (c >= 0 && last - first + 1 > best_len[b]) begin
                    best_len[b] = last - first + 1; rd_bitslip[b] = s; rd_dq_tap[b] = c;
                end
            end
            if (rd_bitslip[b] < 0) begin
                $display("[%t] BIOS: ERROR: read leveling failed for byte %0d", $realtime, b);
                errors++;
                rd_bitslip[b] = 0; rd_dq_tap[b] = 0;
            end else
                $display("[%t] BIOS: read leveling byte%0d -> bitslip %0d, IDELAY %0d taps (window %0d taps)",
                         $realtime, b, rd_bitslip[b], rd_dq_tap[b], best_len[b]);
            set_rd_bitslip(b, rd_bitslip[b]);
            set_rdly_dq(b, rd_dq_tap[b]);
        end
    endtask

    // ------------------------------------------------------------------ Write leveling
    // DRAM in write leveling mode samples CK with each DQS rising edge and returns the level on DQ.
    //
    // DQS ODELAY can only go from its reset value (HALF_SYS8X_TAPS) to DELAYS-1, i.e. 3/4 of a
    // tCK (32 taps): a CK 0->1 edge in the remaining quarter is not seen. If any byte has no edge,
    // delay CK/CA (one shared ODELAY) by CK_SHIFTS taps and sweep again: every edge moves later by
    // the same amount (all bytes must fit in one 23-tap window: byte-to-byte DQS skew up to
    // ~1.5 ns). Read leveling depends on the CK delay, so it runs after this.
    localparam int CK_SHIFTS [7] = '{0, 4, 8, 12, 16, 20, 24};

    // CK, CA, CS, CKE and ODT share one ODELAY; change it in power-down (CKE low), as for the
    // frequency change in init(): tCKELCK / tCKCKEH / tXP all well below 100 ns at 400 MHz.
    task automatic set_ck_delay(input int taps);
        dfii_control(DFII_CONTROL_RESET_N | DFII_CONTROL_ODT);
        #(100ns);
        pulse(CSR_DDRPHY_CDLY_RST_ADDR);
        pulse(CSR_DDRPHY_CDLY_INC_ADDR, taps);
        #(100ns);
        dfii_control(DFII_CONTROL_RESET_N | DFII_CONTROL_ODT | DFII_CONTROL_CKE);
        #(100ns);
    endtask

    task automatic write_leveling_sweep(output bit level [NBYTES][]);
        logic [DFI_DATABITS*NPHASES-1:0] d;
        foreach (level[b]) level[b] = new[DELAYS];
        mrw(2, MR2_VALUE | 8'h80);                               // MR2 OP7: write leveling
        wait_cycles(16);
        csr_write(CSR_DDRPHY_WLEVEL_EN_ADDR, 1);
        wait_cycles(16);
        for (int t = HALF_SYS8X_TAPS; t < DELAYS; t++) begin
            for (int b = 0; b < NBYTES; b++) set_wdly_dqs(b, t);
            pulse(CSR_DDRPHY_WLEVEL_STROBE_ADDR);
            wait_cycles(16);                                     // tWLO
            dfii_get_rddata(d);
            for (int b = 0; b < NBYTES; b++) begin
                int ones = 0;
                for (int beat = 0; beat < 16; beat++)
                    for (int i = 0; i < 8; i++) ones += (lane(d, beat, b)[i] === 1'b1);
                level[b][t] = (ones > 8*16/2);
            end
        end
        csr_write(CSR_DDRPHY_WLEVEL_EN_ADDR, 0);
        mrw(2, MR2_VALUE);
        wait_cycles(16);
    endtask

    task automatic train_write_leveling();
        bit level [NBYTES][];
        int tap [NBYTES];
        bit ok;
        foreach (CK_SHIFTS[k]) begin
            if (k > 0 && $test$plusargs("WL_NO_RETRY")) break;   // debug: old behaviour
            ck_tap = CK_SHIFTS[k];
            if (k > 0) begin
                $display("[%t] BIOS: write leveling: retrying with CK/CA ODELAY %0d taps", $realtime, ck_tap);
                set_ck_delay(ck_tap);
            end
            $display("[%t] BIOS: write leveling (DQS ODELAY %0d..%0d taps, CK ODELAY %0d)",
                     $realtime, HALF_SYS8X_TAPS, DELAYS-1, ck_tap);
            write_leveling_sweep(level);
            ok = 1;
            for (int b = 0; b < NBYTES; b++) begin
                string s = "";
                tap[b] = -1;
                for (int t = 0; t < DELAYS; t++) begin
                    s = {s, (t < HALF_SYS8X_TAPS) ? " " : (level[b][t] ? "1" : "0")};
                    if (t > HALF_SYS8X_TAPS && tap[b] < 0 && level[b][t] && !level[b][t-1]) tap[b] = t;
                end
                $display("[%t] BIOS: write leveling byte%0d |%s| -> %s", $realtime, b, s,
                         tap[b] < 0 ? "no CK 0->1 edge" : $sformatf("DQS ODELAY %0d taps", tap[b]));
                if (tap[b] < 0) ok = 0;
            end
            if (ok) break;
        end
        if (!ok) begin
            $display("[%t] BIOS: ERROR: write leveling failed at every CK delay", $realtime);
            errors++;
            foreach (tap[b]) if (tap[b] < 0) tap[b] = HALF_SYS8X_TAPS;
        end
        for (int b = 0; b < NBYTES; b++) begin
            wr_dqs_tap[b] = tap[b];
            set_wdly_dqs(b, wr_dqs_tap[b]);
        end
    endtask

    // ------------------------------------------------------------------ Write latency + DQ-DQS training
    static function automatic logic [7:0] wr_pattern(input int beat, input int b, input int step);
        return 8'(((beat << 4) | (~beat & 4'hF)) ^ (b * 8'h5A) ^ (step * 8'h3B));
    endfunction

    task automatic write_read_check(input int step, output logic [NBYTES-1:0] pass);
        logic [DFI_DATABITS*NPHASES-1:0] wd, rd;
        for (int beat = 0; beat < 16; beat++)
            for (int b = 0; b < NBYTES; b++)
                wd[(beat/2)*DFI_DATABITS + (beat%2)*DATABITS + 8*b +: 8] = wr_pattern(beat, b, step);
        dfii_set_wrdata(wd);
        write_cmd(0, 0);
        wait_cycles(8);
        read_cmd(0, 0);
        wait_cycles(READ_LATENCY + 8);
        dfii_get_rddata(rd);
        for (int b = 0; b < NBYTES; b++) begin
            pass[b] = 1'b1;
            for (int beat = 0; beat < 16; beat++)
                if (lane(rd, beat, b) !== wr_pattern(beat, b, step)) pass[b] = 1'b0;
        end
    endtask

    task automatic train_write_dq();
        bit pass [NBYTES][BITSLIPS][];
        logic [NBYTES-1:0] p;
        int best_len [NBYTES];
        int step = 0;
        $display("[%t] BIOS: write latency + DQ-DQS training (%0d bitslips x %0d ODELAY taps)",
                 $realtime, BITSLIPS, DELAYS);
        foreach (pass[b, s]) pass[b][s] = new[DELAYS];
        activate(0, 0);
        wait_cycles(4);
        for (int s = 0; s < BITSLIPS; s++) begin
            for (int b = 0; b < NBYTES; b++) set_wr_bitslip(b, s);
            dly_sel('1);
            pulse(CSR_DDRPHY_WDLY_DQ_RST_ADDR);
            for (int t = 0; t < DELAYS; t++) begin
                if (t > 0) begin dly_sel('1); pulse(CSR_DDRPHY_WDLY_DQ_INC_ADDR); end
                write_read_check(step++, p);
                for (int b = 0; b < NBYTES; b++) pass[b][s][t] = p[b];
            end
        end
        precharge_all();
        wait_cycles(8);
        for (int b = 0; b < NBYTES; b++) begin
            best_len[b] = 0; wr_bitslip[b] = -1;
            for (int s = 0; s < BITSLIPS; s++) begin
                int first, last, c;
                c = window_center(pass[b][s], first, last);
                if (c >= 0) $display("[%t] BIOS:   byte%0d bitslip %2d |%s| [%0d..%0d]",
                                     $realtime, b, s, pass_map(pass[b][s]), first, last);
                if (c >= 0 && last - first + 1 > best_len[b]) begin
                    best_len[b] = last - first + 1; wr_bitslip[b] = s; wr_dq_tap[b] = c;
                end
            end
            if (wr_bitslip[b] < 0) begin
                $display("[%t] BIOS: ERROR: write DQ training failed for byte %0d", $realtime, b);
                errors++;
                wr_bitslip[b] = 0; wr_dq_tap[b] = 0;
            end else
                $display("[%t] BIOS: write training byte%0d -> bitslip %0d, DQ ODELAY %0d taps (window %0d taps)",
                         $realtime, b, wr_bitslip[b], wr_dq_tap[b], best_len[b]);
            set_wr_bitslip(b, wr_bitslip[b]);
            set_wdly_dq(b, wr_dq_tap[b]);
        end
    endtask

    // ------------------------------------------------------------------ Checks / sequence
    task automatic check_mode_registers();
        logic [7:0] v;
        struct { int ma; logic [7:0] exp; string what; } checks [] = '{
            '{5,  8'h08,      "MR5  manufacturer ID (Winbond)"},
            '{8,  8'h30,      "MR8  type/density/width (S16, 1Gb, x16)"},
            '{1,  MR1_VALUE,  "MR1  (FSP1)"},
            '{2,  MR2_VALUE,  "MR2  (FSP1, RL/WL)"},
            '{3,  MR3_VALUE,  "MR3  (FSP1, PDDS/PU-CAL/DBI)"},
            '{11, MR11_VALUE, "MR11 (FSP1, ODT)"},
            '{12, MR12_VALUE, "MR12 (FSP1, VREF CA)"},
            '{14, MR14_VALUE, "MR14 (FSP1, VREF DQ)"}
        };
        foreach (checks[i]) begin
            mrr(checks[i].ma, v);
            if (v !== checks[i].exp) begin
                $display("[%t] BIOS: ERROR: MRR %s = %h (expected %h)", $realtime, checks[i].what, v, checks[i].exp);
                errors++;
            end else
                $display("[%t] BIOS: MRR %s = %h OK", $realtime, checks[i].what, v);
        end
    endtask

    // ------------------------------------------------------------------ Unused-slot probe
    // MRW/MRR to mode registers / values LPDDR4 does not define. Runs by default in simulation
    // (+NO_MR_PROBE to skip); NOT part of a real-board BIOS. Checks:
    //  * every MRW/MRR reaches the DRAM pins with the intended MA/OP (pin monitor, in mrw/mrr);
    //  * each unused MA either stores both patterns (pat, ~pat), stores some bits with the rest
    //    constant (e.g. Winbond MR31 keeps OP[1:0] - undocumented, never write it on the board),
    //    ignores writes (reads its old value), or reads X (no storage in this model) - anything
    //    else is an error;
    //  * no aliasing: no MA reads back a pattern written to a different MA (all MAs are written
    //    first, then all read back);
    //  * the defined registers are unchanged afterwards (read-only MRs + check_mode_registers).
    // Skips MRs with side effects: MR9 vendor test, MR10 ZQ reset, MR24/25 TRR/PPR (PPR is a
    // permanent fuse repair on silicon), MR39 (reserved for DRAM test), MR51 (LPDDR4X
    // single-ended modes).
    localparam int PROBE_MAS [] = '{26, 27, 28, 29, 30, 31, 33, 34, 35, 36, 37, 38, 41, 42, 43, 44, 45, 46, 47,
                                    48, 49, 50, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63};
    localparam int PROBE_RO_MAS [] = '{0, 5, 6, 7, 8};             // read-only MRs, must not change

    static function automatic logic [7:0] probe_pat(input int ma);
        return 8'hA5 ^ 8'(ma);                                   // unique per MA, never 00/FF
    endfunction

    task automatic mr_probe();
        int n = PROBE_MAS.size();
        logic [7:0] pre [], rb1 [], rb2 [], ro_pre [], v_post;
        int n_stored = 0, n_partial = 0, n_ignored = 0, n_x = 0, n_bad = 0;
        pre = new[n]; rb1 = new[n]; rb2 = new[n]; ro_pre = new[PROBE_RO_MAS.size()];
        $display("[%t] BIOS: MR probe: %0d unused mode register addresses", $realtime, n);
        foreach (PROBE_RO_MAS[i]) mrr(PROBE_RO_MAS[i], ro_pre[i]);
        foreach (PROBE_MAS[i]) mrr(PROBE_MAS[i], pre[i]);
        foreach (PROBE_MAS[i]) mrw(PROBE_MAS[i], probe_pat(PROBE_MAS[i]));
        foreach (PROBE_MAS[i]) mrr(PROBE_MAS[i], rb1[i]);
        foreach (PROBE_MAS[i]) mrw(PROBE_MAS[i], ~probe_pat(PROBE_MAS[i]));
        foreach (PROBE_MAS[i]) mrr(PROBE_MAS[i], rb2[i]);
        foreach (PROBE_MAS[i]) begin
            int ma = PROBE_MAS[i];
            logic [7:0] pat = probe_pat(ma);
            string res;
            // per bit: "stored" follows both writes, "constant" reads the same value both times
            logic [7:0] stored_bits = ~(rb1[i] ^ pat) & ~(rb2[i] ^ ~pat);
            logic [7:0] const_bits  = ~(rb1[i] ^ rb2[i]);
            if (rb1[i] === pat && rb2[i] === ~pat) begin
                res = "STORED"; n_stored++;
            end else if ($isunknown(rb1[i]) || $isunknown(rb2[i])) begin
                res = "reads X (no storage in this model)"; n_x++;
            end else if (rb1[i] === pre[i] && rb2[i] === pre[i]) begin
                res = "ignored (MRW has no effect)"; n_ignored++;
            end else if ((stored_bits | const_bits) === 8'hFF) begin
                res = $sformatf("PARTIAL: bits %b stored, other bits read constant", stored_bits);
                n_partial++;
            end else begin
                res = "ERROR: inconsistent";
                foreach (PROBE_MAS[j])
                    if (j != i && (rb1[i] === probe_pat(PROBE_MAS[j]) || rb2[i] === ~probe_pat(PROBE_MAS[j])))
                        res = $sformatf("ERROR: aliases MR%0d", PROBE_MAS[j]);
                n_bad++;
            end
            $display("[%t] BIOS:   MR%0d: before %h  wrote %h, %h  read back %h, %h  %s", $realtime, ma,
                     pre[i], pat, ~pat, rb1[i], rb2[i], res);
        end
        foreach (PROBE_MAS[i]) mrw(PROBE_MAS[i], $isunknown(pre[i]) ? 8'h00 : pre[i]);  // leave as found
        foreach (PROBE_RO_MAS[i]) begin
            mrr(PROBE_RO_MAS[i], v_post);
            if (v_post !== ro_pre[i]) begin
                $display("[%t] BIOS: ERROR: MR%0d changed by the probe: %h -> %h", $realtime, PROBE_RO_MAS[i],
                         ro_pre[i], v_post);
                n_bad++;
            end
        end
        errors += n_bad;
        $display("[%t] BIOS: MR probe: %0d stored, %0d partial, %0d ignored, %0d read X, %0d errors (aliasing/inconsistent/RO changed)",
                 $realtime, n_stored, n_partial, n_ignored, n_x, n_bad);
        $display("[%t] BIOS: MR probe: defined registers after the probe:", $realtime);
        check_mode_registers();
        $display("[%t] BIOS: MR probe: reserved values in defined registers", $realtime);
        begin
            struct { int ma; logic [7:0] val, restore; string what; } rv [] = '{
                '{3,  (MR3_VALUE  & 8'hC7) | 8'h38, MR3_VALUE,  "MR3 PDDS=7 (reserved)"},
                '{3,  (MR3_VALUE  & 8'hC7),         MR3_VALUE,  "MR3 PDDS=0 (reserved)"},
                '{11, (MR11_VALUE & 8'hF8) | 8'h07, MR11_VALUE, "MR11 DQ ODT=7 (reserved)"}
            };
            foreach (rv[i]) begin
                mrw(rv[i].ma, rv[i].val);
                mrr(rv[i].ma, v_post);
                $display("[%t] BIOS:   %s: wrote %h read back %h  %s", $realtime, rv[i].what, rv[i].val, v_post,
                         v_post === rv[i].val ? "STORED" : "not stored");
                mrw(rv[i].ma, rv[i].restore);
                mrr(rv[i].ma, v_post);
                if (v_post !== rv[i].restore) begin
                    $display("[%t] BIOS: ERROR: MR%0d not restored (%h)", $realtime, rv[i].ma, v_post);
                    errors++;
                end
            end
        end
    endtask

    task automatic train();
        $display("[%t] BIOS: training", $realtime);
        mrw(32, DQ_CAL_A);
        mrw(40, DQ_CAL_B);
        mrw(15, 8'h00);
        mrw(20, 8'h00);
        train_write_leveling();                                  // may move CK: before read leveling
        train_read();
        check_mode_registers();
        if (!$test$plusargs("NO_MR_PROBE")) mr_probe();          // simulation only, see mr_probe()
        train_write_dq();
    endtask

    task automatic handover();
        dfii_control(DFII_CONTROL_SEL | DFII_CONTROL_CKE | DFII_CONTROL_RESET_N | DFII_CONTROL_ODT);
        $display("[%t] BIOS: DFI handed over to the LiteDRAM controller", $realtime);
    endtask

endclass
