
task automatic set_init();
    cmd_valid        = 1'b0;
    cmd_first        = 1'b0;
    cmd_last         = 1'b0;
    cmd_payload_we   = 1'b0;
    cmd_payload_addr = '0;

    wdata_valid        = 1'b0;
    wdata_first        = 1'b0;
    wdata_last         = 1'b0;
    wdata_payload_data = '0;
    wdata_payload_we   = '0;

    rdata_ready = 1'b1;
    rdata_first = 1'b0;
    rdata_last  = 1'b0;

    dfi_p0_act_n       = 1'b1;
    dfi_p0_rddata      = '0;
    dfi_p0_rddata_valid = 1'b0;

endtask