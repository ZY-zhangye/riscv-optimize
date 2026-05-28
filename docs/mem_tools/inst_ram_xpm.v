`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/02 16:12:02
// Design Name: 
// Module Name: inst_ram_xpm
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module inst_ram_xpm #(
    parameter MEM_FILE = "program.mem"
)(
    input  wire         clk,
    input  wire         en,
    input  wire [31:0]  addr,
    output wire [31:0]  inst
);

    wire [11:0] word_addr;

    // CPU 是字节地址，BRAM 是 32-bit word 地址
    assign word_addr = addr[13:2];

    xpm_memory_sprom #(
        .ADDR_WIDTH_A        (12),
        .MEMORY_SIZE         (32 * 4096),
        .MEMORY_PRIMITIVE    ("block"),
        .READ_DATA_WIDTH_A   (32),
        .MEMORY_INIT_FILE    (MEM_FILE),
        .MEMORY_INIT_PARAM   (""),
        .READ_LATENCY_A      (1),
        .READ_RESET_VALUE_A  ("0"),
        .USE_MEM_INIT        (1),
        .WAKEUP_TIME         ("disable_sleep"),
        .MEMORY_OPTIMIZATION ("false"),
        .MESSAGE_CONTROL     (0),
        .ECC_MODE            ("no_ecc"),
        .AUTO_SLEEP_TIME     (0),
        .CASCADE_HEIGHT      (0)
    ) u_xpm_inst_rom (
        .clka           (clk),
        .ena            (en),
        .addra          (word_addr),
        .douta          (inst),
        .rsta           (1'b0),
        .regcea         (1'b1),
        .sleep          (1'b0),
        .injectsbiterra (1'b0),
        .injectdbiterra (1'b0),
        .sbiterra       (),
        .dbiterra       ()
    );

endmodule