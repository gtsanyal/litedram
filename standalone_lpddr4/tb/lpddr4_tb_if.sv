`timescale 1ps/1fs
// Testbench-side view of lpddr4_top: CSR bus and native user port.
interface lpddr4_tb_if (input logic sys_clk);
    import lpddr4_pkg::*;

    // CSR bus (LiteX csr_bus, word addressed, 1-cycle read latency)
    logic [13:0]                    csr_adr   = '0;
    logic                           csr_we    = 1'b0;
    logic                           csr_re    = 1'b0;
    logic [31:0]                    csr_dat_w = '0;
    logic [31:0]                    csr_dat_r;

    // Native port: command
    logic                           cmd_valid = 1'b0;
    logic                           cmd_ready;
    logic                           cmd_we    = 1'b0;
    logic [NATIVE_ADDR_WIDTH-1:0]   cmd_addr  = '0;

    // Native port: write data
    logic                           wdata_valid = 1'b0;
    logic                           wdata_ready;
    logic [NATIVE_DATA_WIDTH-1:0]   wdata_data  = '0;
    logic [NATIVE_DATA_WIDTH/8-1:0] wdata_we    = '0;

    // Native port: read data
    logic                           rdata_valid;
    logic                           rdata_ready = 1'b1;
    logic [NATIVE_DATA_WIDTH-1:0]   rdata_data;
endinterface
