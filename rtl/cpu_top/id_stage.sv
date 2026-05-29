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
    // ============================================================
    always_comb begin
        if (!rst_n)
            ds_flush = 1'b0;
        else if (exception_flag || br_taken)
            ds_flush = 1'b1;
        else
            ds_flush = 1'b0;
    end

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

endmodule
