`timescale 1ns/1ps

module tb_lpddr5_controller ();

/////////////////////////////////
// Params
/////////////////////////////////
    localparam BANKS = 16;

/////////////////////////////////
// Clock and Reset
/////////////////////////////////

    logic sys_clk   = 1'b0;
    always #5 sys_clk = ~sys_clk; // 100Mhz
    logic sys_rst = 1'b1;

/////////////////////////////////
// PROC <-> Controller
/////////////////////////////////

    // Proc to Controller
    logic           cmd_valid;
    logic           cmd_first;
    logic           cmd_last;
    logic           cmd_payload_we;
    logic [24:0]    cmd_payload_addr;

    // Controller to Proc
    logic cmd_ready;

    // Proc to Controller (Write Data)
    logic           wdata_valid;
    logic           wdata_first;
    logic           wdata_last;
    logic [255:0]   wdata_payload_data;
    logic [31:0]    wdata_payload_we;

    // Controller to Proc (write)
    logic            wdata_ready;

    // Proc to Controller (Read Data)
    logic           rdata_ready;
    logic            rdata_first;
    logic            rdata_last;

    // Controller to Proc (Read Data)
    logic            rdata_valid;
    logic [255:0]    rdata_payload_data;


/////////////////////////////////
// Controller <-> PHY
/////////////////////////////////

    // Controller to PHY
    logic [14:0]                dfi_p0_address;
    logic [$clog2(BANKS)-1:0]   dfi_p0_bank; //16 banks
    logic                       dfi_p0_cas_n;
    logic                       dfi_p0_cs_n; // Chip select
    logic                       dfi_p0_ras_n;
    logic                       dfi_p0_we_n;

    logic dfi_p0_cke;
    logic dfi_p0_odt;
    logic dfi_p0_reset_n;

    // PHY to Controller: Currently undriven ACT signal
    logic dfi_p0_act_n;

    // Controller to PHY: Write Data
    logic [255:0] dfi_p0_wrdata;
    logic         dfi_p0_wrdata_en;
    logic [31:0]  dfi_p0_wrdata_mask;

    // Controller to PHY: Read Enable
    logic dfi_p0_rddata_en;

    // PHY to Controller: Read Data
    logic [255:0] dfi_p0_rddata;
    logic         dfi_p0_rddata_valid;


`include "tb_tasks.svh"

/////////////////////////////////
// Sim
/////////////////////////////////

    initial begin
        set_init();
        repeat(10) @(posedge sys_clk);
        @(negedge sys_clk);
        sys_rst = 1'b0;
        
        $display("lb_lpddr5_controller.sv finished successfully");
        $finish;

    end


lpddr5_controller dut (.*);

endmodule





