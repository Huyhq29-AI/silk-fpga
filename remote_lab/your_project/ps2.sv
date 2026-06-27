`default_nettype none

module top_module (
    input  wire       clk,       // System Clock (25MHz)
    input  wire       rst_n,     // Nút Reset
    input  wire [7:0] SW,        // Không dùng switch 4 và 5 
    input  wire [1:0] KEY,       // 2 Nút nhấn
    input  wire       ps2_clk,   // PS/2 Clock (Bất đồng bộ)
    input  wire       ps2_dat,   // PS/2 Data
    output wire [7:0] HEX_01     // Nối ra 2 LED 7 đoạn
);

    
    // ==========================================
    // 1. ĐỒNG BỘ HÓA VÀ LỌC NHIỄU PS2_CLK
    // ==========================================
    // Dùng thanh ghi dịch 3-bit để đồng bộ tín hiệu từ miền ngoài vào miền Clock hệ thống
    reg [2:0] ps2c_filter;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ps2c_filter <= 3'b111; // Mặc định PS2 CLK mức cao
        else        ps2c_filter <= {ps2c_filter[1:0], ps2_clk};
    end

    // Bắt sườn xuống: Trạng thái trước là 1, trạng thái hiện tại là 0
    wire fall_edge = (ps2c_filter[2:1] == 2'b10);

    // ==========================================
    // 2. BỘ THU PS/2 (FRAME 11 BIT)
    // ==========================================
    // Cấu trúc 1 khung truyền: 1 Start (0) + 8 Data (LSB first) + 1 Parity + 1 Stop (1)
    reg [3:0]  bit_cnt;
    reg [10:0] shift_reg;
    reg [7:0]  scan_code;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt   <= 4'd0;
            shift_reg <= 11'd0;
            scan_code <= 8'h00;
        end 
        else if (fall_edge) begin
            // Dịch phải vì PS/2 truyền LSB (bit thấp) trước
            shift_reg <= {ps2_dat, shift_reg[10:1]};
            
            if (bit_cnt == 4'd10) begin
                // Đủ 11 bit (từ 0 đến 10), bóc tách 8 bit data nằm ở giữa
                scan_code <= shift_reg[9:2]; 
                bit_cnt   <= 4'd0;
            end else begin
                bit_cnt   <= bit_cnt + 1'b1;
            end
        end
    end

    // ==========================================
    // 3. HIỂN THỊ KẾT QUẢ RA HEX
    // ==========================================
    // Xuất thẳng mã Quét (Scan Code) ra 2 con LED 7 đoạn (Nó sẽ hiển thị dưới dạng nhị phân thô trên 8 bóng LED của 2 con HEX, 
    // hoặc nếu Web của bro có giải mã HEX sẵn thì nó sẽ hiện ra số Hexa (ví dụ nhấn 'A' hiện '1C').
    assign HEX_01 = scan_code;

endmodule
