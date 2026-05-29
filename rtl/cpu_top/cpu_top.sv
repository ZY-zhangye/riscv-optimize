`include "defines.svh"
module cpu_top (
    input logic clk,
    input logic rst_n,
    //指令存储器接口 (single port — dual port added when DUAL_ISSUE_ENABLE)
    input logic [31:0] imem_rdata,
    output logic [31:0] imem_addr,
    output logic imem_en,
    //数据存储器接口
    input logic [31:0] dmem_rdata,
    output logic [31:0] dmem_addr,
    output logic [3:0] dmem_wen,
    output logic dmem_en,
    output logic [31:0] dmem_wdata,
    //plic接口
    input logic plic_irq
    //debug接口
    `ifdef DEBUG_EN
    ,
    output logic [31:0] debug_wb_pc,
    output logic [4:0] debug_wb_rf_addr,
    output logic [31:0] debug_wb_rf_data,
    output logic debug_wb_rf_wen,
    output logic [31:0] debug_data
    `endif
);

    // ============================================================
    // Signal declarations
    // ============================================================
    logic [`FS_DS_WIDTH-1:0] fs_to_ds_bus;
    logic [`EXC_WIDTH-1:0] fs_exc_bus;
    logic fs_to_ds_valid;
    logic if_ds_allowin;   // backpressure from queue to IF
    logic id_ds_allowin;   // ID → queue pop_ready

    // Queue signals (P2: buffer between IF and ID)
    logic push_valid0;
    logic [31:0] push_inst0, push_pc0;
    logic push_bp_hit0, push_bp_taken0;
    logic [31:0] push_bp_target0;
    logic [`EXC_WIDTH-1:0] push_exc0;
    logic [1:0] push_free;
    logic queue_pop_valid;
    logic [`FS_DS_WIDTH-1:0] queue_pop_bus;
    logic [`EXC_WIDTH-1:0] queue_pop_exc;
    logic queue_flush;

    // Branch / exception
    logic br_redirect;
    logic [31:0] br_redirect_target;
    logic bp_update_valid;
    logic [31:0] bp_update_pc;
    logic bp_update_taken;
    logic [31:0] bp_update_target;
    logic bp_update_is_jalr;
    logic exception_flag;
    logic [31:0] exception_addr;
    logic external_irq_enable;

    // ID stage
    logic [4:0] rs1_addr, rs2_addr;
    logic [31:0] rs1_data, rs2_data;
    logic [11:0] csr_addr;
    logic [31:0] csr_data;
    logic ds_to_es_valid;
    logic es_allowin;
    logic ds_flush;
    logic [`DS_ES_WIDTH-1:0] ds_to_es_bus;
    logic regfile_wen;
    logic [4:0] regfile_waddr;
    logic [31:0] regfile_wdata;
    logic [4:0] exe_dest_addr;
    logic exe_regfile_wen;
    logic [11:0] exe_csr_addr;
    logic exe_csr_wen;
    logic [4:0] mem_dest_addr;
    logic mem_regfile_wen;
    logic [`EXC_WIDTH-1:0] ds_exc_bus;
    logic perf_load_use_stall;

    // EX stage
    logic es_valid;
    logic ms_allowin;
    logic es_to_ms_valid;
    logic [`ES_MS_WIDTH-1:0] es_to_ms_bus;
    logic es_flush;
    logic [31:0] mem_result;
    logic [`EXE_EXC_BUS - 1:0] exe_exc_bus;
    logic br_taken;
    logic [31:0] br_target;
    logic perf_branch_valid, perf_branch_mispredict;
    logic perf_bp_hit, perf_bp_miss, perf_ex_stall;

    // MEM stage
    logic ms_valid;
    logic [`MS_WS_WIDTH-1:0] ms_to_ws_bus;
    logic ms_to_ws_valid;
    logic ws_allowin;
    logic csr_we;
    logic [11:0] csr_waddr;
    logic [31:0] csr_wdata;
    logic [6:0] exception_code;
    logic [31:0] exception_mtval;
    logic perf_retire_valid;

    // ============================================================
    // IF stage (original, unchanged)
    // ============================================================
    if_stage u_if_stage (
        .clk(clk),
        .rst_n(rst_n),
        .pc_out(imem_addr),
        .inst_ren(imem_en),
        .inst_in(imem_rdata),
        .ds_allowin(if_ds_allowin),
        .fs_to_ds_valid(fs_to_ds_valid),
        .fs_to_ds_bus(fs_to_ds_bus),
        .br_taken(br_redirect),
        .br_target(br_redirect_target),
        .bp_update_valid(bp_update_valid),
        .bp_update_pc(bp_update_pc),
        .bp_update_taken(bp_update_taken),
        .bp_update_target(bp_update_target),
        .bp_update_is_jalr(bp_update_is_jalr),
        .fs_exc_bus(fs_exc_bus),
        .exception_flag(exception_flag),
        .exception_addr(exception_addr)
    );

    // ---- Extract fields from fs_to_ds_bus for queue push ----
    assign push_pc0    = fs_to_ds_bus[`FS_DS_WIDTH-32-1:`FS_DS_WIDTH-64];
    assign push_inst0  = fs_to_ds_bus[`FS_DS_WIDTH-1:`FS_DS_WIDTH-32];
    assign push_bp_hit0    = fs_to_ds_bus[`BP_PACKET_WIDTH-1];
    assign push_bp_taken0  = fs_to_ds_bus[`BP_PACKET_WIDTH-2];
    assign push_bp_target0 = fs_to_ds_bus[31:0];
    assign push_valid0     = fs_to_ds_valid;
    assign push_exc0       = fs_exc_bus;

    // ============================================================
    // IF → ID connection: direct (single-issue) or via queue (dual-issue)
    // ============================================================
    assign queue_flush = br_redirect || exception_flag;

    `ifdef DUAL_ISSUE_ENABLE
    // ==== Dual-issue: IF → queue → ID ====
    instr_queue #(.DEPTH(4)) u_instr_queue (
        .clk(clk),
        .rst_n(rst_n),
        .push_valid0(push_valid0),
        .push_valid1(1'b0),
        .push_inst0(push_inst0),
        .push_inst1(32'b0),
        .push_pc0(push_pc0),
        .push_pc1(32'b0),
        .push_bp_hit0(push_bp_hit0),
        .push_bp_hit1(1'b0),
        .push_bp_taken0(push_bp_taken0),
        .push_bp_taken1(1'b0),
        .push_bp_target0(push_bp_target0),
        .push_bp_target1(32'b0),
        .push_exc0(push_exc0),
        .push_exc1('0),
        .push_free(push_free),
        .pop_ready(id_ds_allowin),
        .pop_valid(queue_pop_valid),
        .pop_bus(queue_pop_bus),
        .pop_exc(queue_pop_exc),
        .flush(queue_flush)
    );
    assign if_ds_allowin = (push_free >= 2'd1);

    // ID receives from queue
    id_stage u_id_stage (
        .clk(clk),
        .rst_n(rst_n),
        .fs_to_ds_valid(queue_pop_valid),
        .fs_to_ds_bus(queue_pop_bus),
        .ds_allowin(id_ds_allowin),
        .fs_exc_bus(queue_pop_exc),

    `else
    // ==== Single-issue: original direct IF→ID (queue not in path) ====
    assign if_ds_allowin = id_ds_allowin;

    // ID receives directly from IF
    id_stage u_id_stage (
        .clk(clk),
        .rst_n(rst_n),
        .fs_to_ds_valid(fs_to_ds_valid),
        .fs_to_ds_bus(fs_to_ds_bus),
        .ds_allowin(id_ds_allowin),
        .fs_exc_bus(fs_exc_bus),
    `endif
        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data),
        .csr_addr(csr_addr),
        .csr_data(csr_data),
        .ds_to_es_valid(ds_to_es_valid),
        .es_allowin(es_allowin),
        .ds_flush(ds_flush),
        .ds_to_es_bus(ds_to_es_bus),
        .regfile_wen(regfile_wen),
        .regfile_waddr(regfile_waddr),
        .regfile_wdata(regfile_wdata),
        .exe_dest_addr(exe_dest_addr),
        .exe_regfile_wen(exe_regfile_wen),
        .exe_csr_addr(exe_csr_addr),
        .exe_csr_wen(exe_csr_wen),
        .es_valid(es_valid),
        .mem_dest_addr(mem_dest_addr),
        .mem_regfile_wen(mem_regfile_wen),
        .ms_valid(ms_valid),
        .br_taken(br_redirect),
        .exception_flag(exception_flag),
        .ds_exc_bus(ds_exc_bus),
        .perf_load_use_stall(perf_load_use_stall)
    );

    // ============================================================
    // EX stage
    // ============================================================
    exe_stage u_exe_stage (
        .clk(clk),
        .rst_n(rst_n),
        .ds_to_es_valid(ds_to_es_valid),
        .ms_allowin(ms_allowin),
        .ds_to_es_bus(ds_to_es_bus),
        .ds_flush(ds_flush),
        .es_allowin(es_allowin),
        .es_to_ms_valid(es_to_ms_valid),
        .es_flush(es_flush),
        .es_to_ms_bus(es_to_ms_bus),
        .dmem_addr(dmem_addr),
        .dmem_wen(dmem_wen),
        .dmem_en(dmem_en),
        .dmem_wdata(dmem_wdata),
        .exe_dest_addr(exe_dest_addr),
        .exe_regfile_wen(exe_regfile_wen),
        .exe_csr_addr(exe_csr_addr),
        .exe_csr_wen(exe_csr_wen),
        .es_valid(es_valid),
        .ds_exc_bus(ds_exc_bus),
        .exception_flag(exception_flag),
        .br_taken(br_taken),
        .br_target(br_target),
        .br_redirect(br_redirect),
        .br_redirect_target(br_redirect_target),
        .bp_update_valid(bp_update_valid),
        .bp_update_pc(bp_update_pc),
        .bp_update_taken(bp_update_taken),
        .bp_update_target(bp_update_target),
        .bp_update_is_jalr(bp_update_is_jalr),
        .perf_branch_valid(perf_branch_valid),
        .perf_branch_mispredict(perf_branch_mispredict),
        .perf_bp_hit(perf_bp_hit),
        .perf_bp_miss(perf_bp_miss),
        .perf_ex_stall(perf_ex_stall),
        .mem_result(mem_result),
        .exe_exc_bus(exe_exc_bus)
    );

    // ============================================================
    // MEM stage
    // ============================================================
    mem_stage u_mem_stage (
        .clk(clk),
        .rst_n(rst_n),
        .es_flush(es_flush),
        .es_to_ms_bus(es_to_ms_bus),
        .ms_to_ws_bus(ms_to_ws_bus),
        .es_to_ms_valid(es_to_ms_valid),
        .ms_to_ws_valid(ms_to_ws_valid),
        .ms_allowin(ms_allowin),
        .ws_allowin(ws_allowin),
        .dmem_rdata(dmem_rdata),
        .mem_dst_addr(mem_dest_addr),
        .mem_regfile_wen(mem_regfile_wen),
        .mem_result(mem_result),
        .ms_valid(ms_valid),
        .exception_flag(exception_flag),
        .exe_exc_bus(exe_exc_bus),
        .plic_irq(plic_irq),
        .external_irq_enable(external_irq_enable),
        .csr_we(csr_we),
        .csr_waddr(csr_waddr),
        .csr_wdata(csr_wdata),
        .exception_code(exception_code),
        .exception_mtval(exception_mtval),
        .perf_retire_valid(perf_retire_valid)
    );

    // ============================================================
    // WB stage
    // ============================================================
    wb_stage u_wb_stage (
        .clk(clk),
        .rst_n(rst_n),
        .ms_to_ws_bus(ms_to_ws_bus),
        .ms_to_ws_valid(ms_to_ws_valid),
        .ws_allowin(ws_allowin),
        .regfile_wen(regfile_wen),
        .regfile_addr(regfile_waddr),
        .regfile_wdata(regfile_wdata)
        `ifdef DEBUG_EN
        ,
        .debug_wb_pc(debug_wb_pc),
        .debug_wb_rf_addr(debug_wb_rf_addr),
        .debug_wb_rf_data(debug_wb_rf_data),
        .debug_wb_rf_wen(debug_wb_rf_wen)
        `endif
    );

    // ============================================================
    // Regfiles + CSR
    // ============================================================
    regfiles u_regfiles (
        .clk(clk),
        .rst_n(rst_n),
        .regfile_wen(regfile_wen),
        .regfile_waddr(regfile_waddr),
        .regfile_wdata(regfile_wdata),
        .regfile_raddr1(rs1_addr),
        .regfile_rdata1(rs1_data),
        .regfile_raddr2(rs2_addr),
        .regfile_rdata2(rs2_data)
        `ifdef DEBUG_EN
        ,
        .debug_data(debug_data)
        `endif
    );

    regfile_csr u_regfile_csr (
        .clk(clk),
        .rst_n(rst_n),
        .csr_wen(csr_we),
        .csr_waddr(csr_waddr),
        .csr_wdata(csr_wdata),
        .csr_raddr(csr_addr),
        .csr_rdata(csr_data),
        .exception_code(exception_code),
        .exception_mtval(exception_mtval),
        .perf_retire_valid(perf_retire_valid),
        .perf_branch_valid(perf_branch_valid),
        .perf_branch_mispredict(perf_branch_mispredict),
        .perf_bp_hit(perf_bp_hit),
        .perf_bp_miss(perf_bp_miss),
        .perf_load_use_stall(perf_load_use_stall),
        .perf_ex_stall(perf_ex_stall),
        .exception_flag(exception_flag),
        .exception_addr(exception_addr),
        .external_irq_enable(external_irq_enable)
    );

endmodule
