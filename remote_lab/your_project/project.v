`default_nettype none
// ========================================================
// FILE TOP DE BIEN DICH SILK FPGA
// Co 3 che do: MODE_VGA MODE_UART MODE_PS2
// ========================================================

module project (
    input  wire [7:0] ui_in,    // 8 Input
    output wire [7:0] uo_out,   // 8 Output 
    input  wire [7:0] uio_in,   // 8 Inout path
    output wire [7:0] uio_out,  // 8 Inout path
    output wire [7:0] uio_oe,   // enable tri buffer for each path (1: output path, 0: input path)
    input  wire       ena,      
    input  wire       clk,      
    input  wire       rst_n     
);

    // ========================================================
    // CHE DO VGA 
    // ========================================================
`ifdef MODE_VGA
    wire hsync, vsync, video_active;
    wire [1:0] r, g, b;

    assign uio_oe       = 8'b1000_0000; // uio[7] lam ngo ra cho video_active
    assign uio_out[6:0] = 7'b0;         // phai set = 0, vi trang thai tro khang cao
    
    // vga interface
    assign uo_out = {hsync, b[0], g[0], r[0], vsync, b[1], g[1], r[1]};
    assign uio_out[7] = video_active;

    // top module cua ban
    top_module u_top (
        .clk(clk),
        .rst_n(rst_n),
        .SW(ui_in[7:2]),            // control switch
        .KEY(ui_in[1:0]),
        .hsync(hsync),         // vga interface
        .vsync(vsync),
        .r(r),
        .g(g),
        .b(b),
        .video_active(video_active)
    );

    // ========================================================
    // CHE DO UART
    // ========================================================
`elsif MODE_UART
    wire uart_tx;
    assign uio_oe = 8'b0000_0000; // khong dung inout path
    assign uo_out = {3'b0, uart_tx, 4'b0}; // TX la uo_out[4]

    // top module cua ban
    top_module u_top (
        .clk(clk),
        .rst_n(rst_n),
        .SW({ui_in[7:5], 1'b0, ui_in[3:0]}),      // control switch, khong dung switch 4
        .uart_rx(ui_in[4]),    // RX
        .uart_tx(uart_tx)      // TX
    );
    // ========================================================
    // CHE DO PS/2 
    // ========================================================
`elsif MODE_PS2
    // Mở 6 bit cao làm Output (đẩy ra HEX0,1), 2 bit thấp làm Input (đọc KEY)
    assign uio_oe = 8'b1111_1100;
    assign uo_out = 8'b0000_0000; // Không xài LED đỏ để tránh nhiễu
    
    top_module u_top (
        .clk(clk),
        .rst_n(rst_n),
        .SW({ui_in[7:6], 2'b00, ui_in[3:0]}),       // controll switch, khong dung switch 4 và switch 5
        .KEY(uio_in[1:0]),     // 2 key
        .ps2_clk(ui_in[4]),    // ps2_clk
        .ps2_dat(ui_in[5]),    // ps2_dat
        .HEX_01(uio_out)       // scancode ra HEX[0] va HEX[1]
    );
    // ========================================================
    // CHẾ ĐỘ FULL HEX (Hiển thị 4 chữ số 7 đoạn)
    // ========================================================
`elsif MODE_HEX
    // Mở 6 bit cao làm Output (HEX_01), 2 bit thấp làm Input (KEY)
    assign uio_oe = 8'b1111_1100; 
    
    top_module u_top (
        .clk(clk),
        .rst_n(rst_n),
        .SW(ui_in),            // 8 switch control
        .KEY(uio_in[1:0]),     // 2 key
        .HEX_23(uo_out),       // HEX[2] va HEX[3]
        .HEX_01(uio_out)       // HEX[1] va HEX[0]
    );
    // ========================================================
    // CHE DO MAC DINH
    // ========================================================
`else 
    // uio_out[2] --> uio_out[7] la output, uio_in[0] va uio_in[1] lay gia tri key0 va key1
    assign uio_oe = 8'b1111_1100;

    //top module cua ban
    top_module u_top (
        .clk(clk),
        .rst_n(rst_n),
        .SW(ui_in),            // 8 switch
        .KEY(uio_in[1:0]),     // 2 key
        .LEDR(uo_out),         // xuat ra 8 ledr
        .HEX_01(uio_out)       // xuat ra 2 HEX[0] va HEX[1]
    );
`endif

endmodule
