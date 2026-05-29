`include "defines.svh"

// Branch/jump resolution and prediction update — extracted from exe_stage.
// Centralizes branch condition evaluation, redirect generation, and BP update.
module branch_controller (
    // Branch/jump packet (unpacked from ds_to_es_bus)
    input logic bp_pred_hit,
    input logic bp_pred_taken,
    input logic [31:0] bp_pred_target,
    input logic [31:0] br_jmp_target,
    input logic [31:0] br_jmp_imm,
    input logic [5:0] br_jmp_opcode,
    input logic is_jal,
    input logic is_jalr,

    // Operands
    input logic [31:0] src1,
    input logic [31:0] src2,

    // Pipeline context
    input logic [31:0] exe_pc,
    input logic es_flush,
    input logic es_valid,

    // Outputs — branch result
    output logic br_taken,
    output logic [31:0] br_target,
    // Redirect
    output logic br_redirect,
    output logic [31:0] br_redirect_target,
    // BP update
    output logic bp_update_valid,
    output logic [31:0] bp_update_pc,
    output logic bp_update_taken,
    output logic [31:0] bp_update_target,
    output logic bp_update_is_jalr,
    // Performance counters
    output logic perf_branch_valid,
    output logic perf_branch_mispredict,
    output logic perf_bp_hit,
    output logic perf_bp_miss
);

    // ---- Unpack branch opcode ----
    logic is_beq, is_bne, is_blt, is_bge, is_bltu, is_bgeu;
    assign is_beq  = br_jmp_opcode[5];
    assign is_bne  = br_jmp_opcode[4];
    assign is_blt  = br_jmp_opcode[3];
    assign is_bge  = br_jmp_opcode[2];
    assign is_bltu = br_jmp_opcode[1];
    assign is_bgeu = br_jmp_opcode[0];

    logic is_br_jmp;
    assign is_br_jmp = |br_jmp_opcode || is_jal || is_jalr;

    // ---- Compare logic ----
    logic [32:0] sub_res;
    assign sub_res = {1'b0, src1} - {1'b0, src2};

    logic eq, lt, ltu;
    assign eq  = (src1 == src2);
    assign ltu = sub_res[32];
    assign lt  = (src1[31] != src2[31]) ? src1[31] : ltu;

    logic br_cond_raw;
    assign br_cond_raw = (is_beq  & eq)
                       | (is_bne  & !eq)
                       | (is_blt  & lt)
                       | (is_bge  & !lt)
                       | (is_bltu & ltu)
                       | (is_bgeu & !ltu);

    // ---- Branch taken / target ----
    assign br_taken = es_flush ? 1'b0 :
                      (is_jal | is_jalr | (|br_jmp_opcode & br_cond_raw));

    logic [31:0] jalr_sum;
    logic [31:0] pc_jalr;
    assign jalr_sum = src1 + br_jmp_imm;
    assign pc_jalr = { jalr_sum[31:1], 1'b0 };
    assign br_target = is_jalr ? pc_jalr : br_jmp_target;

    // ---- Redirect ----
    assign br_redirect = !es_flush && is_br_jmp &&
                         ((br_taken != bp_pred_taken) ||
                          (br_taken && (br_target != bp_pred_target)));
    assign br_redirect_target = br_taken ? br_target : exe_pc + 32'd4;

    // ---- BP update ----
    assign bp_update_valid    = es_valid && !es_flush && is_br_jmp;
    assign bp_update_pc       = exe_pc;
    assign bp_update_taken    = br_taken;
    assign bp_update_target   = br_target;
    assign bp_update_is_jalr  = is_jalr;

    // ---- Performance counters ----
    assign perf_branch_valid      = bp_update_valid;
    assign perf_branch_mispredict = br_redirect;
    assign perf_bp_hit            = bp_update_valid && !is_jalr && bp_pred_hit;
    assign perf_bp_miss           = bp_update_valid && !is_jalr && !bp_pred_hit;

endmodule : branch_controller
