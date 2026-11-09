// -----------------------------------------------------------------------------
// Clock / reset generator (PLL model) for lpddr4_top.
//
// All clocks are derived from one tick (UI/2) so that their rising edges are
// phase aligned, as required by the PHY serializers:
//   sys8x_ddr : 1 rising edge per UI  (CK/DQ/DQS bit clock)
//   sys8x     : 1 rising edge per tCK (CA/CS)
//   sys       : 1 rising edge per 8 tCK (controller)
//
// LPDDR4 has to be initialized at a boot clock (tCKb = 18..100 ns), so the PLL
// starts divided by BOOT_DIV and is switched to the operating frequency after
// the frequency set point change (set_fast). Switches happen on a sys-cycle
// boundary, so the phase relationship of all clocks is preserved.
// -----------------------------------------------------------------------------
`timescale 1ps/1fs

module lpddr4_crg #(
    parameter realtime UI_PS    = 625.0,    // LPDDR4-1600
    parameter int      BOOT_DIV = 16        // 50 MHz CK during initialization
) (
    output logic sys_clk       = 1'b1,
    output logic sys8x_clk     = 1'b1,
    output logic sys8x_ddr_clk = 1'b1,
    output logic rst           = 1'b1
);
    localparam int TICKS_PER_SYS = 32;

    realtime     tick     = UI_PS / 2.0 * BOOT_DIV;
    bit          fast     = 1'b0;
    bit          fast_req = 1'b0;
    int unsigned n        = 0;

    always begin
        #(tick);
        n = (n + 1) % TICKS_PER_SYS;
        sys8x_ddr_clk = (n % 2) == 0;
        sys8x_clk     = (n % 4) < 2;
        sys_clk       = n < TICKS_PER_SYS/2;
        if (n == 0 && fast != fast_req) begin
            fast = fast_req;
            tick = UI_PS / 2.0 * (fast ? 1 : BOOT_DIV);
        end
    end

    // Change the PLL output frequency (applied at the next sys-cycle boundary).
    task automatic set_fast(input bit f);
        fast_req = f;
        wait (fast == f);
        $display("[%t] CRG: CK period now %0.1f ps", $realtime, 4.0 * tick);
    endtask

    // Release the reset synchronously to a sys rising edge (serializers rely on it).
    task automatic release_reset(input int sys_cycles = 16);
        repeat (sys_cycles) @(posedge sys_clk);
        rst <= 1'b0;
    endtask
endmodule
