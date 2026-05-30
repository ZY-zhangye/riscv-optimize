`include "defines.svh"

// Issue select: picks which lane(s) to issue each cycle.
// P3: always lane0 only, lane1 is shadow (does not go to EX).
// P4+: full pairing rules when DUAL_ISSUE_COMMIT_ENABLE is on.
module issue_select (
    // ---- Lane0 decode ----
    input  logic lane0_valid,
    input  logic [4:0] lane0_rd_addr,
    input  logic [4:0] lane0_rs1_addr,
    input  logic [4:0] lane0_rs2_addr,
    input  logic lane0_need_rs1,
    input  logic lane0_need_rs2,
    input  logic lane0_is_alu,
    input  logic lane0_is_mul,
    input  logic lane0_is_mem,
    input  logic lane0_is_csr,
    input  logic lane0_is_br_jmp,
    input  logic lane0_is_system,
    input  logic lane0_regfile_wen,

    // ---- Lane1 decode ----
    input  logic lane1_valid,
    input  logic [4:0] lane1_rd_addr,
    input  logic [4:0] lane1_rs1_addr,
    input  logic [4:0] lane1_rs2_addr,
    input  logic lane1_need_rs1,
    input  logic lane1_need_rs2,
    input  logic lane1_is_alu,
    input  logic lane1_is_mul,
    input  logic lane1_is_mem,
    input  logic lane1_is_csr,
    input  logic lane1_is_br_jmp,
    input  logic lane1_is_system,
    input  logic lane1_regfile_wen,

    // ---- Pipeline status ----
    input  logic ds_allowin,        // EX can accept new instruction

    // ---- Issue outputs ----
    output logic issue0_valid,
    output logic issue1_valid,
    output logic [1:0] pop_count,   // how many to pop from queue (0/1/2)

    // ---- Shadow signals (P3 debug) ----
    output logic lane1_simple_alu,  // lane1 is simple ALU only
    output logic lane0_not_ctrl,    // lane0 not branch/jump/system
    output logic no_raw_hazard,     // lane1 doesn't read lane0's rd
    output logic no_waw_hazard,     // lane0 and lane1 don't write same rd
    output logic lane1_can_pair     // all pairing conditions met
);

    // ============================================================
    // Pairing checks (used for both shadow and actual issue)
    // ============================================================
    // P5a: lane1 can be simple ALU or branch/jump (no mul/mem/csr/system)
    assign lane1_simple_alu = lane1_valid &&
                              (lane1_is_alu || lane1_is_br_jmp) &&
                              !lane1_is_mul &&
                              !lane1_is_mem &&
                              !lane1_is_csr &&
                              !lane1_is_system;

    // P4: lane0 still cannot be branch/jump/system when pairing
    assign lane0_not_ctrl = lane0_valid &&
                            !lane0_is_br_jmp &&
                            !lane0_is_system;

    // RAW: lane1 reads a register that lane0 writes (intra-pair RAW)
    assign no_raw_hazard = !(lane0_valid && lane0_regfile_wen && (lane0_rd_addr != 5'b0) && lane1_valid &&
                             ((lane1_need_rs1 && (lane1_rs1_addr == lane0_rd_addr)) ||
                              (lane1_need_rs2 && (lane1_rs2_addr == lane0_rd_addr))));

    // WAW: both lanes write the same non-zero register
    assign no_waw_hazard = !(lane0_valid && lane1_valid &&
                             lane0_regfile_wen && lane1_regfile_wen &&
                             (lane0_rd_addr != 5'b0) &&
                             (lane0_rd_addr == lane1_rd_addr));

    // P4a: at most one writer per pair (simplifies WB arbitration)
    // P5a fix: x0 writes are no-ops, exclude from single_writer check
    logic single_writer;
    assign single_writer = !(lane0_valid && lane1_valid &&
                             lane0_regfile_wen && (lane0_rd_addr != 5'b0) &&
                             lane1_regfile_wen && (lane1_rd_addr != 5'b0));

    // Base pairing condition
    assign lane1_can_pair = lane0_valid && lane1_valid &&
                            lane1_simple_alu &&
                            lane0_not_ctrl &&
                            no_raw_hazard &&
                            no_waw_hazard &&
                            single_writer;

    // ============================================================
    // Issue decision
    // ============================================================
    `ifdef DUAL_ISSUE_COMMIT_ENABLE
    // P4+: actual dual-issue when pairing conditions are met
    logic can_dual_issue;
    assign can_dual_issue = lane1_can_pair;

    assign issue0_valid = lane0_valid && ds_allowin;
    assign issue1_valid = can_dual_issue && ds_allowin;
    assign pop_count = (can_dual_issue && ds_allowin) ? 2'd2 :
                       (lane0_valid && ds_allowin)     ? 2'd1 : 2'd0;
    `else
    // P3: always lane0 only, lane1 is shadow
    assign issue0_valid = lane0_valid && ds_allowin;
    assign issue1_valid = 1'b0;
    assign pop_count = issue0_valid ? 2'd1 : 2'd0;
    `endif

endmodule : issue_select
