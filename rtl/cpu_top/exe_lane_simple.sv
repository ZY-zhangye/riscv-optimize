`include "defines.svh"

// Simple ALU execution lane for lane1 in dual-issue.
// P4: 2-stage pipeline (EX1 + MEM1 bubble) to match lane0's EX+MEM timing.
// Only supports simple ALU reg/imm + LUI/AUIPC — no branch, load, store, CSR, mul.
module exe_lane_simple (
    input logic clk,
    input logic rst_n,

    // ---- From ID stage (lane1) ----
    input  logic ds_to_es_valid,
    output logic es_allowin,
    input  logic [`DS_ES_WIDTH-1:0] ds_to_es_bus,
    input  logic ds_flush,

    // ---- Lane0 flush (kills lane1) ----
    input  logic lane0_es_flush,
    input  logic exception_flag,

    // ---- Forwarding from lane0 EX/MEM ----
    input  logic [31:0] lane0_exe_result,
    input  logic [31:0] lane0_mem_result,

    // ---- To WB (matches ms_to_ws_bus format) ----
    output logic ms1_to_ws_valid,
    input  logic ws_allowin,
    output logic [`MS_WS_WIDTH-1:0] ms1_to_ws_bus,

    // ---- Forwarding outputs (for next instructions) ----
    output logic [4:0] exe1_dest_addr,
    output logic exe1_regfile_wen,
    output logic es1_valid
);

    // ============================================================
    // Stage 1: EX1 (ALU execution)
    // ============================================================
    logic es1_ready_go;
    logic ms1_valid, ms1_allowin;  // forward declaration, assigned in Stage 2
    assign es1_ready_go = 1'b1;  // ALU is always ready (single-cycle)
    assign es_allowin = !es1_valid || (es1_ready_go && ms1_allowin);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            es1_valid <= 1'b0;
        else if (es_allowin)
            es1_valid <= ds_to_es_valid;
    end

    // Latch input data
    logic [`DS_ES_WIDTH-1:0] ds_to_es_bus_r;
    logic ds_flush_r;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ds_to_es_bus_r <= '0;
            ds_flush_r <= 1'b0;
        end else if (ds_to_es_valid && es_allowin) begin
            ds_to_es_bus_r <= ds_to_es_bus;
            ds_flush_r <= ds_flush;
        end
    end

    // Flush: killed by lane0 redirect/exception
    logic es1_flush;
    assign es1_flush = rst_n && (ds_flush_r || lane0_es_flush || exception_flag);

    // ---- Unpack ds_to_es_bus ----
    logic [`ALU_PACKET_WIDTH-1:0]   alu_packet;
    logic [`MUL_PACKET_WIDTH-1:0]   mul_packet;
    logic [`MEM_PACKET_WIDTH-1:0]   mem_packet;
    logic [`CSR_PACKET_WIDTH-1:0]   csr_packet;
    logic [`BR_JMP_PACKET_WIDTH-1:0] br_jmp_packet;
    logic [`CTRL_PACKET_WIDTH-1:0]  ctrl_packet;
    logic [`SRC_PACKET_WIDTH-1:0]   src_packet;

    `ifdef Z_BITMAIN_ENABLE
    logic [`BITMAN_PACKET_WIDTH-1:0] bitman_packet;
    assign {bitman_packet, alu_packet, mul_packet, mem_packet,
            csr_packet, br_jmp_packet, ctrl_packet, src_packet} = ds_to_es_bus_r;
    `else
    assign {alu_packet, mul_packet, mem_packet,
            csr_packet, br_jmp_packet, ctrl_packet, src_packet} = ds_to_es_bus_r;
    `endif

    // ALU op
    logic [9:0] alu_op;
    assign alu_op = alu_packet[9:0];

    // CTRL
    logic is_alu, is_mul, is_mem, is_csr, is_br_jmp;
    logic [4:0] rd_addr;
    logic regfile_wen;
    logic [1:0] exe_result_sel;
    logic [31:0] exe_pc;
    `ifdef Z_BITMAIN_ENABLE
    logic is_bitman;
    assign {exe_pc, exe_result_sel, is_bitman, is_alu, is_mul, is_mem,
            is_csr, is_br_jmp, rd_addr, regfile_wen, is_multicycle} = ctrl_packet;
    `else
    logic is_multicycle;
    assign {exe_pc, exe_result_sel, is_alu, is_mul, is_mem,
            is_csr, is_br_jmp, rd_addr, regfile_wen, is_multicycle} = ctrl_packet;
    `endif

    // SRC
    logic [31:0] reg_src1, reg_src2;
    logic [1:0] src1_fwd, src2_fwd;
    assign {reg_src1, reg_src2, src1_fwd, src2_fwd} = src_packet;

    // ---- Operand selection (forwarding from lane0 EX/MEM) ----
    logic [31:0] src1, src2;

    // Simplified forwarding: lane1 can only forward from lane0's EX/MEM
    // (lane1 cannot forward from another lane1 instance in P4)
    assign src1 = (src1_fwd == 2'b01) ? lane0_exe_result :
                  (src1_fwd == 2'b10) ? lane0_mem_result : reg_src1;
    assign src2 = (src2_fwd == 2'b01) ? lane0_exe_result :
                  (src2_fwd == 2'b10) ? lane0_mem_result : reg_src2;

    // ---- ALU execution ----
    logic [31:0] alu_result;
    alu_wrapper u_alu_wrapper1 (
        .alu_op(alu_op),
        .src1(src1),
        .src2(src2),
        .alu_result(alu_result)
    );

    // ---- Result selection (ALU or PC+4 for JAL/BR placeholder) ----
    logic [31:0] exe1_result;
    always_comb begin
        if (es1_flush)
            exe1_result = 32'b0;
        else
            exe1_result = alu_result;
    end

    // ---- Latch EX1 result for next stage ----
    logic [31:0] exe1_result_reg;
    logic [4:0]  exe1_rd_addr_reg;
    logic        exe1_regfile_wen_reg;
    logic [31:0] exe1_pc_reg;
    logic        exe1_flush_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            exe1_result_reg <= '0;
            exe1_rd_addr_reg <= '0;
            exe1_regfile_wen_reg <= 1'b0;
            exe1_pc_reg <= '0;
            exe1_flush_reg <= 1'b0;
        end else if (es1_valid && es1_ready_go) begin
            exe1_result_reg <= exe1_result;
            exe1_rd_addr_reg <= rd_addr;
            exe1_regfile_wen_reg <= regfile_wen && !es1_flush;
            exe1_pc_reg <= exe_pc;
            exe1_flush_reg <= es1_flush;
        end
    end

    // Forwarding outputs — valid while result is in EX1 or MEM1 (before regfile)
    assign exe1_dest_addr   = rd_addr;
    assign exe1_regfile_wen = regfile_wen && !es1_flush && (es1_valid || ms1_valid);

    // ============================================================
    // Stage 2: MEM1 (bubble — matches lane0's MEM timing)
    // ============================================================
    logic ms1_ready_go;
    assign ms1_ready_go = 1'b1;
    assign ms1_allowin = !ms1_valid || (ms1_ready_go && ws_allowin);
    assign ms1_to_ws_valid = ms1_valid && ms1_ready_go;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ms1_valid <= 1'b0;
        else if (ms1_allowin)
            ms1_valid <= (es1_valid && es1_ready_go);
    end

    logic [31:0] ms1_result;
    logic [4:0]  ms1_rd_addr;
    logic        ms1_regfile_wen;
    logic [31:0] ms1_pc;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ms1_result <= '0;
            ms1_rd_addr <= '0;
            ms1_regfile_wen <= 1'b0;
            ms1_pc <= '0;
        end else if ((es1_valid && es1_ready_go) && ms1_allowin) begin
            ms1_result <= exe1_result_reg;
            ms1_rd_addr <= exe1_rd_addr_reg;
            ms1_regfile_wen <= exe1_regfile_wen_reg && !exe1_flush_reg;
            ms1_pc <= exe1_pc_reg;
        end
    end

    // Output bus matching ms_to_ws_bus format: {pc, result, rd_addr, regfile_wen}
    assign ms1_to_ws_bus = {
        ms1_pc,
        ms1_result,
        ms1_rd_addr,
        ms1_regfile_wen
    };

endmodule : exe_lane_simple
