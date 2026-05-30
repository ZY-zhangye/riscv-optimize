`include "defines.svh"

// Lane1 execution unit for dual-issue.
// P4: Simple ALU only (reg/imm + LUI/AUIPC)
// P5a: Extended to support branch/jump (branch_controller instantiated)
// 2-stage pipeline (EX1 + MEM1 bubble) to match lane0's EX+MEM timing.
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

    // ---- P5b: dmem read data (for lane1 loads) ----
    input  logic [31:0] dmem_rdata,

    // ---- To WB (matches ms_to_ws_bus format) ----
    output logic ms1_to_ws_valid,
    input  logic ws_allowin,
    output logic [`MS_WS_WIDTH-1:0] ms1_to_ws_bus,

    // ---- Forwarding outputs (for next instructions) ----
    output logic [4:0] exe1_dest_addr,
    output logic exe1_regfile_wen,
    output logic es1_valid,

    // ---- P5a: Lane1 branch redirect outputs ----
    output logic lane1_br_redirect,
    output logic [31:0] lane1_br_redirect_target,
    output logic lane1_bp_update_valid,
    output logic [31:0] lane1_bp_update_pc,
    output logic lane1_bp_update_taken,
    output logic [31:0] lane1_bp_update_target,
    output logic lane1_bp_update_is_jalr,
    // ---- P5a: Lane1 performance counters ----
    output logic lane1_perf_branch_valid,
    output logic lane1_perf_branch_mispredict,
    output logic lane1_perf_bp_hit,
    output logic lane1_perf_bp_miss,

    // ---- P5b: Lane1 dmem interface (store support) ----
    output logic [31:0] lane1_dmem_addr,
    output logic [31:0] lane1_dmem_wdata,
    output logic [3:0]  lane1_dmem_wen,
    output logic        lane1_dmem_en,
    output logic        lane1_is_mem_op      // lane1 is executing a memory op
);

    // ============================================================
    // Stage 1: EX1 (ALU execution)
    // ============================================================
    logic es1_ready_go;
    logic ms1_valid, ms1_allowin;  // assigned in Stage 2 section below
    logic ms1_ready_go;            // assigned in Stage 2 section below
    assign es1_ready_go = 1'b1;  // ALU is always ready (single-cycle)
    assign es_allowin = !es1_valid || (es1_ready_go && ms1_allowin);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            es1_valid <= 1'b0;
        else if (es_allowin)
            es1_valid <= ds_to_es_valid;
    end

    // Latch input data (EX1 entry)
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

    // BR_JMP — second-level unpack (P5a: used for branch_controller)
    logic        bp_pred_hit, bp_pred_taken;
    logic [31:0] bp_pred_target;
    logic [31:0] br_jmp_target;
    logic [31:0] br_jmp_imm;
    logic [5:0]  br_jmp_opcode;
    logic        is_jal, is_jalr;
    assign {bp_pred_hit, bp_pred_taken, bp_pred_target,
            br_jmp_target, br_jmp_imm, br_jmp_opcode,
            is_jal, is_jalr} = br_jmp_packet;

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

    // MEM — second-level unpack (P5b: used for store address/data)
    logic [31:0] mem_imm;
    logic [4:0]  mem_op;
    logic        is_store;
    assign {mem_imm, mem_op, is_store} = mem_packet;

    // P5b: mem control pipeline — capture at EX1 entry, use at EX1→MEM1 shift
    // Key insight: when instruction leaves EX1 for MEM1, mem_op_ex1 OLD value
    // is exactly that instruction's mem_op (set at its EX1 entry, not yet overwritten).
    logic [4:0]  mem_op_ex1;
    logic        is_store_ex1;
    // Forward-declare mem_op pipeline registers (used in combined block below)
    logic [4:0]  exe1_mem_op_reg;
    logic        exe1_is_store_reg;

    // Extract mem_op from INPUT bus (ds_to_es_bus, before registration)
    // This avoids the NBA ordering issue with ds_to_es_bus_r
    logic [4:0]  input_mem_op;
    logic        input_is_store;
    logic [31:0] input_mem_imm;
    logic [`MEM_PACKET_WIDTH-1:0] input_mem_packet;
    `ifdef Z_BITMAIN_ENABLE
    assign input_mem_packet = ds_to_es_bus[`DS_ES_WIDTH-1-`ALU_PACKET_WIDTH-`MUL_PACKET_WIDTH-`BITMAN_PACKET_WIDTH
                                -:`MEM_PACKET_WIDTH];
    `else
    assign input_mem_packet = ds_to_es_bus[`DS_ES_WIDTH-1-`ALU_PACKET_WIDTH-`MUL_PACKET_WIDTH
                                -:`MEM_PACKET_WIDTH];
    `endif
    assign {input_mem_imm, input_mem_op, input_is_store} = input_mem_packet;

    // Forward-declare pipeline registers used in merged always_ff below
    logic [31:0] exe1_result;
    logic [31:0] exe1_result_reg;
    logic [4:0]  exe1_rd_addr_reg;
    logic        exe1_regfile_wen_reg;
    logic [31:0] exe1_pc_reg;
    logic        exe1_flush_reg;
    logic [1:0]  exe1_addr_low_reg;
    logic [31:0] ms1_result;
    logic [4:0]  ms1_rd_addr;
    logic        ms1_regfile_wen;
    logic [31:0] ms1_pc;

    // Merged always_ff: EX1 entry + all pipeline shifts
    // All mem control and result pipelines in ONE block for deterministic ordering
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_op_ex1 <= '0;
            is_store_ex1 <= 1'b0;
            exe1_mem_op_reg <= '0;
            exe1_is_store_reg <= 1'b0;
            exe1_result_reg <= '0;
            exe1_rd_addr_reg <= '0;
            exe1_regfile_wen_reg <= 1'b0;
            exe1_pc_reg <= '0;
            exe1_flush_reg <= 1'b0;
            exe1_addr_low_reg <= '0;
            ms1_result <= '0;
            ms1_rd_addr <= '0;
            ms1_regfile_wen <= 1'b0;
            ms1_pc <= '0;
        end else begin
            // Stage 0: capture at EX1 entry
            if (ds_to_es_valid && es_allowin) begin
                mem_op_ex1 <= input_mem_op;
                is_store_ex1 <= input_is_store;
            end
            // Stage 0→1: EX1→MEM1 shift (mem_op_ex1 OLD = this inst's value)
            if (es1_valid && es1_ready_go) begin
                exe1_mem_op_reg <= mem_op_ex1;
                exe1_is_store_reg <= is_store_ex1;
                exe1_result_reg <= exe1_result;
                exe1_rd_addr_reg <= rd_addr;
                exe1_regfile_wen_reg <= regfile_wen && !es1_flush;
                exe1_pc_reg <= exe_pc;
                exe1_flush_reg <= es1_flush;
                exe1_addr_low_reg <= exe1_result[1:0];
            end
            // Stage 1→2: MEM1→WB shift
            if ((es1_valid && es1_ready_go) && ms1_allowin) begin
                ms1_result <= exe1_result_reg;
                ms1_rd_addr <= exe1_rd_addr_reg;
                ms1_regfile_wen <= exe1_regfile_wen_reg && !exe1_flush_reg;
                ms1_pc <= exe1_pc_reg;
            end
        end
    end

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

    // ---- P5a: Branch controller (reuses lane0's branch_controller) ----
    logic lane1_br_taken;
    logic [31:0] lane1_br_target;

    branch_controller u_branch_controller1 (
        .bp_pred_hit(bp_pred_hit),
        .bp_pred_taken(bp_pred_taken),
        .bp_pred_target(bp_pred_target),
        .br_jmp_target(br_jmp_target),
        .br_jmp_imm(br_jmp_imm),
        .br_jmp_opcode(br_jmp_opcode),
        .is_jal(is_jal),
        .is_jalr(is_jalr),
        .src1(src1),
        .src2(src2),
        .exe_pc(exe_pc),
        .es_flush(es1_flush),
        .es_valid(es1_valid),
        .br_taken(lane1_br_taken),
        .br_target(lane1_br_target),
        .br_redirect(lane1_br_redirect),
        .br_redirect_target(lane1_br_redirect_target),
        .bp_update_valid(lane1_bp_update_valid),
        .bp_update_pc(lane1_bp_update_pc),
        .bp_update_taken(lane1_bp_update_taken),
        .bp_update_target(lane1_bp_update_target),
        .bp_update_is_jalr(lane1_bp_update_is_jalr),
        .perf_branch_valid(lane1_perf_branch_valid),
        .perf_branch_mispredict(lane1_perf_branch_mispredict),
        .perf_bp_hit(lane1_perf_bp_hit),
        .perf_bp_miss(lane1_perf_bp_miss)
    );

    // ---- Result selection (ALU or PC+4 for JAL/JALR link) ----
    always_comb begin
        if (es1_flush)
            exe1_result = 32'b0;
        else if (is_br_jmp)
            exe1_result = exe_pc + 32'd4;  // JAL/JALR link address
        else if (is_mem)
            exe1_result = src1 + mem_imm;   // load/store address
        else
            exe1_result = alu_result;
    end

    // ---- P5b: Lane1 dmem store interface ----
    logic inst_sb1, inst_sh1, inst_sw1;
    assign inst_sb1 = mem_op[4] & is_store;
    assign inst_sh1 = mem_op[3] & is_store;
    assign inst_sw1 = mem_op[2] & is_store;

    // Byte/halfword store data replication
    logic [31:0] lane1_store_data;
    assign lane1_store_data = inst_sb1 ? {4{src2[7:0]}} :
                              inst_sh1 ? {2{src2[15:0]}} : src2;

    // Store byte-enable generation (same as exe_stage)
    logic [3:0] sb_wen1, sh_wen1;
    always_comb begin
        case (exe1_result[1:0])
            2'b00: sb_wen1 = 4'b0001;
            2'b01: sb_wen1 = 4'b0010;
            2'b10: sb_wen1 = 4'b0100;
            default: sb_wen1 = 4'b1000;
        endcase
    end
    always_comb begin
        case (exe1_result[1])
            1'b0: sh_wen1 = 4'b0011;
            default: sh_wen1 = 4'b1100;
        endcase
    end
    always_comb begin
        lane1_dmem_wen = 4'b0000;
        if (!es1_flush) begin
            unique case (1'b1)
                inst_sb1: lane1_dmem_wen = sb_wen1;
                inst_sh1: lane1_dmem_wen = sh_wen1;
                inst_sw1: lane1_dmem_wen = 4'b1111;
                default:  lane1_dmem_wen = 4'b0000;
            endcase
        end
    end

    assign lane1_dmem_addr = exe1_result;
    assign lane1_dmem_wdata = lane1_store_data;
    assign lane1_dmem_en   = |mem_op && !es1_flush;
    assign lane1_is_mem_op = is_mem && es1_valid && !es1_flush;



    // P5b: Load data extraction signals (combinational from registered values)
    logic load_lb1, load_lh1, load_lw1, load_lbu1, load_lhu1;
    logic is_load1;
    logic [7:0]  load_byte1;
    logic [15:0] load_half1;
    logic [31:0] load_data1;

    // Combinational load data extraction (from registered dmem_rdata at posedge)
    assign load_lb1  = exe1_mem_op_reg[4] & ~exe1_is_store_reg;
    assign load_lh1  = exe1_mem_op_reg[3] & ~exe1_is_store_reg;
    assign load_lw1  = exe1_mem_op_reg[2] & ~exe1_is_store_reg;
    assign load_lbu1 = exe1_mem_op_reg[1] & ~exe1_is_store_reg;
    assign load_lhu1 = exe1_mem_op_reg[0] & ~exe1_is_store_reg;
    assign is_load1  = load_lb1 || load_lh1 || load_lw1 || load_lbu1 || load_lhu1;

    // Byte selection from dmem_rdata
    always_comb begin
        unique case (exe1_addr_low_reg)
            2'b00: load_byte1 = dmem_rdata[7:0];
            2'b01: load_byte1 = dmem_rdata[15:8];
            2'b10: load_byte1 = dmem_rdata[23:16];
            default: load_byte1 = dmem_rdata[31:24];
        endcase
    end
    always_comb begin
        unique case (exe1_addr_low_reg[1])
            1'b0: load_half1 = dmem_rdata[15:0];
            default: load_half1 = dmem_rdata[31:16];
        endcase
    end
    always_comb begin
        load_data1 = dmem_rdata;
        unique case (1'b1)
            load_lb1:  load_data1 = {{24{load_byte1[7]}}, load_byte1};
            load_lbu1: load_data1 = {24'b0, load_byte1};
            load_lh1:  load_data1 = {{16{load_half1[15]}}, load_half1};
            load_lhu1: load_data1 = {16'b0, load_half1};
            default:   load_data1 = dmem_rdata;
        endcase
    end


    // ---- MEM1 allowin / valid (forward-declared at line 64) ----
    assign ms1_ready_go = 1'b1;
    assign ms1_allowin = !ms1_valid || (ms1_ready_go && ws_allowin);
    assign ms1_to_ws_valid = ms1_valid && ms1_ready_go;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ms1_valid <= 1'b0;
        else if (ms1_allowin)
            ms1_valid <= (es1_valid && es1_ready_go);
    end

    // Output bus — combinational mux for loads (like mem_stage uses mem_result)
    // In MEM1: ms1_valid=1, is_load1 gates whether load_data1 or ms1_result is used.
    // load_data1 is combinational from dmem_rdata (registered memory output).
    assign ms1_to_ws_bus = {
        ms1_pc,
        (ms1_valid && is_load1) ? load_data1 : ms1_result,
        ms1_rd_addr,
        ms1_regfile_wen
    };

endmodule : exe_lane_simple
