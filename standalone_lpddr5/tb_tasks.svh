
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

task automatic monitor_dfi();

    typedef enum logic[2:0] {
        NOP   = 3'b000,
        ACT   = 3'b010,
        READ  = 3'b100,
        WRITE = 3'b101
    } DFI_CMD;

    logic [2:0] dfi_cmd;

    forever begin
        @(negedge sys_clk);

        if (!sys_rst && !dfi_p0_cs_n) begin

            dfi_cmd = {
                ~dfi_p0_cas_n,
                ~dfi_p0_ras_n,
                ~dfi_p0_we_n
            };

            case (dfi_cmd)

                NOP: ;

                ACT: $display(
                    "[%0t] DFI ACT: bank=%0d row=0x%h",
                    $time, dfi_p0_bank, dfi_p0_address
                );

                READ: $display(
                    "[%0t] DFI READ: bank=%0d col=0x%h",
                    $time, dfi_p0_bank, dfi_p0_address
                );

                WRITE: $display(
                    "[%0t] DFI WRITE: bank=%0d col=0x%h",
                    $time, dfi_p0_bank, dfi_p0_address
                );

                default: $display(
                    "[%0t] DFI OTHER: cmd=%03b bank=%0d addr=0x%h",
                    $time, dfi_cmd, dfi_p0_bank, dfi_p0_address
                );

            endcase
        end
    end
endtask

task automatic send_read(input logic [24:0] addr);

    @(negedge sys_clk);

    cmd_valid        = 1'b1;
    cmd_payload_we   = 1'b0;
    cmd_payload_addr = addr;
    cmd_first        = 1'b1;
    cmd_last         = 1'b1;

    // Wait until controller accepts the command
    do begin
        @(posedge sys_clk);
    end while (!cmd_ready);

    // Deassert after the accepting clock edge
    @(negedge sys_clk);
    cmd_valid = 1'b0;
    cmd_first = 1'b0;
    cmd_last  = 1'b0;

    $display("[%0t] READ accepted: addr=0x%h", $time, addr);
endtask

task automatic wait_for_read();

    forever begin
        @(posedge sys_clk);

        if (!dfi_p0_cs_n &&
            !dfi_p0_cas_n &&
             dfi_p0_ras_n &&
             dfi_p0_we_n) begin

            $display("[%0t] READ command issued on DFI", $time);
            return;
        end
    end
endtask

task automatic send_write(
    input logic [24:0]  addr,
    input logic [255:0] data
);

    fork
        // Command channel
        begin
            @(negedge sys_clk);

            cmd_valid        = 1'b1;
            cmd_payload_we   = 1'b1; // WRITE
            cmd_payload_addr = addr;
            cmd_first        = 1'b1;
            cmd_last         = 1'b1;

            do begin
                @(posedge sys_clk);
            end while (!cmd_ready);

            @(negedge sys_clk);

            cmd_valid = 1'b0;
            cmd_first = 1'b0;
            cmd_last  = 1'b0;

            $display("[%0t] WRITE command accepted: addr=0x%h",
                     $time, addr);
        end

        // Write-data channel
        begin
            @(negedge sys_clk);

            wdata_valid        = 1'b1;
            wdata_payload_data = data;
            wdata_payload_we   = '1; // Enable all 32 bytes
            wdata_first        = 1'b1;
            wdata_last         = 1'b1;

            do begin
                @(posedge sys_clk);
            end while (!wdata_ready);

            @(negedge sys_clk);

            wdata_valid = 1'b0;
            wdata_first = 1'b0;
            wdata_last  = 1'b0;

            $display("[%0t] WRITE data accepted: data=0x%h",
                     $time, data);
        end
    join
endtask

task automatic wait_for_write();

    for (int cycle = 0; cycle < 1000; cycle++) begin

        @(negedge sys_clk);

        if (!dfi_p0_cs_n &&
             dfi_p0_ras_n &&
            !dfi_p0_cas_n &&
            !dfi_p0_we_n) begin

            $display("[%0t] WRITE command issued on DFI", $time);
            return;
        end
    end

    $fatal(1, "Timeout waiting for DFI WRITE command");
endtask