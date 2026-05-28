`timescale 1ns/1ps
`include "my_cpu_defines.svh"

module tb_my_cpu_xsim;
    localparam string MEM_FILE = "xsim_work/program.mem";
    localparam int CLK_PERIOD_NS = 10;
    localparam int TIMEOUT_CYCLES = 200000;
    localparam logic [31:0] PASS_PC = 32'h8000_0044;
    localparam logic [31:0] PASS_VALUE = 32'h0000_0001;

    logic i_sys_clk_p;
    logic i_sys_clk_n;
    logic rst_n;
    logic uart_rx;
    logic uart_tx;
    logic [31:0] led;
    logic plic_irq;
    logic [`PLIC_NUM_INTERRUPTS-1:0] external_interrupts;

    assign external_interrupts = '0;
    assign uart_rx = 1'b1;

    my_cpu #(
        .INST_MEM_FILE(MEM_FILE),
        .DATA_MEM_FILE(MEM_FILE)
    ) u_my_cpu (
        .i_sys_clk_p(i_sys_clk_p),
        .i_sys_clk_n(i_sys_clk_n),
        .rst_n(rst_n),
        .uart_rx(uart_rx),
        .external_interrupts(external_interrupts),
        .uart_tx(uart_tx),
        .led(led),
        .plic_irq(plic_irq)
    );

    wire cpu_clk = u_my_cpu.clk;
    wire soc_rst_n = u_my_cpu.soc_rst_n;
    wire wb_valid = u_my_cpu.u_cpu_top.u_wb_stage.ws_valid;
    wire [31:0] wb_pc = u_my_cpu.u_cpu_top.u_wb_stage.wb_pc;
    wire [4:0] wb_rf_addr = u_my_cpu.u_cpu_top.u_wb_stage.wb_dst_addr;
    wire [31:0] wb_rf_data = u_my_cpu.u_cpu_top.u_wb_stage.wb_result;
    wire wb_rf_wen = u_my_cpu.u_cpu_top.u_wb_stage.wb_regfile_wen;
    wire [31:0] x3_value = u_my_cpu.u_cpu_top.u_regfiles.regfile[3];

    initial begin
        i_sys_clk_p = 1'b0;
        i_sys_clk_n = 1'b1;
        forever #(CLK_PERIOD_NS / 2) begin
            i_sys_clk_p = ~i_sys_clk_p;
            i_sys_clk_n = ~i_sys_clk_n;
        end
    end

    initial begin
        rst_n = 1'b0;
        #100;
        rst_n = 1'b1;
    end

    always_ff @(posedge cpu_clk) begin
        if (soc_rst_n && wb_valid && wb_rf_wen) begin
            $display("WB pc=%08h rd=x%0d data=%08h x3=%08h led=%08h plic_irq=%0b",
                     wb_pc, wb_rf_addr, wb_rf_data, x3_value, led, plic_irq);
        end
    end

    always_ff @(posedge cpu_clk) begin
        if (soc_rst_n && wb_valid && (wb_pc == PASS_PC)) begin
            $display("---------------------------------------------");
            $display("Time: %0t", $time);
            $display("Simulation finished.");
            if (x3_value == PASS_VALUE) begin
                $display("Test passed.");
            end else begin
                $display("Test failed. Expected x3 = %08h, got %08h", PASS_VALUE, x3_value);
            end
            $display("---------------------------------------------");
            $finish;
        end
    end

    initial begin
        int cycle_count;
        cycle_count = 0;
        wait (soc_rst_n === 1'b1);
        forever begin
            @(posedge cpu_clk);
            cycle_count++;
            if (cycle_count >= TIMEOUT_CYCLES) begin
                $display("Simulation timeout after %0d CPU cycles", TIMEOUT_CYCLES);
                $display("last wb_pc=%08h x3=%08h led=%08h plic_irq=%0b", wb_pc, x3_value, led, plic_irq);
                $finish;
            end
        end
    end

endmodule
