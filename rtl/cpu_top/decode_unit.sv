`include "defines.svh"

// Combinational instruction decoder — extracted from id_stage for dual-issue reuse.
// Produces all control packets, register addresses, immediates, and metadata
// from a single instruction + PC + BP/CSR context.
module decode_unit (
    input logic [31:0] inst,
    input logic [31:0] pc,

    // Branch predictor packet (from IF stage)
    input logic bp_pred_hit,
    input logic bp_pred_taken,
    input logic [31:0] bp_pred_target,

    // CSR read data
    input logic [31:0] csr_rdata,
    // CSR forwarding check
    input logic [11:0] exe_csr_addr,
    input logic exe_csr_wen,

    // ---- Register addresses ----
    output logic [4:0] rs1_addr,
    output logic [4:0] rs2_addr,
    output logic [4:0] rd_addr,
    output logic [11:0] csr_addr,

    // ---- Immediate bundle ----
    output logic [31:0] imm_i_ext,
    output logic [31:0] imm_s_ext,
    output logic [31:0] imm_b_ext,
    output logic [31:0] imm_u_ext,
    output logic [31:0] imm_j_ext,
    output logic [31:0] imm_z_ext,
    output logic IMI_valid,
    output logic IMS_valid,
    output logic IMB_valid,
    output logic IMU_valid,
    output logic IMJ_valid,
    output logic IMZ_valid,

    // ---- Control packets ----
    output logic [`ALU_PACKET_WIDTH-1:0]   alu_packet,
    output logic [`MUL_PACKET_WIDTH-1:0]   mul_packet,
    output logic [`MEM_PACKET_WIDTH-1:0]   mem_packet,
    output logic [`CSR_PACKET_WIDTH-1:0]   csr_packet,
    output logic [`BR_JMP_PACKET_WIDTH-1:0] br_jmp_packet,
    output logic [`CTRL_PACKET_WIDTH-1:0]  ctrl_packet,

    `ifdef Z_BITMAIN_ENABLE
    output logic [`BITMAN_PACKET_WIDTH-1:0] bitman_packet,
    `endif

    // ---- Metadata for hazard / operand prep ----
    output logic need_rs1,
    output logic need_rs2,
    output logic is_load,
    output logic alu_src2_imm_sel,
    output logic inst_lui,
    output logic inst_auipc,
    output logic inst_bitman_imm_inst,
    output logic inst_bitman_any,
    output logic inst_bitman_rs2_inst,

    // ---- Exception decode ----
    output logic inst_ecall,
    output logic inst_ebreak,
    output logic inst_mret
);

    // ============================================================
    // Field extraction
    // ============================================================
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    assign opcode  = inst[6:0];
    assign funct3  = inst[14:12];
    assign funct7  = inst[31:25];
    assign rs1_addr = inst[19:15];
    assign rs2_addr = inst[24:20];
    assign csr_addr = inst[31:20];
    assign rd_addr  = inst[11:7];

    // ============================================================
    // Immediate generation
    // ============================================================
    logic [11:0] imm_i;
    logic [11:0] imm_s;
    logic [12:0] imm_b;
    logic [19:0] imm_u;
    logic [20:0] imm_j;
    logic [4:0]  imm_z;
    assign imm_i = inst[31:20];
    assign imm_s = {inst[31:25], inst[11:7]};
    assign imm_b = {inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
    assign imm_u = inst[31:12];
    assign imm_j = {inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};
    assign imm_z = inst[19:15];

    assign imm_i_ext = {{20{imm_i[11]}}, imm_i};
    assign imm_s_ext = {{20{imm_s[11]}}, imm_s};
    assign imm_b_ext = {{19{imm_b[12]}}, imm_b};
    assign imm_u_ext = {imm_u, 12'b0};
    assign imm_j_ext = {{11{imm_j[20]}}, imm_j};
    assign imm_z_ext = {{27{1'b0}}, imm_z};

    // ============================================================
    // Opcode classification
    // ============================================================
    logic is_load_d, is_store_d, is_branch_d, is_jal_d, is_jalr_d;
    logic is_op_imm, is_op_reg, is_lui_d, is_auipc_d, is_system, is_fence;

    assign is_load_d   = (opcode == 7'b0000011);
    assign is_store_d  = (opcode == 7'b0100011);
    assign is_branch_d = (opcode == 7'b1100011);
    assign is_jal_d    = (opcode == 7'b1101111);
    assign is_jalr_d   = (opcode == 7'b1100111);
    assign is_op_imm   = (opcode == 7'b0010011);
    assign is_op_reg   = (opcode == 7'b0110011);
    assign is_lui_d    = (opcode == 7'b0110111);
    assign is_auipc_d  = (opcode == 7'b0010111);
    assign is_system   = (opcode == 7'b1110011);
    assign is_fence    = (opcode == 7'b0001111);

    assign inst_lui   = is_lui_d;
    assign inst_auipc = is_auipc_d;
    assign is_load    = is_load_d;

    // funct3 one-hot
    logic f3_000, f3_001, f3_010, f3_011, f3_100, f3_101, f3_110, f3_111;
    assign f3_000 = (funct3 == 3'b000);
    assign f3_001 = (funct3 == 3'b001);
    assign f3_010 = (funct3 == 3'b010);
    assign f3_011 = (funct3 == 3'b011);
    assign f3_100 = (funct3 == 3'b100);
    assign f3_101 = (funct3 == 3'b101);
    assign f3_110 = (funct3 == 3'b110);
    assign f3_111 = (funct3 == 3'b111);

    // funct7 one-hot
    logic f7_0000000, f7_0100000, f7_0000001, f7_0011000;
    assign f7_0000000 = (funct7 == 7'b0000000);
    assign f7_0100000 = (funct7 == 7'b0100000);
    assign f7_0000001 = (funct7 == 7'b0000001);
    assign f7_0011000 = (funct7 == 7'b0011000);

    // ============================================================
    // Z-bitman instruction decode
    // ============================================================
    `ifdef Z_BITMAIN_ENABLE
    logic is_bitman, is_bitman_imm;
    assign is_bitman     = (opcode == 7'b0110011);
    assign is_bitman_imm = (opcode == 7'b0010011);

    logic inst_sh1add, inst_sh2add, inst_sh3add;
    logic inst_andn, inst_orn, inst_xnor;
    logic inst_min, inst_max, inst_minu, inst_maxu;
    logic inst_sextb, inst_sexth, inst_zexth;
    logic inst_orcb, inst_rev8, inst_brev8, inst_pack, inst_packh, inst_zip, inst_unzip;
    logic inst_bclr, inst_bclri, inst_bext, inst_bexti, inst_binv, inst_binvi, inst_bset, inst_bseti;

    assign inst_sh1add = is_bitman && f3_010 && (inst[31:25] == 7'b0010000);
    assign inst_sh2add = is_bitman && f3_100 && (inst[31:25] == 7'b0010000);
    assign inst_sh3add = is_bitman && f3_110 && (inst[31:25] == 7'b0010000);
    assign inst_andn = is_bitman && f3_111 && (inst[31:25] == 7'b0100000);
    assign inst_orn  = is_bitman && f3_110 && (inst[31:25] == 7'b0100000);
    assign inst_xnor = is_bitman && f3_100 && (inst[31:25] == 7'b0100000);
    assign inst_max  = is_bitman && f3_110 && (inst[31:25] == 7'b0000101);
    assign inst_maxu = is_bitman && f3_111 && (inst[31:25] == 7'b0000101);
    assign inst_min  = is_bitman && f3_100 && (inst[31:25] == 7'b0000101);
    assign inst_minu = is_bitman && f3_101 && (inst[31:25] == 7'b0000101);
    assign inst_sextb = is_bitman_imm && f3_001 && (inst[31:20] == 12'h604);
    assign inst_sexth = is_bitman_imm && f3_001 && (inst[31:20] == 12'h605);
    assign inst_zexth = is_bitman && f3_100 && (inst[31:25] == 7'b0000100) && (inst[24:20] == 5'b00000);
    assign inst_orcb  = is_bitman_imm && f3_101 && (inst[31:20] == 12'h287);
    assign inst_rev8  = is_bitman_imm && f3_101 && (inst[31:20] == 12'h698);
    assign inst_brev8 = is_bitman_imm && f3_101 && (inst[31:20] == 12'h687);
    assign inst_pack  = is_bitman && f3_100 && (inst[31:25] == 7'b0000100) && (inst[24:20] != 5'b00000);
    assign inst_packh = is_bitman && f3_111 && (inst[31:25] == 7'b0000100);
    assign inst_zip   = is_bitman_imm && f3_001 && (inst[31:25] == 7'b0000100) && (inst[24:20] == 5'b01111);
    assign inst_unzip = is_bitman_imm && f3_101 && (inst[31:25] == 7'b0000100) && (inst[24:20] == 5'b01111);
    assign inst_bclr  = is_bitman && f3_001 && (inst[31:25] == 7'b0100100);
    assign inst_bclri = is_bitman_imm && f3_001 && (inst[31:25] == 7'b0100100);
    assign inst_bext  = is_bitman && f3_101 && (inst[31:25] == 7'b0100100);
    assign inst_bexti = is_bitman_imm && f3_101 && (inst[31:25] == 7'b0100100);
    assign inst_binv  = is_bitman && f3_001 && (inst[31:25] == 7'b0110100);
    assign inst_binvi = is_bitman_imm && f3_001 && (inst[31:25] == 7'b0110100);
    assign inst_bset  = is_bitman && f3_001 && (inst[31:25] == 7'b0010100);
    assign inst_bseti = is_bitman_imm && f3_001 && (inst[31:25] == 7'b0010100);

    assign inst_bitman_any = inst_sh1add || inst_sh2add || inst_sh3add ||
                             inst_andn || inst_orn || inst_xnor ||
                             inst_min || inst_max || inst_minu || inst_maxu ||
                             inst_sextb || inst_sexth || inst_zexth ||
                             inst_orcb || inst_rev8 || inst_brev8 ||
                             inst_pack || inst_packh || inst_zip || inst_unzip ||
                             inst_bclr || inst_bclri || inst_bext || inst_bexti ||
                             inst_binv || inst_binvi || inst_bset || inst_bseti;
    assign inst_bitman_imm_inst = inst_bclri || inst_bexti || inst_binvi || inst_bseti;
    assign inst_bitman_rs2_inst = inst_sh1add || inst_sh2add || inst_sh3add ||
                                  inst_andn || inst_orn || inst_xnor ||
                                  inst_min || inst_max || inst_minu || inst_maxu ||
                                  inst_pack || inst_packh ||
                                  inst_bclr || inst_bext || inst_binv || inst_bset;

    logic [`BITMAN_OP_WIDTH-1:0] bitman_op;
    assign bitman_op = {
        inst_sh1add, inst_sh2add, inst_sh3add,
        inst_andn, inst_orn, inst_xnor,
        inst_min, inst_max, inst_minu, inst_maxu,
        inst_sextb, inst_sexth, inst_zexth,
        inst_orcb, inst_rev8, inst_brev8,
        inst_pack, inst_packh, inst_zip, inst_unzip,
        inst_bclr, inst_bclri, inst_bext, inst_bexti,
        inst_binv, inst_binvi, inst_bset, inst_bseti
    };
    assign bitman_packet = bitman_op;
    `else
    assign inst_bitman_any      = 1'b0;
    assign inst_bitman_imm_inst = 1'b0;
    assign inst_bitman_rs2_inst = 1'b0;
    `endif

    // ============================================================
    // Load / Store instructions
    // ============================================================
    logic inst_lw, inst_lb, inst_lh, inst_lbu, inst_lhu;
    logic inst_sw, inst_sb, inst_sh;
    assign inst_lw  = is_load_d  && f3_010;
    assign inst_lb  = is_load_d  && f3_000;
    assign inst_lh  = is_load_d  && f3_001;
    assign inst_lbu = is_load_d  && f3_100;
    assign inst_lhu = is_load_d  && f3_101;
    assign inst_sw  = is_store_d && f3_010;
    assign inst_sb  = is_store_d && f3_000;
    assign inst_sh  = is_store_d && f3_001;

    // ============================================================
    // Branch instructions
    // ============================================================
    logic inst_beq, inst_bne, inst_blt, inst_bge, inst_bltu, inst_bgeu;
    assign inst_beq  = is_branch_d && f3_000;
    assign inst_bne  = is_branch_d && f3_001;
    assign inst_blt  = is_branch_d && f3_100;
    assign inst_bge  = is_branch_d && f3_101;
    assign inst_bltu = is_branch_d && f3_110;
    assign inst_bgeu = is_branch_d && f3_111;

    // ============================================================
    // Jump instructions
    // ============================================================
    logic inst_jal, inst_jalr;
    assign inst_jal  = is_jal_d;
    assign inst_jalr = is_jalr_d;

    // ============================================================
    // ALU immediate instructions
    // ============================================================
    logic inst_addi, inst_slti, inst_sltiu, inst_xori, inst_ori, inst_andi;
    logic inst_slli, inst_srli, inst_srai;
    assign inst_addi  = is_op_imm && f3_000;
    assign inst_slti  = is_op_imm && f3_010;
    assign inst_sltiu = is_op_imm && f3_011;
    assign inst_xori  = is_op_imm && f3_100;
    assign inst_ori   = is_op_imm && f3_110;
    assign inst_andi  = is_op_imm && f3_111;
    assign inst_slli  = is_op_imm && f3_001 && f7_0000000;
    assign inst_srli  = is_op_imm && f3_101 && f7_0000000;
    assign inst_srai  = is_op_imm && f3_101 && f7_0100000;

    // ============================================================
    // ALU register-register instructions
    // ============================================================
    logic inst_add, inst_sub, inst_sll, inst_slt, inst_sltu;
    logic inst_xor_d, inst_or_d, inst_and_d, inst_srl, inst_sra;
    logic inst_mul, inst_mulh, inst_mulhsu, inst_mulhu;
    logic inst_div, inst_divu, inst_rem, inst_remu;
    assign inst_add  = is_op_reg && f3_000 && f7_0000000;
    assign inst_sub  = is_op_reg && f3_000 && f7_0100000;
    assign inst_sll  = is_op_reg && f3_001 && f7_0000000;
    assign inst_slt  = is_op_reg && f3_010 && f7_0000000;
    assign inst_sltu = is_op_reg && f3_011 && f7_0000000;
    assign inst_xor_d = is_op_reg && f3_100 && f7_0000000;
    assign inst_or_d  = is_op_reg && f3_110 && f7_0000000;
    assign inst_and_d = is_op_reg && f3_111 && f7_0000000;
    assign inst_srl  = is_op_reg && f3_101 && f7_0000000;
    assign inst_sra  = is_op_reg && f3_101 && f7_0100000;
    assign inst_mul    = is_op_reg && f3_000 && f7_0000001;
    assign inst_mulh   = is_op_reg && f3_001 && f7_0000001;
    assign inst_mulhsu = is_op_reg && f3_010 && f7_0000001;
    assign inst_mulhu  = is_op_reg && f3_011 && f7_0000001;
    assign inst_div    = is_op_reg && f3_100 && f7_0000001;
    assign inst_divu   = is_op_reg && f3_101 && f7_0000001;
    assign inst_rem    = is_op_reg && f3_110 && f7_0000001;
    assign inst_remu   = is_op_reg && f3_111 && f7_0000001;

    // ============================================================
    // System / CSR instructions
    // ============================================================
    logic inst_csrrw, inst_csrrs, inst_csrrc, inst_csrrwi, inst_csrrsi, inst_csrrci;
    logic inst_fence_d;
    assign inst_ecall  = is_system && f3_000 && inst[25:20] == 6'b000000;
    assign inst_ebreak = is_system && f3_000 && inst[25:20] == 6'b000001;
    assign inst_mret   = is_system && f3_000 && f7_0011000;
    assign inst_csrrw  = is_system && f3_001;
    assign inst_csrrs  = is_system && f3_010;
    assign inst_csrrc  = is_system && f3_011;
    assign inst_csrrwi = is_system && f3_101;
    assign inst_csrrsi = is_system && f3_110;
    assign inst_csrrci = is_system && f3_111;
    assign inst_fence_d = is_fence && f3_000;

    // ============================================================
    // Immediate selection
    // ============================================================
    assign IMI_valid = is_load_d || inst_addi || inst_slti || inst_sltiu ||
                       inst_xori || inst_ori || inst_andi ||
                       inst_slli || inst_srli || inst_srai || inst_jalr;
    assign IMS_valid = is_store_d;
    assign IMB_valid = is_branch_d;
    assign IMU_valid = is_lui_d || is_auipc_d;
    assign IMJ_valid = is_jal_d;
    assign IMZ_valid = inst_csrrwi || inst_csrrsi || inst_csrrci;

    // ============================================================
    // ALU packet
    // ============================================================
    logic alu_add, alu_sub, alu_and, alu_or, alu_xor;
    logic alu_sll, alu_srl, alu_sra, alu_slt, alu_sltu;
    assign alu_src2_imm_sel = is_op_imm || is_lui_d || is_auipc_d;
    assign alu_add = inst_add || inst_addi || inst_lui || inst_auipc;
    assign alu_sub = inst_sub;
    assign alu_and = inst_and_d || inst_andi;
    assign alu_or  = inst_or_d  || inst_ori;
    assign alu_xor = inst_xor_d || inst_xori;
    assign alu_sll = inst_sll || inst_slli;
    assign alu_srl = inst_srl || inst_srli;
    assign alu_sra = inst_sra || inst_srai;
    assign alu_slt = inst_slt || inst_slti;
    assign alu_sltu= inst_sltu || inst_sltiu;
    logic [9:0] alu_op;
    assign alu_op = {alu_add, alu_sub, alu_and, alu_or, alu_xor,
                     alu_sll, alu_srl, alu_sra, alu_slt, alu_sltu};
    assign alu_packet = alu_op;

    // ============================================================
    // MUL packet
    // ============================================================
    logic [3:0] mul_op;
    logic src1_signed, src2_signed;
    assign src1_signed = inst_mul || inst_mulh || inst_mulhsu || inst_div || inst_rem;
    assign src2_signed = inst_mul || inst_mulh || inst_div || inst_rem;
    assign mul_op = {inst_mul, (inst_mulh || inst_mulhsu || inst_mulhu),
                     (inst_div || inst_divu), (inst_rem || inst_remu)};
    assign mul_packet = {mul_op, src1_signed, src2_signed};

    // ============================================================
    // MEM packet
    // ============================================================
    logic [31:0] mem_imm;
    logic [4:0] mem_op;
    logic is_store_inst;
    assign is_store_inst = is_store_d;
    assign mem_imm = {32{IMS_valid}} & imm_s_ext | {32{IMI_valid}} & imm_i_ext;
    assign mem_op = {(inst_lb || inst_sb), (inst_lh || inst_sh), (inst_lw || inst_sw),
                     inst_lbu, inst_lhu};
    assign mem_packet = {mem_imm, mem_op, is_store_inst};

    // ============================================================
    // CSR packet
    // ============================================================
    logic [31:0] csr_rdata_out;
    logic [31:0] csr_imm;
    logic [11:0] csr_waddr;
    logic [2:0] csr_op;
    logic csr_wen;
    logic csr_imm_sel;
    logic csr_rdata_fwd;
    assign csr_rdata_out = csr_rdata;
    assign csr_imm      = {32{IMZ_valid}} & imm_z_ext;
    assign csr_waddr    = csr_addr;
    assign csr_op       = {(inst_csrrw || inst_csrrwi),
                           (inst_csrrs || inst_csrrsi),
                           (inst_csrrc || inst_csrrci)};
    assign csr_imm_sel  = inst_csrrwi || inst_csrrsi || inst_csrrci;
    assign csr_rdata_fwd = (exe_csr_wen && (exe_csr_addr == csr_addr));
    assign csr_wen = inst_csrrw || inst_csrrwi ||
                     ((inst_csrrs || inst_csrrc) && (rs1_addr != 5'b0)) ||
                     ((inst_csrrsi || inst_csrrci) && (imm_z != 5'b0));
    assign csr_packet = {csr_rdata_out, csr_imm, csr_waddr, csr_op,
                         csr_imm_sel, csr_rdata_fwd, csr_wen};

    // ============================================================
    // BR_JMP packet
    // ============================================================
    logic [31:0] br_jmp_target;
    logic [31:0] br_jmp_imm;
    logic [5:0] br_jmp_opcode;
    assign br_jmp_imm = ({32{IMB_valid}} & imm_b_ext) |
                        ({32{IMJ_valid}} & imm_j_ext) |
                        ({32{IMI_valid && is_jalr_d}} & imm_i_ext);
    assign br_jmp_opcode = {inst_beq, inst_bne, inst_blt, inst_bge, inst_bltu, inst_bgeu};
    assign br_jmp_target = pc + br_jmp_imm;
    assign br_jmp_packet = {bp_pred_hit, bp_pred_taken, bp_pred_target,
                            br_jmp_target, br_jmp_imm, br_jmp_opcode,
                            inst_jal, inst_jalr};

    // ============================================================
    // CTRL packet
    // ============================================================
    logic is_alu_inst, is_mul_inst, is_mem_inst, is_csr_inst, is_br_jmp_inst;
    logic is_bitman_inst;
    logic [4:0] ctrl_rd_addr;
    logic ctrl_regfile_wen;
    logic is_multicycle_inst;
    logic wb_exe_result, wb_mem_result;
    logic [1:0] exe_result_sel;
    assign is_bitman_inst = inst_bitman_any;
    assign is_alu_inst = alu_add || alu_sub || alu_and || alu_or || alu_xor ||
                         alu_sll || alu_srl || alu_sra || alu_slt || alu_sltu;
    assign is_mul_inst = inst_mul || inst_mulh || inst_mulhsu || inst_mulhu ||
                         inst_div || inst_divu || inst_rem || inst_remu;
    assign is_mem_inst = is_load_d || is_store_d;
    assign is_csr_inst = inst_csrrw || inst_csrrs || inst_csrrc ||
                         inst_csrrwi || inst_csrrsi || inst_csrrci;
    assign is_br_jmp_inst = is_branch_d || is_jal_d || is_jalr_d;
    assign ctrl_rd_addr = rd_addr;
    assign ctrl_regfile_wen = is_alu_inst || is_mul_inst || is_load_d ||
                              is_csr_inst || is_jal_d || is_jalr_d || is_bitman_inst;
    assign is_multicycle_inst = ((inst_mul || inst_mulh || inst_mulhsu || inst_mulhu) && `MUL_MULTICYCLE_ENABLE) ||
                                inst_div || inst_divu || inst_rem || inst_remu;
    assign wb_exe_result = is_alu_inst || is_mul_inst || is_csr_inst ||
                           is_jal_d || is_jalr_d || is_bitman_inst;
    assign wb_mem_result = is_mem_inst;
    assign exe_result_sel = {wb_exe_result, wb_mem_result};
    `ifdef Z_BITMAIN_ENABLE
    assign ctrl_packet = {pc, exe_result_sel, is_bitman_inst, is_alu_inst,
                          is_mul_inst, is_mem_inst, is_csr_inst, is_br_jmp_inst,
                          ctrl_rd_addr, ctrl_regfile_wen, is_multicycle_inst};
    `else
    assign ctrl_packet = {pc, exe_result_sel, is_alu_inst, is_mul_inst,
                          is_mem_inst, is_csr_inst, is_br_jmp_inst,
                          ctrl_rd_addr, ctrl_regfile_wen, is_multicycle_inst};
    `endif

    // ============================================================
    // Hazard preconditions
    // ============================================================
    assign need_rs1 = is_op_reg || is_op_imm || is_load_d || is_store_d ||
                      is_branch_d || inst_jalr ||
                      inst_csrrw || inst_csrrs || inst_csrrc;
    assign need_rs2 = is_op_reg || is_store_d || is_branch_d;

endmodule : decode_unit
