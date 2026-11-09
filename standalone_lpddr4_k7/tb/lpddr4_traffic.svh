// -----------------------------------------------------------------------------
// lpddr4_traffic: LiteDRAM native-port driver with a reference-memory scoreboard.
//
// Address layout of the native port (ROW_BANK_COL): {row, bank, col[COLBITS-1:4]}
// One native word = one BL16 burst (16 beats x 16 bits = 256 bits).
// -----------------------------------------------------------------------------

import lpddr4_pkg::*;

class lpddr4_traffic;

    typedef logic [NATIVE_ADDR_WIDTH-1:0]   addr_t;
    typedef logic [NATIVE_DATA_WIDTH-1:0]   data_t;
    typedef logic [NATIVE_DATA_WIDTH/8-1:0] mask_t;

    virtual lpddr4_tb_if vif;
    typedef struct { addr_t addr; data_t data; } expect_t;

    data_t   mem [addr_t];      // reference memory (unwritten words are unknown)
    expect_t rd_expect [$];     // outstanding reads, in order (LiteDRAM keeps per-port ordering:
                                // a port is locked to one bank until its transaction completes)
    int     writes, reads, errors;
    int     timeout_cycles = 20000;

    function new(virtual lpddr4_tb_if vif);
        this.vif = vif;
    endfunction

    static function automatic addr_t make_addr(input int row, input int bank, input int col);
        return addr_t'((row << (BANKBITS + COLBITS - 4)) | (bank << (COLBITS - 4)) | (col >> 4));
    endfunction

    // ------------------------------------------------------------------ low level
    task automatic send_cmd(input bit we, input addr_t addr);
        int n = 0;
        @(negedge vif.sys_clk);
        vif.cmd_valid = 1'b1;
        vif.cmd_we    = we;
        vif.cmd_addr  = addr;
        do begin
            @(posedge vif.sys_clk);
            if (++n > timeout_cycles) $fatal(1, "native: command timeout (addr=%h)", addr);
        end while (vif.cmd_ready !== 1'b1);
        @(negedge vif.sys_clk);
        vif.cmd_valid = 1'b0;
    endtask

    task automatic send_wdata(input data_t data, input mask_t we);
        int n = 0;
        @(negedge vif.sys_clk);
        vif.wdata_valid = 1'b1;
        vif.wdata_data  = data;
        vif.wdata_we    = we;
        do begin
            @(posedge vif.sys_clk);
            if (++n > timeout_cycles) $fatal(1, "native: write data timeout");
        end while (vif.wdata_ready !== 1'b1);
        @(negedge vif.sys_clk);
        vif.wdata_valid = 1'b0;
    endtask

    // ------------------------------------------------------------------ operations
    task automatic write(input addr_t addr, input data_t data, input mask_t we = '1);
        data_t merged = mem.exists(addr) ? mem[addr] : 'x;
        for (int i = 0; i < NATIVE_DATA_WIDTH/8; i++)
            if (we[i]) merged[8*i +: 8] = data[8*i +: 8];
        mem[addr] = merged;
        writes++;
        fork
            send_cmd(1'b1, addr);
            send_wdata(data, we);
        join
    endtask

    // Reads are pipelined: commands are queued here and checked by the monitor.
    task automatic read(input addr_t addr);
        // Snapshot the expected data now, so later writes to the same address don't affect it.
        rd_expect.push_back('{addr, mem.exists(addr) ? mem[addr] : 'x});
        reads++;
        send_cmd(1'b0, addr);
    endtask

    task automatic wait_reads_done();
        int n = 0;
        while (rd_expect.size() > 0) begin
            @(posedge vif.sys_clk);
            if (++n > timeout_cycles) $fatal(1, "native: %0d read(s) never returned", rd_expect.size());
        end
    endtask

    // Read data monitor / checker (run forever in the background).
    task automatic monitor();
        forever begin
            @(posedge vif.sys_clk);
            if (vif.rdata_valid === 1'b1 && vif.rdata_ready === 1'b1) begin
                expect_t e;
                addr_t   a;
                data_t   exp;
                if (rd_expect.size() == 0) begin
                    $display("[%t] SCOREBOARD: ERROR: unexpected read data %h", $realtime, vif.rdata_data);
                    errors++;
                    continue;
                end
                e   = rd_expect.pop_front();
                a   = e.addr;
                exp = e.data;
                for (int i = 0; i < NATIVE_DATA_WIDTH/8; i++) begin
                    if (exp[8*i +: 8] !== 8'bx && vif.rdata_data[8*i +: 8] !== exp[8*i +: 8]) begin
                        $display("[%t] SCOREBOARD: ERROR: addr %h byte %0d: got %h expected %h",
                                 $realtime, a, i, vif.rdata_data[8*i +: 8], exp[8*i +: 8]);
                        errors++;
                    end
                end
            end
        end
    endtask

    // ------------------------------------------------------------------ tests
    static function automatic data_t random_data();
        data_t d;
        for (int i = 0; i < NATIVE_DATA_WIDTH/32; i++) d[32*i +: 32] = $urandom();
        return d;
    endfunction

    task automatic directed();
        addr_t a [] = '{
            make_addr(0,    0, 0),    make_addr(0,    0, 16),   make_addr(0,    7, 1008),
            make_addr(1,    3, 512),  make_addr(4095, 5, 64),   make_addr(8191, 7, 1008)
        };
        $display("[%t] TRAFFIC: directed write/read of %0d words", $realtime, a.size());
        foreach (a[i]) write(a[i], random_data());
        foreach (a[i]) read(a[i]);
        wait_reads_done();
    endtask

    task automatic masked();
        addr_t a = make_addr(2, 1, 128);
        $display("[%t] TRAFFIC: masked writes (DMI)", $realtime);
        write(a, random_data());
        write(a, random_data(), 32'h0000_00FF);
        write(a, random_data(), 32'hA5A5_0F00);
        write(a, random_data(), 32'h8000_0001);
        read(a);
        wait_reads_done();
    endtask

    // Back-to-back reads of sequential words (seamless bursts on the DQ bus).
    task automatic streaming(input int n = 32);
        addr_t base = make_addr(7, 2, 0);
        $display("[%t] TRAFFIC: %0d sequential writes then back-to-back reads", $realtime, n);
        for (int i = 0; i < n; i++) write(base + i, random_data());
        for (int i = 0; i < n; i++) read(base + i);
        wait_reads_done();
    endtask

    task automatic random_ops(input int n = 200);
        addr_t pool [16];
        $display("[%t] TRAFFIC: %0d random operations", $realtime, n);
        foreach (pool[i]) pool[i] = make_addr($urandom_range(0, 2**ROWBITS-1), $urandom_range(0, 2**BANKBITS-1),
                                              16 * $urandom_range(0, 2**(COLBITS-4)-1));
        foreach (pool[i]) write(pool[i], random_data());
        for (int i = 0; i < n; i++) begin
            addr_t a = pool[$urandom_range(0, 15)];
            case ($urandom_range(0, 2))
                0: write(a, random_data());
                1: write(a, random_data(), mask_t'({$urandom(), $urandom()}));
                2: read(a);
            endcase
        end
        wait_reads_done();
    endtask

endclass
