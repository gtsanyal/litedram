

class harness;

    typedef enum logic[2:0] {
        NOP   = 3'b000,
        ACT   = 3'b010,
        READ  = 3'b100,
        WRITE = 3'b101
    } DFI_CMD;

    local virtual lpddr5_if vif;

    function new(virtual lpddr5_if vif);
        this.vif = vif;
    endfunction

    task automatic monitor_dfi();

        logic [2:0] dfi_cmd;

        forever begin
            @(negedge vif.sys_clk);

            if (!vif.sys_rst && !vif.dfi_p0_cs_n) begin

                dfi_cmd = {
                    ~vif.dfi_p0_cas_n,
                    ~vif.dfi_p0_ras_n,
                    ~vif.dfi_p0_we_n
                };

                case (dfi_cmd)

                    NOP: ;

                    ACT: $display(
                        "[%0t] DFI ACT: bank=%0d row=0x%h",
                        $time, vif.dfi_p0_bank, vif.dfi_p0_address
                    );

                    READ: $display(
                        "[%0t] DFI READ: bank=%0d col=0x%h",
                        $time, vif.dfi_p0_bank, vif.dfi_p0_address
                    );

                    WRITE: $display(
                        "[%0t] DFI WRITE: bank=%0d col=0x%h",
                        $time, vif.dfi_p0_bank, vif.dfi_p0_address
                    );

                    default: $display(
                        "[%0t] DFI OTHER: cmd=%03b bank=%0d addr=0x%h",
                        $time, dfi_cmd, vif.dfi_p0_bank, vif.dfi_p0_address
                    );

                endcase
            end
        end
    endtask

    task automatic set_init();
        vif.sys_rst = 1'b1;

        vif.cmd_valid        = 1'b0;
        vif.cmd_first        = 1'b0;
        vif.cmd_last         = 1'b0;
        vif.cmd_payload_we   = 1'b0;
        vif.cmd_payload_addr = '0;

        vif.wdata_valid        = 1'b0;
        vif.wdata_first        = 1'b0;
        vif.wdata_last         = 1'b0;
        vif.wdata_payload_data = '0;
        vif.wdata_payload_we   = '0;

        vif.rdata_ready = 1'b1;
        vif.rdata_first = 1'b0;
        vif.rdata_last  = 1'b0;

        vif.dfi_p0_act_n       = 1'b1;
        vif.dfi_p0_rddata      = '0;
        vif.dfi_p0_rddata_valid = 1'b0;
    endtask

    task automatic reset(int cycles = 10);
        $display("RESET------------------------------------------------\n");
        vif.sys_rst = 1'b1;
        repeat (cycles) @(posedge vif.sys_clk);
        @(negedge vif.sys_clk);
        vif.sys_rst = 1'b0;
        repeat (5) @(posedge vif.sys_clk);
    endtask


    local task automatic send_read(input logic [24:0] addr);

        @(negedge vif.sys_clk);

        vif.cmd_valid        = 1'b1;
        vif.cmd_payload_we   = 1'b0;
        vif.cmd_payload_addr = addr;
        vif.cmd_first        = 1'b1;
        vif.cmd_last         = 1'b1;

        // Wait until controller accepts the command
        do begin
            @(posedge vif.sys_clk);
        end while (!vif.cmd_ready);

        // Deassert after the accepting clock edge
        @(negedge vif.sys_clk);
        vif.cmd_valid = 1'b0;
        vif.cmd_first = 1'b0;
        vif.cmd_last  = 1'b0;

        $display("[%0t] READ accepted: addr=0x%h", $time, addr);
    endtask

    local task automatic wait_for_read();

        for (int cycle = 0; cycle < 1000; cycle++) begin
            @(negedge vif.sys_clk);

            if (!vif.dfi_p0_cs_n &&
                !vif.dfi_p0_cas_n &&
                vif.dfi_p0_ras_n &&
                vif.dfi_p0_we_n) begin

                $display("[%0t] READ command issued on DFI", $time);
                return;
            end
        end

        $fatal(1, "Timeout waiting for DFI READ command");
    endtask

    task automatic read(input logic [24:0] addr);
        $display("READ BEGIN-------------------------------------------------");
        fork
            send_read(addr);
            wait_for_read();
        join
        $display("READ END---------------------------------------------------\n");
    endtask 

    local task automatic send_write(
        input logic [24:0]  addr,
        input logic [255:0] data
    );

        fork
            // Command channel
            begin
                @(negedge vif.sys_clk);

                vif.cmd_valid        = 1'b1;
                vif.cmd_payload_we   = 1'b1;
                vif.cmd_payload_addr = addr;
                vif.cmd_first        = 1'b1;
                vif.cmd_last         = 1'b1;

                do begin
                    @(posedge vif.sys_clk);
                end while (!vif.cmd_ready);

                @(negedge vif.sys_clk);

                vif.cmd_valid = 1'b0;
                vif.cmd_first = 1'b0;
                vif.cmd_last  = 1'b0;

                $display("[%0t] WRITE command accepted: addr=0x%h",
                        $time, addr);
            end

            // Write-data channel
            begin
                @(negedge vif.sys_clk);

                vif.wdata_valid        = 1'b1;
                vif.wdata_payload_data = data;
                vif.wdata_payload_we   = '1; // Enable all 32 bytes
                vif.wdata_first        = 1'b1;
                vif.wdata_last         = 1'b1;

                do begin
                    @(posedge vif.sys_clk);
                end while (!vif.wdata_ready);

                @(negedge vif.sys_clk);

                vif.wdata_valid = 1'b0;
                vif.wdata_first = 1'b0;
                vif.wdata_last  = 1'b0;

                $display("[%0t] WRITE data accepted: data=0x%h",
                        $time, data);
            end
        join
    endtask

    local task automatic wait_for_write();

        for (int cycle = 0; cycle < 1000; cycle++) begin

            @(negedge vif.sys_clk);

            if (!vif.dfi_p0_cs_n &&
                vif.dfi_p0_ras_n &&
                !vif.dfi_p0_cas_n &&
                !vif.dfi_p0_we_n) begin

                $display("[%0t] WRITE command issued on DFI", $time);
                return;
            end
        end

        $fatal(1, "Timeout waiting for DFI WRITE command");
    endtask

    task automatic write(
        input logic [24:0]  addr,
        input logic [255:0] data
    );
        $display("WRITE BEGIN------------------------------------------------");
        fork
            send_write(addr,data);
            // @ same time bc send_write might write before wait_for_write starts
            // Since send_write also forks
            wait_for_write();
        join
        $display("WRITE END--------------------------------------------------\n");

    endtask

endclass

