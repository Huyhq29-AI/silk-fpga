`default_nettype none
`define COLOR_CYAN 3'd5
`define FPGA_DEBUG

// =========================================================================
// 1. TOP MODULE (KHỐI ĐIỀU PHỐI TỔNG)
// =========================================================================
module top_module (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] SW,           // SW[3:0] chỉnh tốc độ
    input  wire [1:0] KEY,          // KEY0: Rẽ Trái, KEY1: Rẽ Phải
    output wire       hsync,        // Xung đồng bộ ngang
    output wire       vsync,        // Xung đồng bộ dọc
    output reg  [1:0] r,            // 2-bit red
    output reg  [1:0] g,            // 2-bit green
    output reg  [1:0] b,            // 2-bit blue
    output wire       video_active  // Video active
);

    // --- TÍN HIỆU VGA ---
    wire [9:0] pixel_x, pixel_y;
    wire frame_tick = (pixel_x == 0 && pixel_y == 0);

    hvsync_generator u_hvsync (
        .clk(clk),
        .rst_n(rst_n),
        .hsync(hsync),
        .vsync(vsync),
        .display_on(video_active),
        .hpos(pixel_x),
        .vpos(pixel_y)
    );

    // --- ĐỒNG BỘ NÚT BẤM (EDGE DETECTOR) ---
    reg [1:0] key_d1, key_d2;
    always @(posedge clk) begin
        if (!rst_n) begin
            key_d1 <= 2'b11;
            key_d2 <= 2'b11;
        end else begin
            key_d1 <= KEY;
            key_d2 <= key_d1;
        end
    end
    
    wire key0_press = (key_d2[0] == 1'b1 && key_d1[0] == 1'b0); // Rẽ Trái
    wire key1_press = (key_d2[1] == 1'b1 && key_d1[1] == 1'b0); // Rẽ Phải

    // --- MÁY TRẠNG THÁI (PURE CONTROL FSM) ---
    (* fsm_encoding = "auto" *)
    reg [1:0] state;
    localparam S_IDLE = 2'd0;
    localparam S_RUN  = 2'd1;
    localparam S_OVER = 2'd2;

    wire hit;          
    wire update_tick;  

    always @(posedge clk) begin : p_fsm_state
        if (!rst_n) begin
            state <= S_IDLE;
        end else begin
            case (state)
                S_IDLE: state <= (key0_press || key1_press) ? S_RUN : S_IDLE;
                S_RUN : state <= (update_tick && hit)       ? S_OVER : S_RUN;
                S_OVER: state <= (key0_press || key1_press) ? S_IDLE : S_OVER;
                default:state <= S_IDLE;
            endcase
        end
    end

    // --- BỘ ĐẾM TỐC ĐỘ & QUẢN LÝ HƯỚNG ĐI ---
    reg [3:0] frame_counter;
    wire [3:0] speed_limit = (SW[3:0] == 0) ? 4'd4 : SW[3:0]; 
    
    assign update_tick = frame_tick && (frame_counter == 0);

    always @(posedge clk) begin : p_frame_cnt
        if (!rst_n) frame_counter <= 0;
        else if (state != S_RUN) frame_counter <= 0;
        else if (frame_tick) begin
            if (frame_counter >= speed_limit) frame_counter <= 0;
            else frame_counter <= frame_counter + 1'b1;
        end
    end

    reg [1:0] dir; // 0: Up, 1: Right, 2: Down, 3: Left
    reg turn_handled;
    
    always @(posedge clk) begin : p_dir
        if (!rst_n || state == S_IDLE) begin
            dir <= 2'd1; 
            turn_handled <= 1'b0;
        end else if (state == S_RUN) begin
            if (update_tick) begin
                turn_handled <= 1'b0;
            end else if (!turn_handled) begin
                if (key0_press) begin
                    dir <= dir - 2'd1;
                    turn_handled <= 1'b1;
                end else if (key1_press) begin
                    dir <= dir + 2'd1;
                    turn_handled <= 1'b1;
                end
            end
        end
    end

    // --- LƯU TRỮ TỌA ĐỘ RẮN & TÁO ---
    reg [5:0] snake_x [0:31];
    reg [4:0] snake_y [0:31];
    reg [4:0] length;

    wire [5:0] next_x = (dir == 1) ? snake_x[0] + 1'b1 :
                        (dir == 3) ? snake_x[0] - 1'b1 : snake_x[0];
    wire [4:0] next_y = (dir == 0) ? snake_y[0] - 1'b1 :
                        (dir == 2) ? snake_y[0] + 1'b1 : snake_y[0];

    integer i;
    always @(posedge clk) begin : p_snake_body
        if (!rst_n) begin
            for (i=0; i<32; i=i+1) begin
                snake_x[i] <= 0;
                snake_y[i] <= 0;
            end
        end else if (state == S_IDLE) begin
            snake_x[0] <= 10; snake_y[0] <= 15;
            snake_x[1] <= 9;  snake_y[1] <= 15;
            snake_x[2] <= 8;  snake_y[2] <= 15;
        end else if (state == S_RUN && update_tick && !hit) begin
            for (i=31; i>0; i=i-1) begin
                snake_x[i] <= snake_x[i-1];
                snake_y[i] <= snake_y[i-1];
            end
            snake_x[0] <= next_x; 
            snake_y[0] <= next_y;
        end
    end

    reg [15:0] lfsr;
    reg [5:0] apple_x;
    reg [4:0] apple_y;

    always @(posedge clk) begin : p_lfsr
        if (!rst_n) lfsr <= 16'hACE1;
        else lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
    end

    wire eat = (next_x == apple_x && next_y == apple_y);

    always @(posedge clk) begin : p_apple_len
        if (!rst_n || state == S_IDLE) begin
            length  <= 5'd3;
            apple_x <= 6'd25;
            apple_y <= 5'd15;
        end else if (state == S_RUN && update_tick && !hit && eat) begin
            if (length < 5'd31) length <= length + 1'b1;
            apple_x <= (lfsr[5:0] < 40)  ? lfsr[5:0]  : (lfsr[5:0] - 6'd24);
            apple_y <= (lfsr[10:6] < 30) ? lfsr[10:6] : (lfsr[10:6] - 5'd2);
        end
    end

    // --- ÉP PHẲNG MẢNG (FLATTEN) ĐỂ TRUYỀN VÀO MODULE CON ---
    wire [191:0] flat_snake_x;
    wire [159:0] flat_snake_y;
    genvar gi;
    generate
        for (gi = 0; gi < 32; gi = gi + 1) begin : flatten_arrays
            assign flat_snake_x[gi*6 +: 6] = snake_x[gi];
            assign flat_snake_y[gi*5 +: 5] = snake_y[gi];
        end
    endgenerate

    // --- INSTANCE CÁC MODULE XỬ LÝ ĐỘC LẬP ---
    collision u_collision (
        .next_x(next_x),
        .next_y(next_y),
        .flat_snake_x(flat_snake_x),
        .flat_snake_y(flat_snake_y),
        .length(length),
        .hit(hit)
    );

    wire [1:0] r_wire, g_wire, b_wire;
    renderer u_renderer (
        .state(state),
        .video_active(video_active),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .flat_snake_x(flat_snake_x),
        .flat_snake_y(flat_snake_y),
        .length(length),
        .apple_x(apple_x),
        .apple_y(apple_y),
        .red(r_wire),
        .green(g_wire),
        .blue(b_wire)
    );

    always @(*) begin
        r = r_wire;
        g = g_wire;
        b = b_wire;
    end

endmodule

// =========================================================================
// 2. MODULE COLLISION (XỬ LÝ VA CHẠM TƯỜNG VÀ TỰ CẮN)
// =========================================================================
module collision (
    input  wire [5:0]   next_x,
    input  wire [4:0]   next_y,
    input  wire [191:0] flat_snake_x,
    input  wire [159:0] flat_snake_y,
    input  wire [4:0]   length,
    output wire         hit
);
    wire wall_hit = (next_x >= 40 || next_y >= 30);
    
    reg self_hit;
    integer k;
    reg [5:0] snk_x_k;
    reg [4:0] snk_y_k;
    
    always @(*) begin
        self_hit = 1'b0;
        for (k = 1; k < 32; k = k + 1) begin
            snk_x_k = flat_snake_x[k*6 +: 6];
            snk_y_k = flat_snake_y[k*5 +: 5];
            if (k < length && next_x == snk_x_k && next_y == snk_y_k) begin
                self_hit = 1'b1;
            end
        end
    end

    assign hit = wall_hit | self_hit;
endmodule

// =========================================================================
// 3. MODULE RENDERER (VẼ PIXEL LÊN MÀN HÌNH VGA)
// =========================================================================
module renderer (
    input  wire [1:0]   state,
    input  wire         video_active,
    input  wire [9:0]   pixel_x,
    input  wire [9:0]   pixel_y,
    input  wire [191:0] flat_snake_x,
    input  wire [159:0] flat_snake_y,
    input  wire [4:0]   length,
    input  wire [5:0]   apple_x,
    input  wire [4:0]   apple_y,
    output reg  [1:0]   red,
    output reg  [1:0]   green,
    output reg  [1:0]   blue
);
    localparam S_OVER = 2'd2;
    
    wire [5:0] blk_x = pixel_x[9:4]; 
    wire [4:0] blk_y = pixel_y[9:4]; 
    
    reg is_snake;
    reg is_head;
    integer j;
    reg [5:0] snk_x_j;
    reg [4:0] snk_y_j;
    
    always @(*) begin
        is_snake = 1'b0;
        is_head = 1'b0;
        for (j = 0; j < 32; j = j + 1) begin
            snk_x_j = flat_snake_x[j*6 +: 6];
            snk_y_j = flat_snake_y[j*5 +: 5];
            
            if (j == 0 && blk_x == snk_x_j && blk_y == snk_y_j) begin
                is_head = 1'b1;
            end else if (j < length && blk_x == snk_x_j && blk_y == snk_y_j) begin
                is_snake = 1'b1;
            end
        end
    end

    wire is_apple = (blk_x == apple_x && blk_y == apple_y);
    wire checker  = blk_x[0] ^ blk_y[0]; 

    always @(*) begin
        if (!video_active) begin
            red = 2'b00; green = 2'b00; blue = 2'b00;
        end else begin
            if (state == S_OVER && checker) begin
                red = 2'b11; green = 2'b00; blue = 2'b00; // Đỏ màn hình Game Over
            end else if (is_head) begin
                red = 2'b00; green = 2'b11; blue = 2'b11; // Đầu rắn
            end else if (is_snake) begin
                red = 2'b00; green = 2'b11; blue = 2'b00; // Thân rắn
            end else if (is_apple) begin
                red = 2'b11; green = 2'b00; blue = 2'b00; // Quả táo
            end else begin
                if (checker) begin
                    red = 2'b01; green = 2'b01; blue = 2'b01; // Cỏ sáng
                end else begin
                    red = 2'b00; green = 2'b00; blue = 2'b00; // Cỏ tối
                end
            end
        end
    end
endmodule

// =========================================================================
// 4. MODULE HVSYNC GENERATOR (BỘ PHÁT XUNG VGA TỔNG)
// =========================================================================
module hvsync_generator (
    input  wire clk,
    input  wire rst_n,
    output wire hsync,
    output wire vsync,
    output wire display_on,
    output wire [9:0] hpos,
    output wire [9:0] vpos
);
    localparam H_DISPLAY     = 640;
    localparam H_FRONT_PORCH = 16;
    localparam H_SYNC_PULSE  = 96;
    localparam H_BACK_PORCH  = 48;
    localparam H_MAX         = H_DISPLAY + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH - 1;

    localparam V_DISPLAY     = 480;
    localparam V_FRONT_PORCH = 10;
    localparam V_SYNC_PULSE  = 2;
    localparam V_BACK_PORCH  = 33;
    localparam V_MAX         = V_DISPLAY + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH - 1;

    reg [9:0] h_count;
    reg [9:0] v_count;

    always @(posedge clk) begin
        if (!rst_n) begin
            h_count <= 0;
            v_count <= 0;
        end else begin
            if (h_count == H_MAX) begin
                h_count <= 0;
                if (v_count == V_MAX) v_count <= 0;
                else v_count <= v_count + 1'b1;
            end else begin
                h_count <= h_count + 1'b1;
            end
        end
    end

    assign hsync = ~(h_count >= (H_DISPLAY + H_FRONT_PORCH) && h_count < (H_DISPLAY + H_FRONT_PORCH + H_SYNC_PULSE));
    assign vsync = ~(v_count >= (V_DISPLAY + V_FRONT_PORCH) && v_count < (V_DISPLAY + V_FRONT_PORCH + V_SYNC_PULSE));
    assign display_on = (h_count < H_DISPLAY) && (v_count < V_DISPLAY);
    
    assign hpos = h_count;
    assign vpos = v_count;
endmodule
