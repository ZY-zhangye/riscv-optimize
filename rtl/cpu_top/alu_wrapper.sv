`include "defines.svh"

// ALU包装单元
// 将所有ALU操作集中在一个模块中，便于后续双发射时复用
module alu_wrapper (
    input logic [9:0] alu_op,      // ALU操作码
    input logic [31:0] src1,       // 操作数1
    input logic [31:0] src2,       // 操作数2

    output logic [31:0] alu_result // ALU计算结果
);

    always_comb begin
        case (1'b1)
            alu_op[9]: alu_result = src1 + src2;           // ADD
            alu_op[8]: alu_result = src1 - src2;           // SUB
            alu_op[7]: alu_result = src1 & src2;           // AND
            alu_op[6]: alu_result = src1 | src2;           // OR
            alu_op[5]: alu_result = src1 ^ src2;           // XOR
            alu_op[4]: alu_result = src1 << src2[4:0];     // SLL
            alu_op[3]: alu_result = src1 >> src2[4:0];     // SRL
            alu_op[2]: alu_result = $signed(src1) >>> src2[4:0];  // SRA
            alu_op[1]: alu_result = ($signed(src1) < $signed(src2)) ? 32'h1 : 32'h0;  // SLT
            alu_op[0]: alu_result = (src1 < src2) ? 32'h1 : 32'h0;  // SLTU
            default:   alu_result = 32'b0;
        endcase
    end

endmodule : alu_wrapper
