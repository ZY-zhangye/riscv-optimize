`define DEBUG_EN
`define USE_RTL_DIVIDER_MODEL

module tb_cpu_top_simple #(
    parameter string MEM_FILE = "test/program.hex",
    parameter int TIMEOUT_CYCLES = 50000
);
    logic clk;
    logic rst_n;
    string mem_file_runtime;
    logic [31:0] imem_rdata;
    logic [31:0] imem_addr;
    logic imem_en;
    logic [31:0] dmem_rdata;
    logic [31:0] dmem_addr;
    logic [3:0] dmem_wen;
    logic dmem_en;
    logic [31:0] dmem_wdata;
    logic plic_irq;

    cpu_top cpu_top_inst (
        .clk(clk),
        .rst_n(rst_n),
        .imem_rdata(imem_rdata),
        .imem_addr(imem_addr),
        .imem_en(imem_en),
        .dmem_rdata(dmem_rdata),
        .dmem_addr(dmem_addr),
        .dmem_wen(dmem_wen),
        .dmem_en(dmem_en),
        .dmem_wdata(dmem_wdata),
        .plic_irq(plic_irq)
    );

    initial begin
        clk = 1;
        forever #5 clk = ~clk;
    end

    // VCD waveform dump for P5a verification
    initial begin
        $dumpfile("tb_cpu_top_simple.vcd");
        $dumpvars(0, tb_cpu_top_simple);
    end

    initial begin
        rst_n = 0;
        plic_irq = 1'b0;
        #20 rst_n = 1;
    end

    // Behavioral memories
    logic [31:0] imem [0:4095];
    logic [31:0] dmem [0:4095];

    initial begin
        mem_file_runtime = MEM_FILE;
        if (!$value$plusargs("MEM_FILE=%s", mem_file_runtime))
            $display("No +MEM_FILE plusarg, using default: %s", mem_file_runtime);
        $display("Loading memory from: %s", mem_file_runtime);
        $readmemh(mem_file_runtime, imem);
        $readmemh(mem_file_runtime, dmem);
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            imem_rdata <= 32'b0;
        end else if (imem_en) begin
            imem_rdata <= imem[imem_addr[13:2]];
        end
    end

    wire [31:0] dmem_rd;
    assign dmem_rd = dmem_en ? dmem[dmem_addr[13:2]] : 32'd0;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            dmem_rdata <= 32'b0;
        end else if (dmem_en && dmem_wen == 4'b0000) begin
            dmem_rdata <= dmem_rd;
        end else if (dmem_en && dmem_wen != 4'b0000) begin
            if (dmem_wen[0]) dmem[dmem_addr[13:2]][7:0]   <= dmem_wdata[7:0];
            if (dmem_wen[1]) dmem[dmem_addr[13:2]][15:8]  <= dmem_wdata[15:8];
            if (dmem_wen[2]) dmem[dmem_addr[13:2]][23:16] <= dmem_wdata[23:16];
            if (dmem_wen[3]) dmem[dmem_addr[13:2]][31:24] <= dmem_wdata[31:24];
        end
    end

    // Monitor and check
    wire [31:0] wb_pc = cpu_top_inst.u_wb_stage.wb_pc;
    wire [31:0] wb_result = cpu_top_inst.u_wb_stage.wb_result;
    wire [4:0]  wb_addr = cpu_top_inst.u_wb_stage.wb_dst_addr;
    wire        wb_wen = cpu_top_inst.u_wb_stage.wb_regfile_wen;
    wire        wb_valid = cpu_top_inst.u_wb_stage.ws_valid;
    wire [31:0] x3_value = cpu_top_inst.u_regfiles.regfile[3];

    always_ff @(posedge clk) begin
        if (rst_n && wb_valid && wb_wen) begin
            $display("WB pc=%08h rd=x%0d data=%08h x3=%08h",
                     wb_pc, wb_addr, wb_result, x3_value);
        end
    end

    // ---- P5a: Redirect / lane1 branch signal monitor ----
    `ifdef DUAL_ISSUE_COMMIT_ENABLE
    wire lane1_br_redirect = cpu_top_inst.lane1_br_redirect;
    wire [31:0] lane1_br_target = cpu_top_inst.lane1_br_redirect_target;
    wire br_redirect = cpu_top_inst.br_redirect;
    wire [31:0] br_target = cpu_top_inst.br_redirect_target;
    wire final_redirect = cpu_top_inst.final_redirect;
    wire [31:0] final_target = cpu_top_inst.final_redirect_target;
    wire es_flush = cpu_top_inst.es_flush;
    wire es1_valid = cpu_top_inst.u_exe_lane_simple.es1_valid;
    wire es1_flush = cpu_top_inst.u_exe_lane_simple.es1_flush;
    wire lane1_can_pair = cpu_top_inst.lane1_can_pair;
    wire issue1_valid = cpu_top_inst.u_id_stage.u_issue_select.issue1_valid;
    // ms1_to_ws_bus = {pc[31:0], result[31:0], rd[4:0], wen}
    // result is bits [MS_WS_WIDTH-33 : MS_WS_WIDTH-64] = bits [37:6]
    wire [31:0] exe1_result = cpu_top_inst.u_exe_lane_simple.ms1_to_ws_bus[`MS_WS_WIDTH-33:`MS_WS_WIDTH-64];
    wire [31:0] lane1_inst = cpu_top_inst.lane1_inst;
    wire [1:0] pop_count = cpu_top_inst.id_pop_count;

    // Debug: check dual-issue signals every cycle
    wire dbg_l0v = cpu_top_inst.u_id_stage.u_issue_select.lane0_valid;
    wire dbg_l1v = cpu_top_inst.u_id_stage.u_issue_select.lane1_valid;
    wire dbg_l1sa = cpu_top_inst.u_id_stage.u_issue_select.lane1_simple_alu;
    wire dbg_l0nc = cpu_top_inst.u_id_stage.u_issue_select.lane0_not_ctrl;
    wire dbg_nraw = cpu_top_inst.u_id_stage.u_issue_select.no_raw_hazard;
    wire dbg_nwaw = cpu_top_inst.u_id_stage.u_issue_select.no_waw_hazard;
    wire dbg_sw = cpu_top_inst.u_id_stage.u_issue_select.single_writer;
    logic [5:0] dbg_cycle;
    always_ff @(posedge clk) begin
        if (rst_n) dbg_cycle <= dbg_cycle + 1;
        else dbg_cycle <= 0;
        if (rst_n && dbg_cycle < 20 && (dbg_l0v || dbg_l1v)) begin
            $display("[P5a-DBG] T=%0t cyc=%0d | l0v=%b l1v=%b l1sa=%b l0nc=%b nraw=%b nwaw=%b sw=%b pair=%b pop=%0d l1i=%08h",
                     $time, dbg_cycle, dbg_l0v, dbg_l1v, dbg_l1sa, dbg_l0nc,
                     dbg_nraw, dbg_nwaw, dbg_sw, lane1_can_pair, pop_count, lane1_inst);
        end
    end

    always_ff @(posedge clk) begin
        if (rst_n && (br_redirect || lane1_br_redirect || issue1_valid || es1_flush)) begin
            if (issue1_valid)
                $display("[P5a] T=%0t | DUAL-ISSUE lane1=%08h", $time, lane1_inst);
            if (br_redirect)
                $display("[P5a] T=%0t | lane0 REDIRECT target=%08h", $time, br_target);
            if (lane1_br_redirect)
                $display("[P5a] T=%0t | lane1 REDIRECT target=%08h", $time, lane1_br_target);
            if (final_redirect && (br_redirect || lane1_br_redirect))
                $display("[P5a] T=%0t | FINAL  REDIRECT target=%08h (lane0=%b lane1=%b)",
                         $time, final_target, br_redirect, lane1_br_redirect);
            if (es1_flush)
                $display("[P5a] T=%0t | lane1 FLUSH (lane0_es_flush=%b)", $time,
                         cpu_top_inst.u_exe_lane_simple.lane0_es_flush);
        end
        if (rst_n && es1_valid && cpu_top_inst.u_exe_lane_simple.ms1_to_ws_valid) begin
            $display("[P5a] T=%0t | lane1 WB data=%08h rd=x%0d wen=%b",
                     $time, exe1_result,
                     cpu_top_inst.u_exe_lane_simple.exe1_rd_addr_reg,
                     cpu_top_inst.u_exe_lane_simple.exe1_regfile_wen_reg);
        end
    end
    `endif

    always_ff @(posedge clk) begin
        if (rst_n && wb_valid && (wb_pc == 32'h8000_0044)) begin
            $display("---------------------------------------------");
            $display("Time: %0t", $time);
            if (x3_value == 32'h0000_0001) begin
                $display("Test passed.");
            end else begin
                $display("Test failed. Expected x3=00000001, got %08h", x3_value);
            end
            $display("---------------------------------------------");
            $finish;
        end
    end

    integer cycle_count;
    initial begin
        cycle_count = 0;
        wait (rst_n === 1'b1);
        forever begin
            @(posedge clk);
            cycle_count++;
            if (cycle_count >= TIMEOUT_CYCLES) begin
                $display("Simulation timeout after %0d cycles. x3=%08h", cycle_count, x3_value);
                $finish;
            end
        end
    end

endmodule
