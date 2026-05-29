`include "defines.svh"

// Instruction queue between IF (dual push) and ID (single pop).
// Depth 4, circular buffer. Flush clears all entries on redirect/exception.
module instr_queue #(
    parameter int DEPTH = 4
) (
    input logic clk,
    input logic rst_n,

    // ---- Push side (from IF stage) ----
    input  logic push_valid0,
    input  logic push_valid1,
    input  logic [31:0] push_inst0, push_inst1,
    input  logic [31:0] push_pc0, push_pc1,
    input  logic push_bp_hit0, push_bp_hit1,
    input  logic push_bp_taken0, push_bp_taken1,
    input  logic [31:0] push_bp_target0, push_bp_target1,
    input  logic [`EXC_WIDTH-1:0] push_exc0, push_exc1,

    output logic [1:0] push_free,   // free slots available for push

    // ---- Pop side (to ID stage) ----
    input  logic pop_ready,          // ds_allowin from ID
    output logic pop_valid,
    output logic [`FS_DS_WIDTH-1:0] pop_bus,    // {inst, pc, bp_hit, bp_taken, bp_target}
    output logic [`EXC_WIDTH-1:0] pop_exc,

    // ---- Control ----
    input logic flush
);

    typedef struct packed {
        logic valid;
        logic [31:0] inst;
        logic [31:0] pc;
        logic bp_hit;
        logic bp_pred_taken;
        logic [31:0] bp_pred_target;
        logic [`EXC_WIDTH-1:0] exc;
    } entry_t;

    entry_t [DEPTH-1:0] entries;
    logic [$clog2(DEPTH)-1:0] head, tail;
    logic [2:0] count;

    // ---- Count and free slots ----
    assign push_free = (count < DEPTH) ? ((count < DEPTH-1) ? 2'd2 : 2'd1) : 2'd0;

    // ---- Pop interface ----
    assign pop_valid = entries[head].valid;
    assign pop_bus = {
        entries[head].inst,
        entries[head].pc,
        entries[head].bp_hit,
        entries[head].bp_pred_taken,
        entries[head].bp_pred_target
    };
    assign pop_exc = entries[head].exc;

    function automatic [$clog2(DEPTH)-1:0] next_ptr(input [$clog2(DEPTH)-1:0] p);
        return (p == DEPTH-1) ? '0 : p + 1'b1;
    endfunction

    // Combinational next-state to handle pop + dual push correctly
    logic do_pop, do_push0, do_push1;
    logic [2:0] cnt_after_pop, cnt_after_push0, count_next;
    logic [$clog2(DEPTH)-1:0] head_next, tail_next;

    assign do_pop  = pop_valid && pop_ready;
    assign cnt_after_pop = count - {2'b0, do_pop};

    assign do_push0 = push_valid0 && (cnt_after_pop < DEPTH);
    assign cnt_after_push0 = cnt_after_pop + {2'b0, do_push0};

    assign do_push1 = push_valid1 && (cnt_after_push0 < DEPTH);
    assign count_next = cnt_after_push0 + {2'b0, do_push1};

    assign head_next = do_pop ? next_ptr(head) : head;
    assign tail_next = do_push1 ? next_ptr(do_push0 ? next_ptr(tail) : tail) :
                       do_push0 ? next_ptr(tail) : tail;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < DEPTH; i++)
                entries[i] <= '0;
            head  <= '0;
            tail  <= '0;
            count <= '0;
        end else if (flush) begin
            for (int i = 0; i < DEPTH; i++)
                entries[i].valid <= 1'b0;
            head  <= '0;
            tail  <= '0;
            count <= '0;
        end else begin
            if (do_pop)
                entries[head].valid <= 1'b0;
            if (do_push0) begin
                entries[tail].valid        <= 1'b1;
                entries[tail].inst         <= push_inst0;
                entries[tail].pc           <= push_pc0;
                entries[tail].bp_hit       <= push_bp_hit0;
                entries[tail].bp_pred_taken<= push_bp_taken0;
                entries[tail].bp_pred_target    <= push_bp_target0;
                entries[tail].exc          <= push_exc0;
            end
            if (do_push1) begin
                // slot1 writes to the position after slot0
                automatic logic [$clog2(DEPTH)-1:0] tail1 = do_push0 ? next_ptr(tail) : tail;
                entries[tail1].valid        <= 1'b1;
                entries[tail1].inst         <= push_inst1;
                entries[tail1].pc           <= push_pc1;
                entries[tail1].bp_hit       <= push_bp_hit1;
                entries[tail1].bp_pred_taken<= push_bp_taken1;
                entries[tail1].bp_pred_target    <= push_bp_target1;
                entries[tail1].exc          <= push_exc1;
            end
            head  <= head_next;
            tail  <= tail_next;
            count <= count_next;
        end
    end

`ifdef DEBUG_EN
    // Debug: expose queue state
    logic [31:0] dbg_entry_pc [DEPTH-1:0];
    logic [DEPTH-1:0] dbg_entry_valid;
    for (genvar i = 0; i < DEPTH; i++) begin
        assign dbg_entry_pc[i]   = entries[i].pc;
        assign dbg_entry_valid[i] = entries[i].valid;
    end
`endif

endmodule : instr_queue
