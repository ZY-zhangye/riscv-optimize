`include "defines.svh"
module exe_stage(
    input logic clk,
    input logic rst_n,
    //握手信号
    input logic ds_to_es_valid,
    output logic es_allowin,
    input logic ms_allowin,
    output logic es_to_ms_valid,
    //来自ID阶段的信息
    input logic ds_flush,
    input logic [`DS_ES_WIDTH-1:0] ds_to_es_bus,
    //输出到MEM阶段的信息
    output logic [`ES_MS_WIDTH-1:0] es_to_ms_bus,
    output logic es_flush,
    //mem阶段数据前递接口
    input logic [31:0] mem_result,
    //DMEM接口
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    output logic [3:0] dmem_wen,
    output logic dmem_en,
    //数据前递接口-仅地址
    output logic [4:0] exe_dest_addr,
    output logic exe_regfile_wen,
    output logic [11:0] exe_csr_addr,
    output logic exe_csr_wen,
    output logic es_valid,
    //异常接口
    input logic [`EXC_WIDTH-1:0] ds_exc_bus,
    output logic [`EXE_EXC_BUS - 1:0] exe_exc_bus,
    input logic exception_flag,
    //跳转接口
    output logic br_taken,
    output logic [31:0] br_target,
    output logic br_redirect,
    output logic [31:0] br_redirect_target,
    output logic bp_update_valid,
    output logic [31:0] bp_update_pc,
    output logic bp_update_taken,
    output logic [31:0] bp_update_target,
    output logic bp_update_is_jalr,
    output logic perf_branch_valid,
    output logic perf_branch_mispredict,
    output logic perf_bp_hit,
    output logic perf_bp_miss,
    output logic perf_ex_stall
    `ifdef DUAL_ISSUE_COMMIT_ENABLE
    ,
    output logic [31:0] exe_fwd_result   // EX result for lane1 forwarding
    `endif
);

    // ============================================================
    // Pipeline control
    // ============================================================
    logic es_ready_go;
    logic mul_stall;
    assign es_ready_go = !mul_stall;
    assign es_allowin = !es_valid || (es_ready_go && ms_allowin);
    assign es_to_ms_valid = es_valid && es_ready_go;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            es_valid <= 1'b0;
        end else if (es_allowin) begin
            es_valid <= ds_to_es_valid;
        end
    end

    // ============================================================
    // Data latching
    // ============================================================
    logic [`DS_ES_WIDTH-1:0] ds_to_es_bus_r;
    logic ds_flush_r;
    logic [31:0] exe_result;
    logic [31:0] csr_wdata;
    logic [31:0] csr_wdata_reg;
    logic [31:0] mem_result_reg;
    logic [31:0] exe_result_reg;
    logic [`EXC_WIDTH-1:0] ds_exc_bus_r;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ds_to_es_bus_r <= '0;
            exe_result_reg <= '0;
            csr_wdata_reg <= '0;
            ds_flush_r <= 1'b0;
            ds_exc_bus_r <= '0;
        end else if (ds_to_es_valid && es_allowin) begin
            ds_flush_r <= ds_flush;
            ds_to_es_bus_r <= ds_to_es_bus;
            ds_exc_bus_r <= ds_exc_bus;
            exe_result_reg <= exe_result;
            csr_wdata_reg <= csr_wdata;
        end
    end
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mem_result_reg <= '0;
        end else if (ds_to_es_valid && es_allowin) begin
            mem_result_reg <= mem_result;
        end
    end
    assign es_flush = rst_n && (ds_flush_r || exception_flag);

    // ============================================================
    // First-level unpack: bus → packets
    // ============================================================
    `ifdef Z_BITMAIN_ENABLE
        logic [`BITMAN_PACKET_WIDTH-1:0] bitman_packet;
    `endif
    logic [`ALU_PACKET_WIDTH-1:0]   alu_packet;
    logic [`MUL_PACKET_WIDTH-1:0]   mul_packet;
    logic [`MEM_PACKET_WIDTH-1:0]   mem_packet;
    logic [`CSR_PACKET_WIDTH-1:0]   csr_packet;
    logic [`BR_JMP_PACKET_WIDTH-1:0] br_jmp_packet;
    logic [`CTRL_PACKET_WIDTH-1:0]  ctrl_packet;
    logic [`SRC_PACKET_WIDTH-1:0]   src_packet;
    `ifdef Z_BITMAIN_ENABLE
        assign {bitman_packet, alu_packet, mul_packet, mem_packet,
                csr_packet, br_jmp_packet, ctrl_packet, src_packet} = ds_to_es_bus_r;
    `else
        assign {alu_packet, mul_packet, mem_packet,
                csr_packet, br_jmp_packet, ctrl_packet, src_packet} = ds_to_es_bus_r;
    `endif

    // ============================================================
    // Second-level unpack: packets → fields
    // ============================================================
    // BITMAN
    `ifdef Z_BITMAIN_ENABLE
        logic [`BITMAN_OP_WIDTH-1:0] bitman_op;
        assign bitman_op = bitman_packet;
    `endif
    // ALU
    logic [9:0] alu_op;
    assign alu_op = alu_packet[9:0];
    // MUL
    logic [3:0] mul_op;
    logic src1_signed, src2_signed;
    assign {mul_op, src1_signed, src2_signed} = mul_packet;
    // MEM
    logic [31:0] mem_imm;
    logic [4:0] mem_op;
    logic is_store;
    assign {mem_imm, mem_op, is_store} = mem_packet;
    // CSR
    logic [31:0] csr_rdata;
    logic [31:0] csr_imm;
    logic [11:0] csr_waddr;
    logic [2:0] csr_op;
    logic csr_wen;
    logic csr_imm_sel;
    logic csr_rdata_fwd;
    assign {csr_rdata, csr_imm, csr_waddr, csr_op,
            csr_imm_sel, csr_rdata_fwd, csr_wen} = csr_packet;
    // BR_JMP
    logic [31:0] br_jmp_imm;
    logic [31:0] br_jmp_target;
    logic [5:0] br_jmp_opcode;
    logic is_jal, is_jalr;
    logic bp_pred_hit;
    logic bp_pred_taken;
    logic [31:0] bp_pred_target;
    assign {bp_pred_hit, bp_pred_taken, bp_pred_target,
            br_jmp_target, br_jmp_imm, br_jmp_opcode,
            is_jal, is_jalr} = br_jmp_packet;
    // CTRL
    logic is_alu, is_mul, is_mem, is_csr, is_br_jmp, is_bitman;
    logic [4:0] rd_addr;
    logic regfile_wen;
    logic is_multicycle;
    logic [1:0] exe_result_sel;
    logic [31:0] exe_pc;
    `ifdef Z_BITMAIN_ENABLE
    assign {exe_pc, exe_result_sel, is_bitman, is_alu, is_mul, is_mem,
            is_csr, is_br_jmp, rd_addr, regfile_wen, is_multicycle} = ctrl_packet;
    `else
    assign {exe_pc, exe_result_sel, is_alu, is_mul, is_mem,
            is_csr, is_br_jmp, rd_addr, regfile_wen, is_multicycle} = ctrl_packet;
    `endif
    // SRC
    logic [31:0] reg_src1;
    logic [31:0] reg_src2;
    logic [1:0] src1_fwd;
    logic [1:0] src2_fwd;
    assign {reg_src1, reg_src2, src1_fwd, src2_fwd} = src_packet;

    // ============================================================
    // Operand selection (forwarding unit)
    // ============================================================
    logic [31:0] src1, src2;
    logic [31:0] csr_data;

    forwarding_unit u_forwarding_unit (
        .reg_src1(reg_src1),
        .reg_src2(reg_src2),
        .exe_result_reg(exe_result_reg),
        .mem_result_reg(mem_result_reg),
        .src1_fwd(src1_fwd),
        .src2_fwd(src2_fwd),
        .src1(src1),
        .src2(src2)
    );

    assign csr_data = csr_rdata_fwd ? csr_wdata_reg : csr_rdata;

    // ============================================================
    // BITMAN execution (combinational)
    // ============================================================
    `ifdef Z_BITMAIN_ENABLE
        logic [31:0] bitman_result;
        logic bm_sh1add, bm_sh2add, bm_sh3add;
        logic bm_andn, bm_orn, bm_xnor;
        logic bm_min, bm_max, bm_minu, bm_maxu;
        logic bm_sextb, bm_sexth, bm_zexth;
        logic bm_orcb, bm_rev8, bm_brev8, bm_pack, bm_packh, bm_zip, bm_unzip;
        logic bm_bclr, bm_bclri, bm_bext, bm_bexti, bm_binv, bm_binvi, bm_bset, bm_bseti;
        logic [4:0] bit_idx;
        logic [31:0] bit_mask;

        assign {
            bm_sh1add, bm_sh2add, bm_sh3add,
            bm_andn, bm_orn, bm_xnor,
            bm_min, bm_max, bm_minu, bm_maxu,
            bm_sextb, bm_sexth, bm_zexth,
            bm_orcb, bm_rev8, bm_brev8,
            bm_pack, bm_packh, bm_zip, bm_unzip,
            bm_bclr, bm_bclri, bm_bext, bm_bexti,
            bm_binv, bm_binvi, bm_bset, bm_bseti
        } = bitman_op;
        assign bit_idx = src2[4:0];
        assign bit_mask = 32'b1 << bit_idx;

        function automatic [7:0] reverse8(input logic [7:0] data);
            reverse8 = {data[0], data[1], data[2], data[3], data[4], data[5], data[6], data[7]};
        endfunction

        function automatic [31:0] zip32(input logic [31:0] data);
            for (int i = 0; i < 16; i++) begin
                zip32[2*i] = data[i];
                zip32[2*i+1] = data[i+16];
            end
        endfunction

        function automatic [31:0] unzip32(input logic [31:0] data);
            for (int i = 0; i < 16; i++) begin
                unzip32[i] = data[2*i];
                unzip32[i+16] = data[2*i+1];
            end
        endfunction

        always_comb begin
            unique case (1'b1)
                bm_sh1add: bitman_result = (src1 << 1) + src2;
                bm_sh2add: bitman_result = (src1 << 2) + src2;
                bm_sh3add: bitman_result = (src1 << 3) + src2;
                bm_andn: bitman_result = src1 & ~src2;
                bm_orn: bitman_result = src1 | ~src2;
                bm_xnor: bitman_result = ~(src1 ^ src2);
                bm_min: bitman_result = ($signed(src1) < $signed(src2)) ? src1 : src2;
                bm_max: bitman_result = ($signed(src1) < $signed(src2)) ? src2 : src1;
                bm_minu: bitman_result = (src1 < src2) ? src1 : src2;
                bm_maxu: bitman_result = (src1 < src2) ? src2 : src1;
                bm_sextb: bitman_result = {{24{src1[7]}}, src1[7:0]};
                bm_sexth: bitman_result = {{16{src1[15]}}, src1[15:0]};
                bm_zexth: bitman_result = {16'b0, src1[15:0]};
                bm_orcb: bitman_result = {
                    {8{|src1[31:24]}}, {8{|src1[23:16]}},
                    {8{|src1[15:8]}},   {8{|src1[7:0]}}
                };
                bm_rev8: bitman_result = {src1[7:0], src1[15:8], src1[23:16], src1[31:24]};
                bm_brev8: bitman_result = {
                    reverse8(src1[31:24]), reverse8(src1[23:16]),
                    reverse8(src1[15:8]),  reverse8(src1[7:0])
                };
                bm_pack:  bitman_result = {src2[15:0], src1[15:0]};
                bm_packh: bitman_result = {16'b0, src2[7:0], src1[7:0]};
                bm_zip:   bitman_result = zip32(src1);
                bm_unzip: bitman_result = unzip32(src1);
                bm_bclr, bm_bclri: bitman_result = src1 & ~bit_mask;
                bm_bext, bm_bexti: bitman_result = {31'b0, src1[bit_idx]};
                bm_binv, bm_binvi: bitman_result = src1 ^ bit_mask;
                bm_bset, bm_bseti: bitman_result = src1 | bit_mask;
                default: bitman_result = 32'b0;
            endcase
        end
    `else
        logic [31:0] bitman_result;
        assign bitman_result = 32'b0;
    `endif

    // ============================================================
    // ALU execution (alu_wrapper)
    // ============================================================
    logic [31:0] alu_result;
    alu_wrapper u_alu_wrapper (
        .alu_op(alu_op),
        .src1(src1),
        .src2(src2),
        .alu_result(alu_result)
    );

    // ============================================================
    // Multiplier
    // ============================================================
    logic [31:0] mul_result;
    mul u_mul (
        .clk(clk),
        .rst_n(rst_n),
        .is_mul(is_mul),
        .is_multicycle(is_multicycle),
        .mul_src1(src1),
        .mul_src2(src2),
        .src1_signed(src1_signed),
        .src2_signed(src2_signed),
        .mul_op(mul_op),
        .mul_result(mul_result),
        .mul_stall(mul_stall)
    );

    // ============================================================
    // Memory access
    // ============================================================
    logic inst_lb, inst_sb, inst_lh, inst_sh, inst_lw, inst_sw, inst_lbu, inst_lhu;
    logic [5:0] load_inst;
    assign load_inst = {(inst_lb || inst_sb), (inst_lh || inst_sh),
                        (inst_lw || inst_sw), inst_lbu, inst_lhu, is_store};
    assign inst_lb  = mem_op[4] & ~is_store;
    assign inst_lh  = mem_op[3] & ~is_store;
    assign inst_lw  = mem_op[2] & ~is_store;
    assign inst_lbu = mem_op[1] & ~is_store;
    assign inst_lhu = mem_op[0] & ~is_store;
    assign inst_sb  = mem_op[4] & is_store;
    assign inst_sh  = mem_op[3] & is_store;
    assign inst_sw  = mem_op[2] & is_store;
    assign dmem_addr = src1 + mem_imm;
    assign dmem_wdata = (inst_sb) ? {4{src2[7:0]}} :
                        (inst_sh) ? {2{src2[15:0]}} :
                        src2;

    logic [3:0] sb_wen, sh_wen;
    always_comb begin
        case (dmem_addr[1:0])
            2'b00: sb_wen = 4'b0001;
            2'b01: sb_wen = 4'b0010;
            2'b10: sb_wen = 4'b0100;
            default: sb_wen = 4'b1000;
        endcase
    end
    always_comb begin
        case (dmem_addr[1])
            1'b0: sh_wen = 4'b0011;
            default: sh_wen = 4'b1100;
        endcase
    end
    always_comb begin
        dmem_wen = 4'b0000;
        if (!es_flush) begin
            unique case (1'b1)
                inst_sb: dmem_wen = sb_wen;
                inst_sh: dmem_wen = sh_wen;
                inst_sw: dmem_wen = 4'b1111;
                default: dmem_wen = 4'b0000;
            endcase
        end
    end
    assign dmem_en = |mem_op && !es_flush;

    // ============================================================
    // CSR access
    // ============================================================
    logic inst_csrrw, inst_csrrs, inst_csrrc, inst_csrrwi, inst_csrrsi, inst_csrrci;
    assign inst_csrrw  = csr_op == 3'b100 && csr_imm_sel == 1'b0;
    assign inst_csrrs  = csr_op == 3'b010 && csr_imm_sel == 1'b0;
    assign inst_csrrc  = csr_op == 3'b001 && csr_imm_sel == 1'b0;
    assign inst_csrrwi = csr_op == 3'b100 && csr_imm_sel == 1'b1;
    assign inst_csrrsi = csr_op == 3'b010 && csr_imm_sel == 1'b1;
    assign inst_csrrci = csr_op == 3'b001 && csr_imm_sel == 1'b1;
    assign exe_csr_wen  = csr_wen;
    assign exe_csr_addr = csr_waddr;
    assign csr_wdata = inst_csrrw  ? src1 :
                       inst_csrrs  ? (csr_data | src1) :
                       inst_csrrc  ? (csr_data & ~src1) :
                       inst_csrrwi ? csr_imm :
                       inst_csrrsi ? (csr_data | csr_imm) :
                       inst_csrrci ? (csr_data & ~csr_imm) :
                       32'b0;

    // ============================================================
    // Branch controller — extracted from inline logic
    // ============================================================
    branch_controller u_branch_controller (
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
        .es_flush(es_flush),
        .es_valid(es_valid),
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
        .perf_bp_miss(perf_bp_miss)
    );

    assign perf_ex_stall = es_valid && !es_ready_go && !es_flush;

    `ifdef DUAL_ISSUE_COMMIT_ENABLE
    assign exe_fwd_result = exe_result_reg;
    `endif

    // ============================================================
    // Result selection
    // ============================================================
    always_comb begin
        exe_result = 32'b0;
        if (!es_flush) begin
            unique case (1'b1)
                is_bitman: exe_result = bitman_result;
                is_alu:    exe_result = alu_result;
                is_mem:    exe_result = dmem_addr;
                is_mul:    exe_result = mul_result;
                is_csr:    exe_result = csr_data;
                default:   exe_result = exe_pc + 4;
            endcase
        end
    end

    // ============================================================
    // Forwarding / output interfaces
    // ============================================================
    assign exe_dest_addr   = rd_addr;
    assign exe_regfile_wen = regfile_wen && !es_flush;

    assign es_to_ms_bus = {
        exe_pc,         // 32
        exe_result,     // 32
        load_inst,      // 6
        rd_addr,        // 5
        regfile_wen,    // 1
        exe_result_sel, // 2
        exe_csr_wen,    // 1
        exe_csr_addr,   // 12
        csr_wdata       // 32
    };

    // Exception bus
    logic [32:0] br_bus;
    assign br_bus = {br_taken, br_target};
    assign exe_exc_bus = {br_bus, ds_exc_bus_r};

endmodule
