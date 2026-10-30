`timescale 1ns/1ps
`include "lpddr5_if.svh"
`include "harness.svh"


module tb_lpddr5_controller ();


/////////////////////////////////
// CLK
/////////////////////////////////

    logic sys_clk   = 1'b1;
    always #5 sys_clk = ~sys_clk; // 100Mhz

    initial begin
        $timeformat(-9, 1, " ns", 10);
    end

/////////////////////////////////
// Sim
/////////////////////////////////

    lpddr5_if controller_if(sys_clk);
    harness tester;

    initial begin
        wait (tester != null);
        tester.monitor_dfi();
    end

    initial begin
        
        $display("\nStarting Simulation\n");

        tester = new(controller_if);
        tester.set_init();
        
        tester.reset();

        tester.read(25'h0001234);

        repeat(10) @(posedge sys_clk);

        tester.write(25'h0001234,
            256'h0123456789ABCDEF_0123456789ABCDEF_0123456789ABCDEF_0123456789ABCDEF
        );


        $display("----------------------------------------------");
        $display("lb_lpddr5_controller.sv finished");
        $display("----------------------------------------------");

        $finish;

    end


lpddr5_controller dut (

    .sys_clk             (controller_if.sys_clk),
    .sys_rst             (controller_if.sys_rst),

    // Command interface
    .cmd_valid           (controller_if.cmd_valid),
    .cmd_ready           (controller_if.cmd_ready),
    .cmd_first           (controller_if.cmd_first),
    .cmd_last            (controller_if.cmd_last),
    .cmd_payload_we      (controller_if.cmd_payload_we),
    .cmd_payload_addr    (controller_if.cmd_payload_addr),

    // Write-data
    .wdata_valid         (controller_if.wdata_valid),
    .wdata_ready         (controller_if.wdata_ready),
    .wdata_first         (controller_if.wdata_first),
    .wdata_last          (controller_if.wdata_last),
    .wdata_payload_data  (controller_if.wdata_payload_data),
    .wdata_payload_we    (controller_if.wdata_payload_we),

    // Read-data 
    .rdata_valid         (controller_if.rdata_valid),
    .rdata_ready         (controller_if.rdata_ready),
    .rdata_first         (controller_if.rdata_first),
    .rdata_last          (controller_if.rdata_last),
    .rdata_payload_data  (controller_if.rdata_payload_data),

    // DFI command 
    .dfi_p0_address      (controller_if.dfi_p0_address),
    .dfi_p0_bank         (controller_if.dfi_p0_bank),
    .dfi_p0_cas_n        (controller_if.dfi_p0_cas_n),
    .dfi_p0_cs_n         (controller_if.dfi_p0_cs_n),
    .dfi_p0_ras_n        (controller_if.dfi_p0_ras_n),
    .dfi_p0_we_n         (controller_if.dfi_p0_we_n),

    .dfi_p0_cke          (controller_if.dfi_p0_cke),
    .dfi_p0_odt          (controller_if.dfi_p0_odt),
    .dfi_p0_reset_n      (controller_if.dfi_p0_reset_n),
    .dfi_p0_act_n        (controller_if.dfi_p0_act_n),

    // DFI write data
    .dfi_p0_wrdata       (controller_if.dfi_p0_wrdata),
    .dfi_p0_wrdata_en    (controller_if.dfi_p0_wrdata_en),
    .dfi_p0_wrdata_mask  (controller_if.dfi_p0_wrdata_mask),

    // DFI read data
    .dfi_p0_rddata_en    (controller_if.dfi_p0_rddata_en),
    .dfi_p0_rddata       (controller_if.dfi_p0_rddata),
    .dfi_p0_rddata_valid (controller_if.dfi_p0_rddata_valid)

);

endmodule





