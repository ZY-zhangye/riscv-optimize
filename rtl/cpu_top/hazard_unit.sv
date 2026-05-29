`include "defines.svh"

// Hazard detection and forwarding control — extracted from id_stage for dual-issue.
// Produces forwarding select signals and load-use stall.
module hazard_unit (
    input logic [4:0] rs1_addr,
    input logic [4:0] rs2_addr,
    input logic need_rs1,
    input logic need_rs2,

    // From decode: instruction properties affecting forwarding
    input logic inst_lui,
    input logic inst_auipc,
    input logic alu_src2_imm_sel,
    input logic inst_bitman_imm_inst,
    input logic inst_bitman_any,
    input logic inst_bitman_rs2_inst,

    // Pipeline state for forwarding detection
    input logic [4:0] exe_dest_addr,
    input logic exe_regfile_wen,
    input logic es_valid,
    input logic [4:0] mem_dest_addr,
    input logic mem_regfile_wen,
    input logic ms_valid,

    // Load-use hazard inputs
    input logic prev_load,
    input logic ds_valid,

    // Outputs
    output logic [1:0] src1_fwd,
    output logic [1:0] src2_fwd,
    output logic load_use_hazard
);

    // ---- Forwarding control for src1 ----
    // lui/auipc have no rs1 dependency
    assign src1_fwd = (inst_lui || inst_auipc) ? 2'b00 :
                      (rs1_addr != 5'b0) ?
                      ((exe_regfile_wen && (exe_dest_addr == rs1_addr) && es_valid) ? 2'b01 :
                       (mem_regfile_wen && (mem_dest_addr == rs1_addr) && ms_valid) ? 2'b10 : 2'b00) : 2'b00;

    // ---- Forwarding control for src2 ----
    // alu_src2_imm_sel: src2 is immediate, no forwarding needed
    // bitman_imm: src2 is shamt field, no forwarding needed
    // bitman_any && !bitman_rs2: uses immediate, no forwarding needed
    assign src2_fwd = (alu_src2_imm_sel || inst_bitman_imm_inst ||
                       (inst_bitman_any && !inst_bitman_rs2_inst)) ? 2'b00 :
                      (rs2_addr != 5'b0) ?
                      ((exe_regfile_wen && (exe_dest_addr == rs2_addr) && es_valid) ? 2'b01 :
                       (mem_regfile_wen && (mem_dest_addr == rs2_addr) && ms_valid) ? 2'b10 : 2'b00) : 2'b00;

    // ---- Load-use hazard ----
    // Stall when current instruction reads a register that is being loaded
    // by the previous instruction (still in EX stage)
    logic exe_load_use;
    assign exe_load_use = ((need_rs1 && (rs1_addr != 5'b0) && (rs1_addr == exe_dest_addr)) ||
                           (need_rs2 && (rs2_addr != 5'b0) && (rs2_addr == exe_dest_addr))) &&
                           es_valid && exe_regfile_wen && prev_load;
    assign load_use_hazard = exe_load_use && ds_valid;

endmodule : hazard_unit
