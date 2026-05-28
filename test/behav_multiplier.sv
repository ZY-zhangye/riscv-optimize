// Behavioral multiplier — replaces Xilinx Multiplier IP for simulation
module multiplier (
    input  logic        CLK,
    input  logic signed [32:0] A,
    input  logic signed [32:0] B,
    input  logic        CE,
    output logic signed [65:0] P
);
    always_ff @(posedge CLK) begin
        if (CE) begin
            P <= A * B;
        end
    end
endmodule
