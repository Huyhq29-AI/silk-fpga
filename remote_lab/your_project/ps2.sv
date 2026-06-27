`default_nettype none
`define COLOR_CYAN 3'd5

// =========================================================================
// 1. TOP MODULE 
// =========================================================================
module top_module (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] SW,       // SW[3:0] chỉnh tốc độ
    input  wire [1:0] KEY,      
    input  wire       ps2_clk,  
    input  wire       ps2_dat, 
    output wire       hsync,    
    output wire       vsync,    
    output reg  [1:0] r,        
    output reg  [1:0] g,        
    output reg  [1:0] b,        
    output wire       video_active  
);

  wire [9:0] pixel_x, pixel_y;
  wire       visible;
  wire       frame_tick;
  
  wire [1:0] red, green, blue;
  assign r = red;
  assign g = green;
  assign b = blue;
  assign video_active = visible;

  // --- Dây tín hiệu giao tiếp ---
  wire [1:0]   state;
  wire [191:0] flat_snake_x;
  wire [159:0] flat_snake_y;
  wire [4:0]   length;
  wire [5:0]   apple_x;
  wire [4:0]   apple_y;
  wire [5:0]   next_x;
  wire [4:0]   next_y;
  wire         hit;
  
  wire [7:0]   scan_code;
  wire         rx_done;

  // 1. Module VGA Generator
  hvsync_generator u_hvsync (
    .clk(clk),
    .rst_n(rst_n),
    .hsync(hsync),
    .vsync(vsync),
    .display_on(visible),
    .hpos(pixel_x),
    .vpos(pixel_y)
  );
  assign frame_tick = (pixel_x == 10'd0) && (pixel_y == 10'd0);

  // 2. Module PS/2 Receiver (Đã vá lỗi trích xuất Frame)
  ps2_receiver u_ps2 (
    .clk(clk),
    .rst_n(rst_n),
    .ps2_clk(ps2_clk),
    .ps2_dat(ps2_dat),
    .scan_code(scan_code),
    .rx_done(rx_done)
  );

  // 3. Module Game Controller
  game_ctrl u_game_ctrl (
    .clk(clk),
    .rst_n(rst_n),
    .frame_tick(frame_tick),
    .speed_sw(SW[3:0]),
    .hit(hit),
    .scan_code(scan_code),
    .rx_done(rx_done),
    .state(state),
    .flat_snake_x(flat_snake_x),
    .flat_snake_y(flat_snake_y),
    .length(length),
    .apple_x(apple_x),
    .apple_y(apple_y),
    .next_x(next_x),
    .next_y(next_y)
  );

  // 4. Module Collision
  collision u_collision (
    .next_x(next_x),
    .next_y(next_y),
    .flat_snake_x(flat_snake_x),
    .flat_snake_y(flat_snake_y),
    .length(length),
    .hit(hit)
  );

  // 5. Module Renderer
  renderer u_renderer (
    .state(state),
    .video_active(visible),
    .pixel_x(pixel_x),
    .pixel_y(pixel_y),
    .flat_snake_x(flat_snake_x),
    .flat_snake_y(flat_snake_y),
    .length(length),
    .apple_x(apple_x),
    .apple_y(apple_y),
    .red(red),
    .green(green),
    .blue(blue)
  );

endmodule


// =========================================================================
// 2. MODULE PS/2 RECEIVER 
// =========================================================================
module ps2_receiver (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       ps2_clk,
    input  wire       ps2_dat,
    output reg  [7:0] scan_code,
    output reg        rx_done
);
    reg [2:0] ps2c_filter;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ps2c_filter <= 3'b111;
        else        ps2c_filter <= {ps2c_filter[1:0], ps2_clk};
    end
    wire fall_edge = (ps2c_filter[2:1] == 2'b10);

    reg [3:0]  bit_cnt;
    reg [10:0] shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt   <= 4'd0;
            shift_reg <= 11'd0;
            scan_code <= 8'h00;
            rx_done   <= 1'b0;
        end else begin
            rx_done <= 1'b0; // Pulse 1 chu kỳ
            if (fall_edge) begin
                shift_reg <= {ps2_dat, shift_reg[10:1]};
                
                if (bit_cnt == 4'd10) begin
                    
                    scan_code <= shift_reg[9:2]; 
                    rx_done   <= 1'b1;
                    bit_cnt   <= 4'd0;
                end else begin
                    bit_cnt <= bit_cnt + 1'b1;
                end
            end
        end
    end
endmodule

// =========================================================================
// 3. MODULE GAME_CTRL: XỬ LÝ WASD VÀ FSM
// =========================================================================
module game_ctrl (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_tick,
    input  wire [3:0]  speed_sw,
    input  wire        hit,
    input  wire [7:0]  scan_code,
    input  wire        rx_done,
    output reg  [1:0]  state,
    output wire [191:0] flat_snake_x,
    output wire [159:0] flat_snake_y,
    output reg  [4:0]  length,
    output reg  [5:0]  apple_x,
    output reg  [4:0]  apple_y,
    output wire [5:0]  next_x,
    output wire [4:0]  next_y
);

  // --- Lọc tín hiệu nhả phím (Break Code 0xF0) ---
  reg is_break;
  reg valid_key;
  reg [7:0] key_code;

  always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
          is_break  <= 1'b0;
          valid_key <= 1'b0;
          key_code  <= 8'h00;
      end else begin
          valid_key <= 1'b0;
          if (rx_done) begin
              if (scan_code == 8'hF0) begin
                  is_break <= 1'b1; // Phát hiện đang nhả phím
              end else begin
                  if (!is_break) begin
                      valid_key <= 1'b1; // Chỉ ghi nhận khi đang ấn xuống
                      key_code  <= scan_code;
                  end
                  is_break <= 1'b0; // Reset trạng thái
              end
          end
      end
  end

  // Giải mã phím W, A, S, D
  wire press_W = valid_key && (key_code == 8'h1D);
  wire press_S = valid_key && (key_code == 8'h1B);
  wire press_A = valid_key && (key_code == 8'h1C);
  wire press_D = valid_key && (key_code == 8'h23);
  wire any_press = press_W | press_S | press_A | press_D;

  // --- Máy trạng thái & Bộ đếm tốc độ ---
  localparam S_IDLE = 2'd0;
  localparam S_RUN  = 2'd1;
  localparam S_OVER = 2'd2;

  reg [3:0] frame_counter;
  wire [3:0] speed_limit = (speed_sw == 0) ? 4'd4 : speed_sw; 
  wire update_tick = frame_tick && (frame_counter == 0);

  always @(posedge clk) begin : p_frame_cnt
      if (!rst_n) frame_counter <= 0;
      else if (state != S_RUN) frame_counter <= 0;
      else if (frame_tick) begin
          if (frame_counter >= speed_limit) frame_counter <= 0;
          else frame_counter <= frame_counter + 1'b1;
      end
  end

  (* fsm_encoding = "auto" *)
  always @(posedge clk) begin : p_fsm_state
      if (!rst_n) begin
          state <= S_IDLE;
      end else begin
          case (state)
              S_IDLE: state <= (any_press)          ? S_RUN : S_IDLE;
              S_RUN : state <= (update_tick && hit) ? S_OVER : S_RUN;
              S_OVER: state <= (any_press)          ? S_IDLE : S_OVER;
              default:state <= S_IDLE;
          endcase
      end
  end

  // --- Quản lý hướng đi bằng WASD (Tuyệt đối không cho bẻ ngược 180 độ) ---
  reg [1:0] dir; // 0: Lên, 1: Phải, 2: Xuống, 3: Trái
  reg turn_handled;
  
  always @(posedge clk) begin : p_dir
      if (!rst_n || state == S_IDLE) begin
          dir <= 2'd1; // Mặc định bò sang phải
          turn_handled <= 1'b0;
      end else if (state == S_RUN) begin
          if (update_tick) begin
              turn_handled <= 1'b0; // Reset cờ sau mỗi nhịp bò
          end else if (!turn_handled) begin
              if (press_W && dir != 2'd2) begin 
                  dir <= 2'd0; turn_handled <= 1'b1; 
              end
              else if (press_D && dir != 2'd3) begin 
                  dir <= 2'd1; turn_handled <= 1'b1; 
              end
              else if (press_S && dir != 2'd0) begin 
                  dir <= 2'd2; turn_handled <= 1'b1; 
              end
              else if (press_A && dir != 2'd1) begin 
                  dir <= 2'd3; turn_handled <= 1'b1; 
              end
          end
      end
  end

  // --- Tọa độ cơ thể rắn ---
  reg [5:0] snake_x [0:31];
  reg [4:0] snake_y [0:31];

  assign next_x = (dir == 1) ? snake_x[0] + 1'b1 : (dir == 3) ? snake_x[0] - 1'b1 : snake_x[0];
  assign next_y = (dir == 0) ? snake_y[0] - 1'b1 : (dir == 2) ? snake_y[0] + 1'b1 : snake_y[0];

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

  // --- Quản lý Táo (LFSR) ---
  reg [15:0] lfsr;
  always @(posedge clk) begin
      if (!rst_n) lfsr <= 16'hACE1;
      else lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
  end

  wire eat = (next_x == apple_x && next_y == apple_y);
  always @(posedge clk) begin
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

  // --- Ép phẳng mảng (Flattening) truyền sang module khác ---
  genvar gi;
  generate
      for (gi = 0; gi < 32; gi = gi + 1) begin : flatten_arrays
          assign flat_snake_x[gi*6 +: 6] = snake_x[gi];
          assign flat_snake_y[gi*5 +: 5] = snake_y[gi];
      end
  endgenerate

endmodule


// =========================================================================
// 4. MODULE COLLISION: XỬ LÝ VA CHẠM
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
// 5. MODULE RENDERER: XUẤT ĐỒ HỌA MÀN HÌNH
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
    wire is_checker  = blk_x[0] ^ blk_y[0]; 

    always @(*) begin
        if (!video_active) begin
            red = 2'b00; green = 2'b00; blue = 2'b00;
        end else begin
            if (state == S_OVER && is_checker) begin
                red = 2'b11; green = 2'b00; blue = 2'b00; 
            end else if (is_head) begin
                red = 2'b00; green = 2'b11; blue = 2'b11; 
            end else if (is_snake) begin
                red = 2'b00; green = 2'b11; blue = 2'b00; 
            end else if (is_apple) begin
                red = 2'b11; green = 2'b00; blue = 2'b00; 
            end else begin
                if (is_checker) begin
                    red = 2'b01; green = 2'b01; blue = 2'b01; 
                end else begin
                    red = 2'b00; green = 2'b00; blue = 2'b00; 
                end
            end
        end
    end
endmodule


// =========================================================================
// 6. MODULE HVSYNC GENERATOR
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
