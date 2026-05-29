`include "defines.svh"
module regfiles (
    input logic clk,
    input logic rst_n,
    //写端口
    input logic regfile_wen,
    input logic [4:0] regfile_waddr,
    input logic [31:0] regfile_wdata,
    //读端口1
    input logic [4:0] regfile_raddr1,
    output logic [31:0] regfile_rdata1,
    //读端口2
    input logic [4:0] regfile_raddr2,
    output logic [31:0] regfile_rdata2
    `ifdef DUAL_ISSUE_ENABLE
    ,
    //读端口3 (lane1 rs1)
    input logic [4:0] regfile_raddr3,
    output logic [31:0] regfile_rdata3,
    //读端口4 (lane1 rs2)
    input logic [4:0] regfile_raddr4,
    output logic [31:0] regfile_rdata4
    `endif
    `ifdef DEBUG_EN
    ,
    //debug接口
    output logic [31:0] debug_data
    `endif
);

    logic [31:0] regfile [31:0];
    task clean_regfile;
        integer i;
        for (i = 0; i < 32; i++) begin
            regfile[i] = 32'b0;
        end
    endtask
    //写寄存器
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clean_regfile();
        end else if (regfile_wen && regfile_waddr != 5'b0) begin
            regfile[regfile_waddr] <= regfile_wdata;
        end
    end
    //读寄存器
    assign regfile_rdata1 = (regfile_raddr1 != 5'b0) ? regfile[regfile_raddr1] : 32'b0;
    assign regfile_rdata2 = (regfile_raddr2 != 5'b0) ? regfile[regfile_raddr2] : 32'b0;
    `ifdef DUAL_ISSUE_ENABLE
    assign regfile_rdata3 = (regfile_raddr3 != 5'b0) ? regfile[regfile_raddr3] : 32'b0;
    assign regfile_rdata4 = (regfile_raddr4 != 5'b0) ? regfile[regfile_raddr4] : 32'b0;
    `endif
    `ifdef DEBUG_EN
    assign debug_data = regfile[3];
    `endif


endmodule