`include "defines.svh"
module id_stage (
    input logic clk,
    input logic rst_n,
    //与if_stage的数据接口
    input logic fs_to_ds_valid,
    output logic ds_allowin,
    input logic [`FS_DS_WIDTH-1:0] fs_to_ds_bus,
    //reggiles接口
    output logic [4:0] rs1_addr,
    output logic [4:0] rs2_addr,
    input logic [`DATA_WIDTH-1:0] rs1_data,
    input logic [`DATA_WIDTH-1:0] rs2_data,
    //csr接口
    output logic [11:0] csr_addr,
    input logic [`DATA_WIDTH-1:0] csr_data,
    //与执行阶段的数据接口
    output logic ds_to_es_valid,
    input logic es_allowin,
    output logic ds_flush,
    output logic [`DS_ES_WIDTH-1:0] ds_to_es_bus,
    //数据前递接口--写回
    input logic regfile_wen,
    input logic [4:0] regfile_waddr,
    input logic [`DATA_WIDTH-1:0] regfile_wdata,
    //数据前递接口--执行阶段--仅前递地址，数据选择统一在exe_stage完成
    input logic [4:0] exe_dest_addr,
    input logic exe_regfile_wen,
    input logic [11:0] exe_csr_addr,
    input logic exe_csr_wen,
    input logic es_valid,
    //数据前递接口--访存阶段--仅前递地址，数据选择统一在exe_stage完成
    input logic [4:0] mem_dest_addr,
    input logic mem_regfile_wen,
    input logic ms_valid,
    //跳转信号与异常信号
    input logic br_taken,
    input logic exception_flag,
    input logic [`EXC_WIDTH-1:0] fs_exc_bus,
    output logic [`EXC_WIDTH-1:0] ds_exc_bus,
    output logic perf_load_use_stall

    `ifdef DUAL_ISSUE_ENABLE
    // Queue pop control
    ,
    output logic [1:0] pop_count,
    // Lane1: second instruction from queue
    input  logic pop_valid1,
    input  logic [`FS_DS_WIDTH-1:0] pop_bus1,
    input  logic [`EXC_WIDTH-1:0] pop_exc1,
    // Lane1: extra regfile read ports
    output logic [4:0] rs1_addr1,
    output logic [4:0] rs2_addr1,
    input  logic [31:0] rs1_data1,
    input  logic [31:0] rs2_data1,
    // Lane1 shadow debug
    output logic lane1_can_pair,
    output logic [31:0] lane1_pc,
    output logic [31:0] lane1_inst
    `endif

    `ifdef DUAL_ISSUE_COMMIT_ENABLE
    // Lane1 execution pipeline (P4+)
    ,
    output logic ds_to_es_valid1,
    output logic [`DS_ES_WIDTH-1:0] ds_to_es_bus1,
    output logic ds_flush1,
    output logic [`EXC_WIDTH-1:0] ds_exc_bus1,
    // Lane1 EX1 forwarding (from exe_lane_simple, for hazard detection)
    input  logic [4:0] exe1_dest_addr,
    input  logic exe1_regfile_wen,
    input  logic es1_valid
    `endif
);

    // ============================================================
    // Pipeline control (unchanged)
    // ============================================================
    logic ds_valid;
    logic ds_ready_go;
    logic load_use_hazard;
    assign ds_ready_go = !load_use_hazard;
    assign ds_allowin = !ds_valid || (ds_ready_go && es_allowin);
    assign ds_to_es_valid = ds_valid && ds_ready_go;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            ds_valid <= 1'b0;
        end else if (ds_allowin) begin
            ds_valid <= fs_to_ds_valid;
        end
    end

    // ============================================================
    // Data latching
    // ============================================================
    logic [`FS_DS_WIDTH-1:0] fs_to_ds_bus_r;
    logic [`EXC_WIDTH-1:0] fs_exc_bus_r;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            fs_to_ds_bus_r <= '0;
            fs_exc_bus_r <= '0;
        end else if (fs_to_ds_valid && ds_allowin) begin
            fs_to_ds_bus_r <= fs_to_ds_bus;
            fs_exc_bus_r <= fs_exc_bus;
        end
    end

    // ============================================================
    // Flush logic
    // Latch flush when instruction enters ID so it follows the instruction
    // to EX even if the external flush signal drops (critical with queue).
    // ============================================================
    logic ds_flush_latched;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ds_flush_latched <= 1'b0;
        end else if (fs_to_ds_valid && ds_allowin) begin
            // New instruction entering ID: capture current flush state
            ds_flush_latched <= exception_flag || br_taken;
        end else if (ds_valid && (exception_flag || br_taken)) begin
            // Instruction stalled in ID when flush arrives: hold it
            ds_flush_latched <= 1'b1;
        end else if (!ds_valid) begin
            ds_flush_latched <= 1'b0;
        end
    end

    logic ds_flush_comb;
    assign ds_flush_comb = exception_flag || br_taken;
    assign ds_flush = ds_flush_comb || ds_flush_latched;

    // ---- Unpack fs_to_ds_bus ----
    logic [`ADDR_WIDTH-1:0] id_pc;
    logic [`DATA_WIDTH-1:0] id_inst;
    logic bp_pred_hit;
    logic bp_pred_taken;
    logic [`ADDR_WIDTH-1:0] bp_pred_target;
    assign {id_inst, id_pc, bp_pred_hit, bp_pred_taken, bp_pred_target} = fs_to_ds_bus_r;

    // ============================================================
    // Decode unit — pure combinational instruction decode
    // ============================================================
    logic [4:0]  rd_addr;
    logic [11:0] csr_addr_int;
    logic [31:0] imm_i_ext, imm_s_ext, imm_b_ext, imm_u_ext, imm_j_ext, imm_z_ext;
    logic IMI_valid, IMS_valid, IMB_valid, IMU_valid, IMJ_valid, IMZ_valid;
    logic [`ALU_PACKET_WIDTH-1:0]   alu_packet;
    logic [`MUL_PACKET_WIDTH-1:0]   mul_packet;
    logic [`MEM_PACKET_WIDTH-1:0]   mem_packet;
    logic [`CSR_PACKET_WIDTH-1:0]   csr_packet;
    logic [`BR_JMP_PACKET_WIDTH-1:0] br_jmp_packet;
    logic [`CTRL_PACKET_WIDTH-1:0]  ctrl_packet;
    logic need_rs1, need_rs2;
    logic is_load;
    logic alu_src2_imm_sel;
    logic inst_lui, inst_auipc;
    logic inst_bitman_imm_inst, inst_bitman_any, inst_bitman_rs2_inst;
    logic inst_ecall, inst_ebreak, inst_mret;

    `ifdef Z_BITMAIN_ENABLE
    logic [`BITMAN_PACKET_WIDTH-1:0] bitman_packet;
    `endif

    decode_unit u_decode (
        .inst(id_inst),
        .pc(id_pc),
        .bp_pred_hit(bp_pred_hit),
        .bp_pred_taken(bp_pred_taken),
        .bp_pred_target(bp_pred_target),
        .csr_rdata(csr_data),
        .exe_csr_addr(exe_csr_addr),
        .exe_csr_wen(exe_csr_wen),
        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .rd_addr(rd_addr),
        .csr_addr(csr_addr_int),
        .imm_i_ext(imm_i_ext),
        .imm_s_ext(imm_s_ext),
        .imm_b_ext(imm_b_ext),
        .imm_u_ext(imm_u_ext),
        .imm_j_ext(imm_j_ext),
        .imm_z_ext(imm_z_ext),
        .IMI_valid(IMI_valid),
        .IMS_valid(IMS_valid),
        .IMB_valid(IMB_valid),
        .IMU_valid(IMU_valid),
        .IMJ_valid(IMJ_valid),
        .IMZ_valid(IMZ_valid),
        .alu_packet(alu_packet),
        .mul_packet(mul_packet),
        .mem_packet(mem_packet),
        .csr_packet(csr_packet),
        .br_jmp_packet(br_jmp_packet),
        .ctrl_packet(ctrl_packet),
        `ifdef Z_BITMAIN_ENABLE
        .bitman_packet(bitman_packet),
        `endif
        .need_rs1(need_rs1),
        .need_rs2(need_rs2),
        .is_load(is_load),
        .alu_src2_imm_sel(alu_src2_imm_sel),
        .inst_lui(inst_lui),
        .inst_auipc(inst_auipc),
        .inst_bitman_imm_inst(inst_bitman_imm_inst),
        .inst_bitman_any(inst_bitman_any),
        .inst_bitman_rs2_inst(inst_bitman_rs2_inst),
        .inst_ecall(inst_ecall),
        .inst_ebreak(inst_ebreak),
        .inst_mret(inst_mret)
    );

    assign csr_addr = csr_addr_int;

    // ============================================================
    // WB forwarding for src1/src2 (0-cycle combinational read path)
    // Must stay in id_stage — depends on rs1_data/rs2_data from regfile
    // ============================================================
    logic [31:0] src1, src2;
    assign src1 = (rs1_addr == 5'b0) ? 32'b0 :
                  (regfile_wen && (regfile_waddr == rs1_addr)) ? regfile_wdata :
                   rs1_data;
    assign src2 = (rs2_addr == 5'b0) ? 32'b0 :
                  (regfile_wen && (regfile_waddr == rs2_addr)) ? regfile_wdata :
                   rs2_data;

    // ============================================================
    // Hazard unit — forwarding control + load-use detection
    // ============================================================
    logic [1:0] src1_fwd, src2_fwd;

    logic prev_load;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_load <= 1'b0;
        end else if (ds_allowin) begin
            prev_load <= is_load;
        end
    end

    hazard_unit u_hazard (
        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .need_rs1(need_rs1),
        .need_rs2(need_rs2),
        .inst_lui(inst_lui),
        .inst_auipc(inst_auipc),
        .alu_src2_imm_sel(alu_src2_imm_sel),
        .inst_bitman_imm_inst(inst_bitman_imm_inst),
        .inst_bitman_any(inst_bitman_any),
        .inst_bitman_rs2_inst(inst_bitman_rs2_inst),
        .exe_dest_addr(exe_dest_addr),
        .exe_regfile_wen(exe_regfile_wen),
        .es_valid(es_valid),
        .mem_dest_addr(mem_dest_addr),
        .mem_regfile_wen(mem_regfile_wen),
        .ms_valid(ms_valid),
        `ifdef DUAL_ISSUE_COMMIT_ENABLE
        .exe1_dest_addr(exe1_dest_addr),
        .exe1_regfile_wen(exe1_regfile_wen),
        .es1_valid(es1_valid),
        `endif
        .prev_load(prev_load),
        .ds_valid(ds_valid),
        .src1_fwd(src1_fwd),
        .src2_fwd(src2_fwd),
        .load_use_hazard(load_use_hazard)
    );

    assign perf_load_use_stall = load_use_hazard;

    // ============================================================
    // SRC packet — operand preparation (uses WB-forwarded src1/src2)
    // ============================================================
    logic [`SRC_PACKET_WIDTH-1:0] src_packet;
    logic [31:0] reg_src1, reg_src2;

    assign reg_src1 = inst_lui   ? 32'b0 :
                      inst_auipc ? id_pc : src1;
    assign reg_src2 = inst_bitman_imm_inst ? {27'b0, id_inst[24:20]} :
                      alu_src2_imm_sel ? ({32{IMI_valid}} & imm_i_ext) |
                                          ({32{IMU_valid}} & imm_u_ext) : src2;
    assign src_packet = {reg_src1, reg_src2, src1_fwd, src2_fwd};

    // ============================================================
    // Final bus assembly
    // ============================================================
    `ifdef Z_BITMAIN_ENABLE
    assign ds_to_es_bus = {bitman_packet, alu_packet, mul_packet, mem_packet,
                           csr_packet, br_jmp_packet, ctrl_packet, src_packet};
    `else
    assign ds_to_es_bus = {alu_packet, mul_packet, mem_packet,
                           csr_packet, br_jmp_packet, ctrl_packet, src_packet};
    `endif

    // ============================================================
    // Exception encoding
    // ============================================================
    logic [6:0] exc_code;
    logic [31:0] exc_mtval;
    assign exc_code = ds_flush ? 7'b0 :
                      (inst_ecall && ds_allowin)  ? 7'b0101011 :
                      (inst_ebreak && ds_allowin) ? 7'b0100011 :
                      (inst_mret && ds_allowin)   ? 7'b1000000 :
                      fs_exc_bus_r[38:32];
    assign exc_mtval = ds_flush ? 32'b0 :
                       (inst_ecall && ds_allowin)  ? 32'b0 :
                       (inst_ebreak && ds_allowin) ? 32'b0 :
                       (inst_mret && ds_allowin)   ? 32'b0 :
                       fs_exc_bus_r[31:0];
    assign ds_exc_bus = {exc_code, exc_mtval};

    // ============================================================
    // Dual-issue: lane1 shadow decode + issue select
    // In P3 lane1 never goes to EX — decode + hazard observation only.
    // ============================================================
    `ifdef DUAL_ISSUE_ENABLE
    // ---- Lane1 unpack from queue ----
    logic [31:0] id_pc1, id_inst1;
    logic bp_pred_hit1, bp_pred_taken1;
    logic [31:0] bp_pred_target1;
    assign {id_inst1, id_pc1, bp_pred_hit1, bp_pred_taken1, bp_pred_target1} = pop_bus1;

    // ---- Lane1 decode ----
    logic [4:0]  rd_addr1;
    logic [11:0] csr_addr_int1;
    logic [31:0] imm_i_ext1, imm_s_ext1, imm_b_ext1, imm_u_ext1, imm_j_ext1, imm_z_ext1;
    logic IMI_valid1, IMS_valid1, IMB_valid1, IMU_valid1, IMJ_valid1, IMZ_valid1;
    logic [`ALU_PACKET_WIDTH-1:0]   alu_packet1;
    logic [`MUL_PACKET_WIDTH-1:0]   mul_packet1;
    logic [`MEM_PACKET_WIDTH-1:0]   mem_packet1;
    logic [`CSR_PACKET_WIDTH-1:0]   csr_packet1;
    logic [`BR_JMP_PACKET_WIDTH-1:0] br_jmp_packet1;
    logic [`CTRL_PACKET_WIDTH-1:0]  ctrl_packet1;
    logic need_rs11, need_rs21;
    logic is_load1;
    logic alu_src2_imm_sel1;
    logic inst_lui1, inst_auipc1;
    logic inst_bitman_imm_inst1, inst_bitman_any1, inst_bitman_rs2_inst1;
    logic inst_ecall1, inst_ebreak1, inst_mret1;

    `ifdef Z_BITMAIN_ENABLE
    logic [`BITMAN_PACKET_WIDTH-1:0] bitman_packet1;
    `endif

    decode_unit u_decode1 (
        .inst(id_inst1),
        .pc(id_pc1),
        .bp_pred_hit(bp_pred_hit1),
        .bp_pred_taken(bp_pred_taken1),
        .bp_pred_target(bp_pred_target1),
        .csr_rdata(csr_data),
        .exe_csr_addr(exe_csr_addr),
        .exe_csr_wen(exe_csr_wen),
        .rs1_addr(rs1_addr1),
        .rs2_addr(rs2_addr1),
        .rd_addr(rd_addr1),
        .csr_addr(csr_addr_int1),
        .imm_i_ext(imm_i_ext1),
        .imm_s_ext(imm_s_ext1),
        .imm_b_ext(imm_b_ext1),
        .imm_u_ext(imm_u_ext1),
        .imm_j_ext(imm_j_ext1),
        .imm_z_ext(imm_z_ext1),
        .IMI_valid(IMI_valid1),
        .IMS_valid(IMS_valid1),
        .IMB_valid(IMB_valid1),
        .IMU_valid(IMU_valid1),
        .IMJ_valid(IMJ_valid1),
        .IMZ_valid(IMZ_valid1),
        .alu_packet(alu_packet1),
        .mul_packet(mul_packet1),
        .mem_packet(mem_packet1),
        .csr_packet(csr_packet1),
        .br_jmp_packet(br_jmp_packet1),
        .ctrl_packet(ctrl_packet1),
        `ifdef Z_BITMAIN_ENABLE
        .bitman_packet(bitman_packet1),
        `endif
        .need_rs1(need_rs11),
        .need_rs2(need_rs21),
        .is_load(is_load1),
        .alu_src2_imm_sel(alu_src2_imm_sel1),
        .inst_lui(inst_lui1),
        .inst_auipc(inst_auipc1),
        .inst_bitman_imm_inst(inst_bitman_imm_inst1),
        .inst_bitman_any(inst_bitman_any1),
        .inst_bitman_rs2_inst(inst_bitman_rs2_inst1),
        .inst_ecall(inst_ecall1),
        .inst_ebreak(inst_ebreak1),
        .inst_mret(inst_mret1)
    );

    // ---- Lane1 hazard detection ----
    logic [1:0] src1_fwd1, src2_fwd1;
    logic load_use_hazard1;
    hazard_unit u_hazard1 (
        .rs1_addr(rs1_addr1),
        .rs2_addr(rs2_addr1),
        .need_rs1(need_rs11),
        .need_rs2(need_rs21),
        .inst_lui(inst_lui1),
        .inst_auipc(inst_auipc1),
        .alu_src2_imm_sel(alu_src2_imm_sel1),
        .inst_bitman_imm_inst(inst_bitman_imm_inst1),
        .inst_bitman_any(inst_bitman_any1),
        .inst_bitman_rs2_inst(inst_bitman_rs2_inst1),
        .exe_dest_addr(exe_dest_addr),
        .exe_regfile_wen(exe_regfile_wen),
        .es_valid(es_valid),
        .mem_dest_addr(mem_dest_addr),
        .mem_regfile_wen(mem_regfile_wen),
        .ms_valid(ms_valid),
        `ifdef DUAL_ISSUE_COMMIT_ENABLE
        .exe1_dest_addr(exe1_dest_addr),
        .exe1_regfile_wen(exe1_regfile_wen),
        .es1_valid(es1_valid),
        `endif
        .prev_load(is_load),        // lane0's is_load (older instruction)
        .ds_valid(ds_valid),
        .src1_fwd(src1_fwd1),
        .src2_fwd(src2_fwd1),
        .load_use_hazard(load_use_hazard1)
    );

    // ---- Lane1 WB forwarding for src1/src2 ----
    logic [31:0] src11, src21;
    assign src11 = (rs1_addr1 == 5'b0) ? 32'b0 :
                   (regfile_wen && (regfile_waddr == rs1_addr1)) ? regfile_wdata : rs1_data1;
    assign src21 = (rs2_addr1 == 5'b0) ? 32'b0 :
                   (regfile_wen && (regfile_waddr == rs2_addr1)) ? regfile_wdata : rs2_data1;

    // ---- Issue select ----
    logic lane0_is_alu, lane0_is_mul, lane0_is_mem, lane0_is_csr, lane0_is_br_jmp, lane0_is_system;
    logic lane0_regfile_wen_d;
    logic lane1_is_alu, lane1_is_mul, lane1_is_mem, lane1_is_csr, lane1_is_br_jmp, lane1_is_system;
    logic lane1_regfile_wen_d;
    logic ds_issue0_valid, ds_issue1_valid;

    // Extract from lane0 ctrl_packet (bits [11:7] and [1] same position with/without Zb)
    assign lane0_is_alu     = ctrl_packet[11];
    assign lane0_is_mul     = ctrl_packet[10];
    assign lane0_is_mem     = ctrl_packet[9];
    assign lane0_is_csr     = ctrl_packet[8];
    assign lane0_is_br_jmp  = ctrl_packet[7];
    assign lane0_regfile_wen_d = ctrl_packet[1];
    assign lane0_is_system  = inst_ecall || inst_ebreak || inst_mret;

    // Extract from lane1 ctrl_packet
    assign lane1_is_alu     = ctrl_packet1[11];
    assign lane1_is_mul     = ctrl_packet1[10];
    assign lane1_is_mem     = ctrl_packet1[9];
    assign lane1_is_csr     = ctrl_packet1[8];
    assign lane1_is_br_jmp  = ctrl_packet1[7];
    assign lane1_regfile_wen_d = ctrl_packet1[1];
    assign lane1_is_system  = inst_ecall1 || inst_ebreak1 || inst_mret1;

    logic lane1_simple_alu_shadow, lane0_not_ctrl_shadow;
    logic no_raw_shadow, no_waw_shadow;

    issue_select u_issue_select (
        // Lane0
        .lane0_valid(fs_to_ds_valid),
        .lane0_rd_addr(rd_addr),
        .lane0_rs1_addr(rs1_addr),
        .lane0_rs2_addr(rs2_addr),
        .lane0_need_rs1(need_rs1),
        .lane0_need_rs2(need_rs2),
        .lane0_is_alu(lane0_is_alu),
        .lane0_is_mul(lane0_is_mul),
        .lane0_is_mem(lane0_is_mem),
        .lane0_is_csr(lane0_is_csr),
        .lane0_is_br_jmp(lane0_is_br_jmp),
        .lane0_is_system(lane0_is_system),
        .lane0_regfile_wen(lane0_regfile_wen_d),
        // Lane1
        .lane1_valid(pop_valid1),
        .lane1_rd_addr(rd_addr1),
        .lane1_rs1_addr(rs1_addr1),
        .lane1_rs2_addr(rs2_addr1),
        .lane1_need_rs1(need_rs11),
        .lane1_need_rs2(need_rs21),
        .lane1_is_alu(lane1_is_alu),
        .lane1_is_mul(lane1_is_mul),
        .lane1_is_mem(lane1_is_mem),
        .lane1_is_csr(lane1_is_csr),
        .lane1_is_br_jmp(lane1_is_br_jmp),
        .lane1_is_system(lane1_is_system),
        .lane1_regfile_wen(lane1_regfile_wen_d),
        // Pipeline status
        .ds_allowin(ds_allowin),
        // Issue
        .issue0_valid(ds_issue0_valid),
        .issue1_valid(ds_issue1_valid),
        .pop_count(pop_count),
        // Shadow
        .lane1_simple_alu(lane1_simple_alu_shadow),
        .lane0_not_ctrl(lane0_not_ctrl_shadow),
        .no_raw_hazard(no_raw_shadow),
        .no_waw_hazard(no_waw_shadow),
        .lane1_can_pair(lane1_can_pair)
    );

    assign lane1_pc   = id_pc1;
    assign lane1_inst = id_inst1;

    // ============================================================
    // P4+: Lane1 execution path
    // ============================================================
    `ifdef DUAL_ISSUE_COMMIT_ENABLE
    // ---- Lane1 SRC packet (using lane1's own decode + WB forwarding) ----
    logic [`SRC_PACKET_WIDTH-1:0] src_packet1;
    logic [31:0] reg_src1_1, reg_src2_1;
    assign reg_src1_1 = inst_lui1   ? 32'b0 :
                        inst_auipc1 ? id_pc1 : src11;
    assign reg_src2_1 = inst_bitman_imm_inst1 ? {27'b0, id_inst1[24:20]} :
                        alu_src2_imm_sel1 ? ({32{IMI_valid1}} & imm_i_ext1) |
                                            ({32{IMU_valid1}} & imm_u_ext1) : src21;
    assign src_packet1 = {reg_src1_1, reg_src2_1, src1_fwd1, src2_fwd1};

    // ---- Lane1 ds_to_es_bus assembly ----
    `ifdef Z_BITMAIN_ENABLE
    assign ds_to_es_bus1 = {bitman_packet1, alu_packet1, mul_packet1, mem_packet1,
                             csr_packet1, br_jmp_packet1, ctrl_packet1, src_packet1};
    `else
    assign ds_to_es_bus1 = {alu_packet1, mul_packet1, mem_packet1,
                             csr_packet1, br_jmp_packet1, ctrl_packet1, src_packet1};
    `endif

    // ---- Lane1 pipeline handshake ----
    assign ds_to_es_valid1 = ds_issue1_valid;
    assign ds_flush1 = exception_flag || br_taken;
    assign ds_exc_bus1 = pop_exc1;

    // ---- Connect lane1 EX1 forwarding to hazard units ----
    // (lane0 hazard_unit uses exe1 for lane1→lane0 RAW detection)
    // (lane1 hazard_unit uses exe1 for lane1→lane1 RAW detection)
    `endif

    `endif  // DUAL_ISSUE_ENABLE

endmodule
