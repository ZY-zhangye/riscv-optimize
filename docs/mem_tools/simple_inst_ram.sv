module simple_inst_ram (
    input  logic clk,
    input  logic [31:0] addr,
    input  logic en,
    output logic [31:0] rdata
);
    logic [31:0] mem [0:1023];

    always_ff @(posedge clk) begin
        if (en) begin
            rdata <= mem[addr[11:2]];
        end
    end
endmodule
