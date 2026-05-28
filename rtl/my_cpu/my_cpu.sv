`include "defines.svh"
`include "my_cpu_defines.svh"

module my_cpu #(
    parameter string INST_MEM_FILE = "none",
    parameter string DATA_MEM_FILE = "none",
    parameter string DATA_MEM_FILE_0 = "none",
    parameter string DATA_MEM_FILE_1 = "none",
    parameter string DATA_MEM_FILE_2 = "none",
    parameter string DATA_MEM_FILE_3 = "none"
) (
    input  logic        i_sys_clk_p,
    input  logic        i_sys_clk_n,
    input  logic        uart_rx,
    output logic        uart_tx,
    output logic [31:0] led
    `ifdef DEBUG_EN
    ,
    output logic [31:0] debug_inst_pc,
    output logic [31:0] debug_wb_pc,
    output logic [4:0]  debug_wb_rf_addr,
    output logic [31:0] debug_wb_rf_data,
    output logic        debug_wb_rf_wen,
    output logic [31:0] debug_data
    `endif
);

    logic clk;
    logic clk_uart;
    logic pll_locked;
    logic soc_rst_n;
    logic plic_irq;
    logic [5:0] por_cnt;

    PLL u_pll (
        .clk_out1(clk),
        .locked(pll_locked),
        .clk_in1_p(i_sys_clk_p),
        .clk_in1_n(i_sys_clk_n)
    );

    // The board top does not expose a separate UART tick clock; use the
    // UART's internal baud generator and keep the external tick input quiet.
    assign clk_uart = 1'b0;

    always_ff @(posedge clk) begin
        if (!pll_locked) begin
            por_cnt <= 6'd0;
        end else if (por_cnt != 6'd50) begin
            por_cnt <= por_cnt + 6'd1;
        end
    end

    assign soc_rst_n = pll_locked && (por_cnt == 6'd50);

    logic [31:0] imem_rdata;
    logic [31:0] imem_addr;
    logic        imem_en;

    logic [31:0] cpu_dmem_rdata;
    logic [31:0] cpu_dmem_addr;
    logic [3:0]  cpu_dmem_wen;
    logic        cpu_dmem_en;
    logic [31:0] cpu_dmem_wdata;

    logic        ram_en;
    logic [31:0] ram_addr;
    logic [3:0]  ram_wen;
    logic [31:0] ram_wdata;
    logic [31:0] ram_rdata;

    logic        io_sel;
    logic        io_re;
    logic [3:0]  io_wen;
    logic [31:0] io_addr;
    logic [31:0] io_wdata;
    logic [31:0] io_rdata;

    logic        plic_sel;
    logic        plic_re;
    logic        plic_we;
    logic [31:0] plic_addr;
    logic [31:0] plic_wdata;
    logic [31:0] plic_rdata;

    logic [`PLIC_NUM_INTERRUPTS-1:0] io_interrupts;
    logic [`PLIC_NUM_INTERRUPTS-1:0] plic_interrupts;

    assign plic_interrupts = io_interrupts;

    cpu_top u_cpu_top (
        .clk(clk),
        .rst_n(soc_rst_n),
        .imem_rdata(imem_rdata),
        .imem_addr(imem_addr),
        .imem_en(imem_en),
        .dmem_rdata(cpu_dmem_rdata),
        .dmem_addr(cpu_dmem_addr),
        .dmem_wen(cpu_dmem_wen),
        .dmem_en(cpu_dmem_en),
        .dmem_wdata(cpu_dmem_wdata),
        .plic_irq(plic_irq)
        `ifdef DEBUG_EN
        ,
        .debug_wb_pc(debug_wb_pc),
        .debug_wb_rf_addr(debug_wb_rf_addr),
        .debug_wb_rf_data(debug_wb_rf_data),
        .debug_wb_rf_wen(debug_wb_rf_wen),
        .debug_data(debug_data)
        `endif
    );

    `ifdef DEBUG_EN
    assign debug_inst_pc = imem_addr;
    `endif

    soc_inst_ram #(
        .MEM_FILE(INST_MEM_FILE)
    ) u_inst_ram (
        .clk(clk),
        .addr(imem_addr),
        .en(imem_en),
        .rdata(imem_rdata)
    );

    soc_data_ram #(
        .MEM_FILE(DATA_MEM_FILE),
        .MEM_FILE_0(DATA_MEM_FILE_0),
        .MEM_FILE_1(DATA_MEM_FILE_1),
        .MEM_FILE_2(DATA_MEM_FILE_2),
        .MEM_FILE_3(DATA_MEM_FILE_3)
    ) u_data_ram (
        .clk(clk),
        .addr(ram_addr),
        .en(ram_en),
        .wen(ram_wen),
        .wdata(ram_wdata),
        .rdata(ram_rdata)
    );

    bridge u_bridge (
        .clk(clk),
        .rst_n(soc_rst_n),
        .cpu_dmem_en(cpu_dmem_en),
        .cpu_dmem_addr(cpu_dmem_addr),
        .cpu_dmem_wen(cpu_dmem_wen),
        .cpu_dmem_wdata(cpu_dmem_wdata),
        .cpu_dmem_rdata(cpu_dmem_rdata),
        .ram_en(ram_en),
        .ram_addr(ram_addr),
        .ram_wen(ram_wen),
        .ram_wdata(ram_wdata),
        .ram_rdata(ram_rdata),
        .io_sel(io_sel),
        .io_re(io_re),
        .io_wen(io_wen),
        .io_addr(io_addr),
        .io_wdata(io_wdata),
        .io_rdata(io_rdata),
        .plic_sel(plic_sel),
        .plic_re(plic_re),
        .plic_we(plic_we),
        .plic_addr(plic_addr),
        .plic_wdata(plic_wdata),
        .plic_rdata(plic_rdata)
    );

    IO u_io (
        .clk(clk),
        .rst_n(soc_rst_n),
        .clk_uart(clk_uart),
        .io_sel(io_sel),
        .io_re(io_re),
        .io_wen(io_wen),
        .io_addr(io_addr),
        .io_wdata(io_wdata),
        .io_rdata(io_rdata),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .led(led),
        .peripheral_interrupts(io_interrupts)
    );

    PLIC u_plic (
        .clk(clk),
        .rst_n(soc_rst_n),
        .peripheral_interrupts(plic_interrupts),
        .plic_irq(plic_irq),
        .plic_sel(plic_sel),
        .plic_we(plic_we),
        .plic_re(plic_re),
        .plic_addr(plic_addr),
        .plic_wdata(plic_wdata),
        .plic_rdata(plic_rdata)
    );

endmodule

module soc_inst_ram #(
    parameter int WORDS = 4096,
    parameter string MEM_FILE = "none"
) (
    input  logic        clk,
    input  logic [31:0] addr,
    input  logic        en,
    output logic [31:0] rdata
);
`ifdef DEBUG_EN
    localparam int INDEX_WIDTH = $clog2(WORDS);
    logic [31:0] mem [0:WORDS-1];

    always_ff @(posedge clk) begin
        if (en) begin
            rdata <= mem[addr[INDEX_WIDTH+1:2]];
        end
    end
`else
    localparam int INDEX_WIDTH = $clog2(WORDS);

    xpm_memory_sprom #(
        .ADDR_WIDTH_A        (INDEX_WIDTH),
        .MEMORY_SIZE         (32 * WORDS),
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
        .addra          (addr[INDEX_WIDTH+1:2]),
        .douta          (rdata),
        .rsta           (1'b0),
        .regcea         (1'b1),
        .sleep          (1'b0),
        .injectsbiterra (1'b0),
        .injectdbiterra (1'b0),
        .sbiterra       (),
        .dbiterra       ()
    );
`endif
endmodule

module soc_data_ram #(
    parameter int WORDS = 65536,
    parameter string MEM_FILE = "none",
    parameter string MEM_FILE_0 = "none",
    parameter string MEM_FILE_1 = "none",
    parameter string MEM_FILE_2 = "none",
    parameter string MEM_FILE_3 = "none"
) (
    input  logic        clk,
    input  logic [31:0] addr,
    input  logic        en,
    input  logic [3:0]  wen,
    input  logic [31:0] wdata,
    output logic [31:0] rdata
);
`ifdef DEBUG_EN
    localparam int INDEX_WIDTH = $clog2(WORDS);
    logic [31:0] mem [0:WORDS-1];

    assign rdata = en ? mem[addr[INDEX_WIDTH+1:2]] : 32'd0;

    always_ff @(posedge clk) begin
        if (en) begin
            if (wen[0]) begin
                mem[addr[INDEX_WIDTH+1:2]][7:0] <= wdata[7:0];
            end
            if (wen[1]) begin
                mem[addr[INDEX_WIDTH+1:2]][15:8] <= wdata[15:8];
            end
            if (wen[2]) begin
                mem[addr[INDEX_WIDTH+1:2]][23:16] <= wdata[23:16];
            end
            if (wen[3]) begin
                mem[addr[INDEX_WIDTH+1:2]][31:24] <= wdata[31:24];
            end
        end
    end
`else
    localparam int INDEX_WIDTH = $clog2(WORDS);
    localparam int CHUNK_WORDS = 4096;
    localparam int CHUNK_INDEX_WIDTH = $clog2(CHUNK_WORDS);

    logic [3:0]  chunk_sel;
    logic [15:0] chunk_en;
    logic [15:0] read_chunk_onehot_q;
    logic [31:0] chunk_rdata [0:15];
    logic [31:0] selected_chunk_rdata;

    assign chunk_sel = addr[INDEX_WIDTH+1:CHUNK_INDEX_WIDTH+2];
    assign rdata = selected_chunk_rdata;

    always_comb begin
        chunk_en = 16'd0;
        if (en) begin
            chunk_en[chunk_sel] = 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (en) begin
            read_chunk_onehot_q <= chunk_en;
        end
    end

    always_comb begin
        selected_chunk_rdata = 32'd0;
        for (int i = 0; i < 16; i++) begin
            selected_chunk_rdata |= ({32{read_chunk_onehot_q[i]}} & chunk_rdata[i]);
        end
    end

    soc_data_ram_word_chunk u_data_chunk0  (.clk(clk), .addr(addr[CHUNK_INDEX_WIDTH+1:2]), .en(chunk_en[0]),  .wen(wen), .wdata(wdata), .rdata(chunk_rdata[0]));
    soc_data_ram_word_chunk u_data_chunk1  (.clk(clk), .addr(addr[CHUNK_INDEX_WIDTH+1:2]), .en(chunk_en[1]),  .wen(wen), .wdata(wdata), .rdata(chunk_rdata[1]));
    soc_data_ram_word_chunk u_data_chunk2  (.clk(clk), .addr(addr[CHUNK_INDEX_WIDTH+1:2]), .en(chunk_en[2]),  .wen(wen), .wdata(wdata), .rdata(chunk_rdata[2]));
    soc_data_ram_word_chunk u_data_chunk3  (.clk(clk), .addr(addr[CHUNK_INDEX_WIDTH+1:2]), .en(chunk_en[3]),  .wen(wen), .wdata(wdata), .rdata(chunk_rdata[3]));
    soc_data_ram_word_chunk u_data_chunk4  (.clk(clk), .addr(addr[CHUNK_INDEX_WIDTH+1:2]), .en(chunk_en[4]),  .wen(wen), .wdata(wdata), .rdata(chunk_rdata[4]));
    soc_data_ram_word_chunk u_data_chunk5  (.clk(clk), .addr(addr[CHUNK_INDEX_WIDTH+1:2]), .en(chunk_en[5]),  .wen(wen), .wdata(wdata), .rdata(chunk_rdata[5]));
    soc_data_ram_word_chunk u_data_chunk6  (.clk(clk), .addr(addr[CHUNK_INDEX_WIDTH+1:2]), .en(chunk_en[6]),  .wen(wen), .wdata(wdata), .rdata(chunk_rdata[6]));
    soc_data_ram_word_chunk u_data_chunk7  (.clk(clk), .addr(addr[CHUNK_INDEX_WIDTH+1:2]), .en(chunk_en[7]),  .wen(wen), .wdata(wdata), .rdata(chunk_rdata[7]));
    soc_data_ram_word_chunk u_data_chunk8  (.clk(clk), .addr(addr[CHUNK_INDEX_WIDTH+1:2]), .en(chunk_en[8]),  .wen(wen), .wdata(wdata), .rdata(chunk_rdata[8]));
    soc_data_ram_word_chunk u_data_chunk9  (.clk(clk), .addr(addr[CHUNK_INDEX_WIDTH+1:2]), .en(chunk_en[9]),  .wen(wen), .wdata(wdata), .rdata(chunk_rdata[9]));
    soc_data_ram_word_chunk u_data_chunk10 (.clk(clk), .addr(addr[CHUNK_INDEX_WIDTH+1:2]), .en(chunk_en[10]), .wen(wen), .wdata(wdata), .rdata(chunk_rdata[10]));
    soc_data_ram_word_chunk u_data_chunk11 (.clk(clk), .addr(addr[CHUNK_INDEX_WIDTH+1:2]), .en(chunk_en[11]), .wen(wen), .wdata(wdata), .rdata(chunk_rdata[11]));
    soc_data_ram_word_chunk u_data_chunk12 (.clk(clk), .addr(addr[CHUNK_INDEX_WIDTH+1:2]), .en(chunk_en[12]), .wen(wen), .wdata(wdata), .rdata(chunk_rdata[12]));
    soc_data_ram_word_chunk u_data_chunk13 (.clk(clk), .addr(addr[CHUNK_INDEX_WIDTH+1:2]), .en(chunk_en[13]), .wen(wen), .wdata(wdata), .rdata(chunk_rdata[13]));
    soc_data_ram_word_chunk u_data_chunk14 (.clk(clk), .addr(addr[CHUNK_INDEX_WIDTH+1:2]), .en(chunk_en[14]), .wen(wen), .wdata(wdata), .rdata(chunk_rdata[14]));
    soc_data_ram_word_chunk u_data_chunk15 (.clk(clk), .addr(addr[CHUNK_INDEX_WIDTH+1:2]), .en(chunk_en[15]), .wen(wen), .wdata(wdata), .rdata(chunk_rdata[15]));
`endif
endmodule

module soc_data_ram_word_chunk #(
    parameter int WORDS = 4096,
    parameter string MEM_FILE = "none"
) (
    input  logic                     clk,
    input  logic [$clog2(WORDS)-1:0] addr,
    input  logic                     en,
    input  logic [3:0]               wen,
    input  logic [31:0]              wdata,
    output logic [31:0]              rdata
);
    localparam int INDEX_WIDTH = $clog2(WORDS);

    xpm_memory_spram #(
        .ADDR_WIDTH_A        (INDEX_WIDTH),
        .AUTO_SLEEP_TIME     (0),
        .BYTE_WRITE_WIDTH_A  (8),
        .CASCADE_HEIGHT      (0),
        .ECC_MODE            ("no_ecc"),
        .MEMORY_INIT_FILE    (MEM_FILE),
        .MEMORY_INIT_PARAM   ("0"),
        .MEMORY_OPTIMIZATION ("false"),
        .MEMORY_PRIMITIVE    ("block"),
        .MEMORY_SIZE         (32 * WORDS),
        .MESSAGE_CONTROL     (0),
        .READ_DATA_WIDTH_A   (32),
        .READ_LATENCY_A      (1),
        .READ_RESET_VALUE_A  ("0"),
        .RST_MODE_A          ("SYNC"),
        .USE_MEM_INIT        (1),
        .WAKEUP_TIME         ("disable_sleep"),
        .WRITE_DATA_WIDTH_A  (32),
        .WRITE_MODE_A        ("read_first")
    ) u_xpm_data_ram (
        .clka           (clk),
        .rsta           (1'b0),
        .ena            (en),
        .regcea         (1'b1),
        .wea            (wen),
        .addra          (addr),
        .dina           (wdata),
        .douta          (rdata),
        .sleep          (1'b0),
        .injectsbiterra (1'b0),
        .injectdbiterra (1'b0),
        .sbiterra       (),
        .dbiterra       ()
    );
endmodule
