// -----------------------------------------------------------------------------
// lpddr4_bios: plays the role of the LiteX BIOS for the standalone subsystem.
//
//   * CSR access and DFI injector (DFII) commands
//   * JEDEC LPDDR4 initialization at the boot clock, programming of frequency
//     set point 1 (FSP1) and switch to the operating frequency
//   * PHY training:
//       1. read gate        (rdly_gate<n>, UI)   with MPC READ-DQ-CALIBRATION
//       2. read DQS delay   (rdly_dqs<n>, taps)  with MPC READ-DQ-CALIBRATION
//       3. write DQ delay   (wdly_dq<n>, taps)   with WRITE + READ (tDQS2DQ)
//   * hand-over of the DFI to the LiteDRAM controller
// -----------------------------------------------------------------------------

import lpddr4_pkg::*;

class lpddr4_bios;

    // MPC opcodes (JESD209-4)
    localparam logic [6:0] MPC_READ_DQ_CAL = 7'b1000011;
    localparam logic [6:0] MPC_ZQCAL_START = 7'b1001111;
    localparam logic [6:0] MPC_ZQCAL_LATCH = 7'b1010001;
    // DFI bank values selecting special commands encoded on DFI ZQC (litedram.phy.lpddr4.commands)
    localparam logic [5:0] SPECIAL_MPC = 6'd0;
    localparam logic [5:0] SPECIAL_MRR = 6'd1;
    // Read DQ calibration patterns (MR32: beats 0-7, MR40: beats 8-15, LSB first)
    localparam logic [7:0] DQ_CAL_A = 8'h5A;
    localparam logic [7:0] DQ_CAL_B = 8'h3C;

    localparam int PI_STRIDE = CSR_SDRAM_DFII_PI1_COMMAND_ADDR - CSR_SDRAM_DFII_PI0_COMMAND_ADDR;
    localparam int PHY_BYTE_STRIDE = CSR_DDRPHY_WDLY_DQ1_ADDR - CSR_DDRPHY_WDLY_DQ0_ADDR;

    virtual lpddr4_tb_if vif;
    int errors;

    // Training results
    int gate  [NBYTES];
    int rdqs  [NBYTES];
    int wdq   [NBYTES];

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
        @(negedge vif.sys_clk);          // dat_r is registered on the rising edge in between
        vif.csr_re  = 1'b0;
        value = vif.csr_dat_r;
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

    // LPDDR4 commands through the DFI injector (encodings: litedram/phy/lpddr4/commands.py)
    task automatic mrw(input int ma, input logic [7:0] op);
        dfii_command(0, DFII_COMMAND_RAS | DFII_COMMAND_CAS | DFII_COMMAND_WE | DFII_COMMAND_CS, op, ma[5:0]);
    endtask

    task automatic mpc(input logic [6:0] op, input bit rddata = 1'b0);
        dfii_command(RDPHASE, DFII_COMMAND_WE | DFII_COMMAND_CS | (rddata ? DFII_COMMAND_RDDATA : 6'h0),
                     op, SPECIAL_MPC);
    endtask

    task automatic mrr_cmd(input int ma);
        dfii_command(RDPHASE, DFII_COMMAND_WE | DFII_COMMAND_CS | DFII_COMMAND_RDDATA, ma, SPECIAL_MRR);
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

    task automatic wait_cycles(input int n);
        repeat (n) @(posedge vif.sys_clk);
    endtask

    // ------------------------------------------------------------------ PHY registers
    task automatic set_wdq (input int byte_i, input int taps); csr_write(CSR_DDRPHY_WDLY_DQ0_ADDR   + byte_i*PHY_BYTE_STRIDE, taps); endtask
    task automatic set_rdqs(input int byte_i, input int taps); csr_write(CSR_DDRPHY_RDLY_DQS0_ADDR  + byte_i*PHY_BYTE_STRIDE, taps); endtask
    task automatic set_gate(input int byte_i, input int ui);   csr_write(CSR_DDRPHY_RDLY_GATE0_ADDR + byte_i*PHY_BYTE_STRIDE, ui);   endtask

    // Read with the PHY read FIFO reset beforehand (recovers from misaligned
    // captures during training) and returns the per-byte underflow flags.
    task automatic phy_read(input bit is_mrr, input bit is_cal, input int bank, input int col_or_ma,
                            output logic [DFI_DATABITS*NPHASES-1:0] data, output logic [NBYTES-1:0] underflow);
        logic [31:0] st;
        csr_write(CSR_DDRPHY_RDFIFO_RST_ADDR, 1);
        if (is_cal)      mpc(MPC_READ_DQ_CAL, 1'b1);
        else if (is_mrr) mrr_cmd(col_or_ma);
        else             read_cmd(bank, col_or_ma);
        wait_cycles(READ_LATENCY + 8);
        dfii_get_rddata(data);
        csr_read(CSR_DDRPHY_RDFIFO_STATUS_ADDR, st);
        underflow = st[NBYTES-1:0];
    endtask

    // Byte lane `b` of burst beat `beat` in DFII rddata/wrdata layout:
    // phase p carries beat 2p in bits [DATABITS-1:0] and beat 2p+1 in the upper half.
    static function automatic logic [7:0] lane(input logic [DFI_DATABITS*NPHASES-1:0] d, input int beat, input int b);
        return d[(beat/2)*DFI_DATABITS + (beat%2)*DATABITS + 8*b +: 8];
    endfunction

    // ------------------------------------------------------------------ Initialization
    // Phase 1, at the boot clock: reset, CKE, FSP1 programming, ZQ calibration, FSP-OP switch.
    // The caller must switch the clock to the operating frequency afterwards and call init_fast().
    task automatic init_boot();
        $display("[%t] BIOS: init (boot clock)", $realtime);
        dfii_control(4'h0);                          // software control, RESET_n=0, CKE=0
        #(200us);                                    // tINIT1
        dfii_control(DFII_CONTROL_RESET_N);          // RESET_n=1
        #(2ms);                                      // tINIT3
        dfii_control(DFII_CONTROL_RESET_N | DFII_CONTROL_CKE);
        #(2us);                                      // tINIT5

        // Mode registers of the operating point are written to FSP1 while FSP0 is in use.
        mrw(13, MR13_VALUE | 8'h40);                 // FSP-WR=1
        mrw(1,  MR1_VALUE);
        mrw(2,  MR2_VALUE);
        mrw(3,  MR3_VALUE);
        mrw(11, MR11_VALUE);
        mrw(12, MR12_VALUE);
        mrw(14, MR14_VALUE);

        mpc(MPC_ZQCAL_START);
        #(1us);                                      // tZQCAL
        mpc(MPC_ZQCAL_LATCH);
        #(200ns);                                    // tZQLAT = max(30 ns, 8 tCK)

        mrw(13, MR13_VALUE | 8'h48);                 // VRCG=1 (fast Vref settling) before FSP change
        mrw(13, MR13_VALUE | 8'hC8);                 // FSP-OP=1, FSP-WR=1
        #(100ns);                                    // tCKFSPE
    endtask

    // Phase 2, after the clock switched to the operating frequency.
    task automatic init_fast();
        #(300ns);                                    // tFC + tCKFSPX
        mrw(13, MR13_VALUE | 8'hC0);                 // VRCG back to normal current
        #(200ns);                                    // tVRCG_DISABLE
        $display("[%t] BIOS: running at the operating frequency (FSP1)", $realtime);
    endtask

    // ------------------------------------------------------------------ Training helpers
    task automatic dq_cal_read(output logic [NBYTES-1:0] pass);
        logic [DFI_DATABITS*NPHASES-1:0] d;
        logic [NBYTES-1:0] uf;
        phy_read(1'b0, 1'b1, 0, 0, d, uf);
        for (int b = 0; b < NBYTES; b++) begin
            pass[b] = !uf[b];
            for (int beat = 0; beat < 16; beat++) begin
                logic bitv = (beat < 8) ? DQ_CAL_A[beat] : DQ_CAL_B[beat-8];
                if (lane(d, beat, b) !== {8{bitv}}) pass[b] = 1'b0;
            end
        end
    endtask

    // Center of the longest run of passing settings; -1 if none.
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

    task automatic sweep_report(input string what, input int b, input bit pass[], output int center);
        int first, last;
        center = window_center(pass, first, last);
        $display("[%t] BIOS: %-10s byte%0d |%s| window=[%0d..%0d] -> %0d",
                 $realtime, what, b, pass_map(pass), first, last, center);
        if (center < 0) begin
            $display("[%t] BIOS: ERROR: %s training failed for byte %0d", $realtime, what, b);
            errors++;
        end
    endtask

    // ------------------------------------------------------------------ Training
    task automatic train_read_gate();
        bit pass [NBYTES][];
        logic [NBYTES-1:0] p;
        foreach (pass[b]) pass[b] = new[2**GATE_BITS];
        for (int g = 0; g < 2**GATE_BITS; g++) begin
            for (int b = 0; b < NBYTES; b++) set_gate(b, g);
            dq_cal_read(p);
            for (int b = 0; b < NBYTES; b++) pass[b][g] = p[b];
        end
        for (int b = 0; b < NBYTES; b++) begin
            sweep_report("read gate", b, pass[b], gate[b]);
            set_gate(b, (gate[b] < 0) ? 0 : gate[b]);
        end
    endtask

    task automatic train_read_dqs();
        bit pass [NBYTES][];
        logic [NBYTES-1:0] p;
        foreach (pass[b]) pass[b] = new[NTAPS];
        for (int t = 0; t < NTAPS; t++) begin
            for (int b = 0; b < NBYTES; b++) set_rdqs(b, t);
            dq_cal_read(p);
            for (int b = 0; b < NBYTES; b++) pass[b][t] = p[b];
        end
        for (int b = 0; b < NBYTES; b++) begin
            sweep_report("read DQS", b, pass[b], rdqs[b]);
            set_rdqs(b, (rdqs[b] < 0) ? NTAPS/4 : rdqs[b]);
        end
    endtask

    // Pattern unique per beat and per sweep step (so stale data never passes).
    static function automatic logic [7:0] wr_pattern(input int beat, input int b, input int step);
        return 8'(((beat << 4) | (~beat & 4'hF)) ^ (b * 8'h5A) ^ (step * 8'h3B));
    endfunction

    task automatic train_write_dq(input int bank = 0, input int row = 0, input int col = 0);
        bit pass [NBYTES][];
        logic [DFI_DATABITS*NPHASES-1:0] wd, rd;
        logic [NBYTES-1:0] uf;
        foreach (pass[b]) pass[b] = new[NTAPS];

        activate(bank, row);
        wait_cycles(4);
        for (int t = 0; t < NTAPS; t++) begin
            for (int b = 0; b < NBYTES; b++) set_wdq(b, t);
            for (int beat = 0; beat < 16; beat++)
                for (int b = 0; b < NBYTES; b++)
                    wd[(beat/2)*DFI_DATABITS + (beat%2)*DATABITS + 8*b +: 8] = wr_pattern(beat, b, t);
            dfii_set_wrdata(wd);
            write_cmd(bank, col);
            wait_cycles(8);
            phy_read(1'b0, 1'b0, bank, col, rd, uf);
            for (int b = 0; b < NBYTES; b++) begin
                pass[b][t] = !uf[b];
                for (int beat = 0; beat < 16; beat++)
                    if (lane(rd, beat, b) !== wr_pattern(beat, b, t)) pass[b][t] = 1'b0;
            end
        end
        precharge_all();
        wait_cycles(8);
        for (int b = 0; b < NBYTES; b++) begin
            sweep_report("write DQ", b, pass[b], wdq[b]);
            set_wdq(b, (wdq[b] < 0) ? 0 : wdq[b]);
        end
    endtask

    task automatic check_mode_registers();
        logic [DFI_DATABITS*NPHASES-1:0] d;
        logic [NBYTES-1:0] uf;
        struct { int ma; logic [7:0] exp; string what; } checks [] = '{
            '{5,  8'h08,     "MR5  manufacturer ID (Winbond)"},
            '{8,  8'h30,     "MR8  type/density/width (S16, 1Gb, x16)"},
            '{1,  MR1_VALUE, "MR1  (FSP1)"},
            '{2,  MR2_VALUE, "MR2  (FSP1, RL/WL)"}
        };
        foreach (checks[i]) begin
            phy_read(1'b1, 1'b0, 0, checks[i].ma, d, uf);
            // MRR returns OP[7:0] on DQ[7:0] (first beats)
            if (lane(d, 0, 0) !== checks[i].exp || uf[0]) begin
                $display("[%t] BIOS: ERROR: MRR %s = %h (expected %h, underflow=%b)",
                         $realtime, checks[i].what, lane(d, 0, 0), checks[i].exp, uf);
                errors++;
            end else
                $display("[%t] BIOS: MRR %s = %h OK", $realtime, checks[i].what, lane(d, 0, 0));
        end
    endtask

    task automatic train();
        $display("[%t] BIOS: training", $realtime);
        mrw(32, DQ_CAL_A);
        mrw(40, DQ_CAL_B);
        mrw(15, 8'h00);                              // no per-DQ inversion (lower byte)
        mrw(20, 8'h00);                              // no per-DQ inversion (upper byte)
        train_read_gate();                           // with nominal (1/4 tCK) read DQS delay
        train_read_dqs();
        train_read_gate();                           // re-center the gate with the trained DQS delay
        check_mode_registers();
        train_write_dq();
    endtask

    task automatic handover();
        dfii_control(DFII_CONTROL_SEL | DFII_CONTROL_CKE | DFII_CONTROL_RESET_N | DFII_CONTROL_ODT);
        $display("[%t] BIOS: DFI handed over to the LiteDRAM controller", $realtime);
    endtask

endclass
