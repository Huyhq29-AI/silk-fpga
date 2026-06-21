`default_nettype none
`define COLOR_CYAN 3'd5
`define FPGA_DEBUG
module top_module (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] SW,
    input       [1:0] KEY,    //nut nhan
    output wire       hsync,    // xung dong bo ngang
    output wire       vsync,    // xung dong bo doc
    output reg  [1:0] r,      // 2-bit red
    output reg  [1:0] g,    // 2-bit green
    output reg  [1:0] b,     // 2-bit blue
    output wire       video_active  // video active
);


  reg [1:0] state;
  // =========================
  // VGA timing dùng hvsync_generator
  // =========================
  wire [9:0] pixel_x;
  wire [9:0] pixel_y;
  wire       visible;
  wire       frame_tick;
 


  reg game_over_d;

  // =========================
  // FSM game
  // =========================
  localparam S_IDLE      = 2'd0;
  localparam S_RUN       = 2'd1;
  localparam S_GAME_OVER = 2'd2;

  wire ko_now = (state == S_GAME_OVER);
  wire ko_start = ko_now && !game_over_d;
  wire rst = ~rst_n;
  reg jump_req;
  wire jump_pulse = frame_tick && jump_req;
  
  always @(posedge clk)
  begin
    if (rst)
      game_over_d <= 1'b0;
    else
      game_over_d <= ko_now;
  end






  wire [1:0] red, green, blue;

 
  assign r = red;
  assign g = green;
  assign b = blue;
  assign video_active = visible;


  // =========================
  // Tham số màn hình / vật thể
  // =========================
  localparam SCREEN_W = 640;
  localparam SCREEN_H = 480;

  localparam GROUND_Y = 440;

  localparam DINO_X   = 60;
  localparam DINO_W   = 32;
  localparam DINO_H   = 32;

  localparam OBS_W    = 24;
  localparam OBS_H    = 32;
  localparam OBS_Y    = GROUND_Y - OBS_H;



  hvsync_generator u_hvsync (
                     .clk(clk),
                     .reset(rst),
                     .hsync(hsync),
                     .vsync(vsync),
                     .display_on(visible),
                     .hpos(pixel_x),
                     .vpos(pixel_y)
                   );

  assign frame_tick = (pixel_x == 10'd0) && (pixel_y == 10'd0);

  // =========================
  // Bắt cạnh nút nhảy, rồi giữ yêu cầu nhảy đến frame tiếp theo
  // =========================
  reg jump_btn_d;


  always @(posedge clk)
  begin
    if (rst)
    begin
      jump_btn_d <= 1'b0;
      jump_req   <= 1'b0;
    end
    else
    begin
      jump_btn_d <= KEY[0];

        if (KEY[0] && !jump_btn_d)
        jump_req <= 1'b1;
      else if (frame_tick)
        jump_req <= 1'b0;
    end
  end





  reg [15:0] score;
  reg [3:0] speed;

  wire game_run  = (state == S_RUN);
  wire new_round = jump_pulse && (state != S_RUN);

  // =========================
  // Dino
  // =========================
  wire [9:0] dino_y;
  wire       on_ground;

  dino_ctrl #(
              .GROUND_Y(GROUND_Y),
              .DINO_H(DINO_H)
            ) u_dino_ctrl (
              .clk(clk),
              .rst(rst),
              .frame_tick(frame_tick),
              .game_run(game_run),
              .new_round(new_round),
              .jump_pulse(jump_pulse),
              .dino_y(dino_y),
              .on_ground(on_ground)
            );

  // =========================
  // Animation chân chạy
  // =========================
  reg       dino_frame;
  reg [3:0] anim_cnt;

  always @(posedge clk)
  begin
    if (rst)
    begin
      anim_cnt   <= 4'd0;
      dino_frame <= 1'b0;
    end
    else if (frame_tick)
    begin
      if (new_round)
      begin
        anim_cnt   <= 4'd0;
        dino_frame <= 1'b0;
      end
      else if (state == S_RUN && on_ground)
      begin
        if (anim_cnt == 4'd5)
        begin
          anim_cnt   <= 4'd0;
          dino_frame <= ~dino_frame;
        end
        else
        begin
          anim_cnt <= anim_cnt + 4'd1;
        end
      end
      else
      begin
        anim_cnt   <= 4'd0;
        dino_frame <= 1'b0;
      end
    end
  end

  // =========================
  // Obstacle
  // =========================
  wire [9:0] obs_x;

  obstacle_ctrl #(
                  .SCREEN_W(SCREEN_W)
                ) u_obstacle_ctrl (
                  .clk(clk),
                  .rst(rst),
                  .frame_tick(frame_tick),
                  .game_run(game_run),
                  .new_round(new_round),
                  .speed(speed),
                  .obs_x(obs_x)
                );

  // =========================
  // Collision
  // =========================
  wire hit;

  collision #(
              .DINO_W(DINO_W),
              .DINO_H(DINO_H),
              .OBS_W(OBS_W),
              .OBS_H(OBS_H)
            ) u_collision (
              .dino_x(DINO_X),
              .dino_y(dino_y),
              .obs_x(obs_x),
              .obs_y(OBS_Y),
              .hit(hit)
            );

  // =========================
  // Update state game theo frame
  // =========================
  always @(posedge clk)
  begin
    if (rst)
    begin
      state <= S_IDLE;
      score <= 16'd0;
      speed <= 4'd4;
    end
    else if (frame_tick)
    begin
      case (state)
        S_IDLE:
        begin
          score <= 16'd0;
          speed <= 4'd4;
          if (jump_req)
            state <= S_RUN;
        end

        S_RUN:
        begin
          if (hit)
          begin
            state <= S_GAME_OVER;
          end
          else
          begin
            score <= score + 16'd1;

            if (score[7:0] == 8'hFF && speed < 4'd8)
              speed <= speed + 4'd1;
          end
        end

        S_GAME_OVER:
        begin
          if (jump_req)
          begin
            state <= S_RUN;
            score <= 16'd0;
            speed <= 4'd4;
          end
        end

        default:
        begin
          state <= S_IDLE;
        end
      endcase
    end
  end

  // =========================
  // Renderer
  // =========================
  renderer #(
             .GROUND_Y(GROUND_Y),
             .DINO_W(DINO_W),
             .DINO_H(DINO_H),
             .OBS_W(OBS_W),
             .OBS_H(OBS_H)
           ) u_renderer (
             .visible(visible),
             .pixel_x(pixel_x),
             .pixel_y(pixel_y),
             .state(state),
             .dino_x(DINO_X),
             .dino_y(dino_y),
             .dino_frame(dino_frame),
             .dino_airborne(~on_ground),
             .obs_x(obs_x),
             .obs_y(OBS_Y),
             .red(red),
             .green(green),
             .blue(blue)
           );

endmodule


// ==========================================
// Dino controller: jump + gravity
// ==========================================
module dino_ctrl #(
    parameter GROUND_Y = 440,
    parameter DINO_H   = 32
  )(
    input  wire       clk,
    input  wire       rst,
    input  wire       frame_tick,
    input  wire       game_run,
    input  wire       new_round,
    input  wire       jump_pulse,
    output wire [9:0] dino_y,
    output reg        on_ground
  );

  localparam signed [11:0] JUMP_V0    = -12'sd12;
  localparam signed [11:0] GRAVITY    =  12'sd1;
  localparam signed [11:0] GROUND_TOP = GROUND_Y - DINO_H;

  reg signed [11:0] y_pos;
  reg signed [11:0] vy;

  assign dino_y = y_pos[9:0];

  always @(posedge clk)
  begin
    if (rst)
    begin
      y_pos     <= GROUND_TOP;
      vy        <= 12'sd0;
      on_ground <= 1'b1;
    end
    else if (frame_tick)
    begin
      if (new_round)
      begin
        y_pos     <= GROUND_TOP + JUMP_V0;
        vy        <= JUMP_V0 + GRAVITY;
        on_ground <= 1'b0;
      end
      else if (game_run)
      begin
        if (jump_pulse && on_ground)
        begin
          y_pos     <= y_pos + JUMP_V0;
          vy        <= JUMP_V0 + GRAVITY;
          on_ground <= 1'b0;
        end
        else if (!on_ground)
        begin
          if ((y_pos + vy) >= GROUND_TOP)
          begin
            y_pos     <= GROUND_TOP;
            vy        <= 12'sd0;
            on_ground <= 1'b1;
          end
          else
          begin
            y_pos     <= y_pos + vy;
            vy        <= vy + GRAVITY;
            on_ground <= 1'b0;
          end
        end
        else
        begin
          y_pos     <= GROUND_TOP;
          vy        <= 12'sd0;
          on_ground <= 1'b1;
        end
      end
    end
  end

endmodule


// ==========================================
// Obstacle controller: di chuyển từ phải sang trái
// ==========================================
module obstacle_ctrl #(
    parameter SCREEN_W = 640
  )(
    input  wire       clk,
    input  wire       rst,
    input  wire       frame_tick,
    input  wire       game_run,
    input  wire       new_round,
    input  wire [3:0] speed,
    output reg  [9:0] obs_x
  );

  always @(posedge clk)
  begin
    if (rst)
    begin
      obs_x <= SCREEN_W + 10'd80;
    end
    else if (frame_tick)
    begin
      if (new_round)
      begin
        obs_x <= SCREEN_W + 10'd80;
      end
      else if (game_run)
      begin
        if (obs_x <= speed)
          obs_x <= SCREEN_W + 10'd80;
        else
          obs_x <= obs_x - speed;
      end
    end
  end

endmodule


// ==========================================
// Collision: AABB đơn giản
// ==========================================
module collision #(
    parameter DINO_W = 32,
    parameter DINO_H = 32,
    parameter OBS_W  = 24,
    parameter OBS_H  = 32
  )(
    input  wire [9:0] dino_x,
    input  wire [9:0] dino_y,
    input  wire [9:0] obs_x,
    input  wire [9:0] obs_y,
    output wire       hit
  );

  wire [9:0] dino_left   = dino_x + 10'd3;
  wire [9:0] dino_right  = dino_x + DINO_W - 10'd4;
  wire [9:0] dino_top    = dino_y + 10'd2;
  wire [9:0] dino_bottom = dino_y + DINO_H - 10'd1;

  wire [9:0] obs_left    = obs_x + 10'd4;
  wire [9:0] obs_right   = obs_x + OBS_W - 10'd5;
  wire [9:0] obs_top     = obs_y + 10'd1;
  wire [9:0] obs_bottom  = obs_y + OBS_H - 10'd1;

  assign hit =
         (dino_right  >= obs_left)   &&
         (dino_left   <= obs_right)  &&
         (dino_bottom >= obs_top)    &&
         (dino_top    <= obs_bottom);

endmodule

module sound_engine #(
    parameter CLK_HZ = 25000000
  )(
    input  wire clk,
    input  wire rst,
    input  wire jump_pulse,
    input  wire ko_start,
    output reg  audio_out
  );

  // =========================
  // Tạo tick 1ms
  // =========================
  localparam integer MS_DIV = CLK_HZ / 1000;

  reg [31:0] ms_cnt;
  reg tick_1ms;

  always @(posedge clk)
  begin
    if (rst)
    begin
      ms_cnt   <= 0;
      tick_1ms <= 1'b0;
    end
    else
    begin
      if (ms_cnt == MS_DIV - 1)
      begin
        ms_cnt   <= 0;
        tick_1ms <= 1'b1;
      end
      else
      begin
        ms_cnt   <= ms_cnt + 1;
        tick_1ms <= 1'b0;
      end
    end
  end

  // =========================
  // Square-wave tone generator
  // half_period = số clock cho nửa chu kỳ
  // =========================
  reg [31:0] half_period;
  reg [31:0] tone_cnt;
  reg tone_enable;

  always @(posedge clk)
  begin
    if (rst)
    begin
      tone_cnt   <= 0;
      audio_out  <= 1'b0;
    end
    else if (!tone_enable || half_period == 0)
    begin
      tone_cnt   <= 0;
      audio_out  <= 1'b0;
    end
    else
    begin
      if (tone_cnt >= half_period - 1)
      begin
        tone_cnt  <= 0;
        audio_out <= ~audio_out;
      end
      else
      begin
        tone_cnt <= tone_cnt + 1;
      end
    end
  end

  // =========================
  // Note table (25MHz clock)
  // half_period ~= CLK_HZ / (2*f)
  // =========================
  localparam [31:0] NOTE_C5 = 47778; // ~261 Hz
  localparam [31:0] NOTE_E5 = 37879; // ~330 Hz
  localparam [31:0] NOTE_G5 = 31888; // ~392 Hz
  localparam [31:0] NOTE_A5 = 28409; // ~440 Hz
  localparam [31:0] NOTE_B5 = 25310; // ~494 Hz
  localparam [31:0] NOTE_C6 = 23889; // ~523 Hz
  localparam [31:0] NOTE_D6 = 21284; // ~587 Hz
  localparam [31:0] NOTE_E6 = 18939; // ~660 Hz

  // =========================
  // Bộ phát hiệu ứng
  // mode:
  // 0 = idle
  // 1 = jump beep
  // 2 = KO jingle
  // =========================
  reg [1:0] mode;
  reg [7:0] step_idx;
  reg [15:0] step_ms;
  reg ko_busy;

  localparam MODE_IDLE = 2'd0;
  localparam MODE_JUMP = 2'd1;
  localparam MODE_KO   = 2'd2;

  always @(posedge clk)
  begin
    if (rst)
    begin
      mode        <= MODE_IDLE;
      step_idx    <= 0;
      step_ms     <= 0;
      tone_enable <= 1'b0;
      half_period <= 0;
      ko_busy     <= 1'b0;
    end
    else
    begin
      // Ưu tiên KO hơn jump
      if (ko_start && !ko_busy)
      begin
        mode        <= MODE_KO;
        step_idx    <= 0;
        step_ms     <= 0;
        tone_enable <= 1'b1;
        half_period <= NOTE_A5;
        ko_busy     <= 1'b1;
      end
      else if (jump_pulse && mode == MODE_IDLE)
      begin
        mode        <= MODE_JUMP;
        step_idx    <= 0;
        step_ms     <= 0;
        tone_enable <= 1'b1;
        half_period <= NOTE_E6;
      end

      if (tick_1ms)
      begin
        case (mode)
          MODE_IDLE:
          begin
            tone_enable <= 1'b0;
            half_period <= 0;
          end

          // Jump: 1 tiếng tít 60ms
          MODE_JUMP:
          begin
            if (step_ms >= 16'd60)
            begin
              mode        <= MODE_IDLE;
              step_ms     <= 0;
              tone_enable <= 1'b0;
              half_period <= 0;
            end
            else
            begin
              step_ms <= step_ms + 1;
            end
          end

          // KO jingle nguyên bản 4 nốt
          // A5 (120ms), G5 (120ms), E5 (180ms), C5 (240ms)
          MODE_KO:
          begin
            step_ms <= step_ms + 1;

            case (step_idx)
              0:
              begin
                tone_enable <= 1'b1;
                half_period <= NOTE_A5;
                if (step_ms >= 16'd120)
                begin
                  step_idx <= 1;
                  step_ms  <= 0;
                end
              end

              1:
              begin
                tone_enable <= 1'b1;
                half_period <= NOTE_G5;
                if (step_ms >= 16'd120)
                begin
                  step_idx <= 2;
                  step_ms  <= 0;
                end
              end

              2:
              begin
                tone_enable <= 1'b1;
                half_period <= NOTE_E5;
                if (step_ms >= 16'd180)
                begin
                  step_idx <= 3;
                  step_ms  <= 0;
                end
              end

              3:
              begin
                tone_enable <= 1'b1;
                half_period <= NOTE_C5;
                if (step_ms >= 16'd240)
                begin
                  step_idx <= 4;
                  step_ms  <= 0;
                end
              end

              4:
              begin
                tone_enable <= 1'b0;
                half_period <= 0;
                if (step_ms >= 16'd80)
                begin
                  mode     <= MODE_IDLE;
                  step_idx <= 0;
                  step_ms  <= 0;
                  ko_busy  <= 1'b0;
                end
              end

              default:
              begin
                mode        <= MODE_IDLE;
                step_idx    <= 0;
                step_ms     <= 0;
                tone_enable <= 1'b0;
                half_period <= 0;
                ko_busy     <= 1'b0;
              end
            endcase
          end

          default:
          begin
            mode        <= MODE_IDLE;
            tone_enable <= 1'b0;
            half_period <= 0;
            ko_busy     <= 1'b0;
          end
        endcase
      end
    end
  end

endmodule

// ==========================================
// Renderer: nền trắng, dino bitmap, cactus bitmap, KO khi game over
// ==========================================
module renderer #(
    parameter GROUND_Y = 440,
    parameter DINO_W   = 32,
    parameter DINO_H   = 32,
    parameter OBS_W    = 24,
    parameter OBS_H    = 32
  )(
    input  wire [1:0]  state,
    input  wire        visible,
    input  wire [9:0]  pixel_x,
    input  wire [9:0]  pixel_y,
    input  wire [9:0]  dino_x,
    input  wire [9:0]  dino_y,
    input  wire        dino_frame,
    input  wire        dino_airborne,
    input  wire [9:0]  obs_x,
    input  wire [9:0]  obs_y,
    output reg  [1:0]  red,
    output reg  [1:0]  green,
    output reg  [1:0]  blue
  );

  localparam S_GAME_OVER = 2'd2;

  // =========================
  // Ground hơi gồ ghề
  // =========================
  wire on_ground_main =
       (pixel_y >= GROUND_Y) && (pixel_y < GROUND_Y + 10'd2);

  wire on_ground_ridge =
       ((pixel_y == GROUND_Y - 10'd1) &&
        ((pixel_x[4:0] == 5'd3) || (pixel_x[4:0] == 5'd11) ||
         (pixel_x[4:0] == 5'd19) || (pixel_x[4:0] == 5'd27))) ||
       ((pixel_y == GROUND_Y + 10'd2) &&
        ((pixel_x[5:0] == 6'd7) || (pixel_x[5:0] == 6'd21) ||
         (pixel_x[5:0] == 6'd39) || (pixel_x[5:0] == 6'd54)));

  wire on_ground_pebble =
       ((pixel_y == GROUND_Y + 10'd4) &&
        ((pixel_x[6:0] == 7'd18) || (pixel_x[6:0] == 7'd71) || (pixel_x[6:0] == 7'd109))) ||
       ((pixel_y == GROUND_Y + 10'd5) &&
        ((pixel_x[6:0] == 7'd19) || (pixel_x[6:0] == 7'd72)));

  wire on_ground = on_ground_main || on_ground_ridge || on_ground_pebble;

  // =========================
  // Dino bitmap 32x32
  // =========================
  wire in_dino_box =
       (pixel_x >= dino_x) && (pixel_x < dino_x + DINO_W) &&
       (pixel_y >= dino_y) && (pixel_y < dino_y + DINO_H);

  wire [9:0] local_x_full = pixel_x - dino_x;
  wire [9:0] local_y_full = pixel_y - dino_y;
  wire [4:0] local_x = local_x_full[4:0];
  wire [4:0] local_y = local_y_full[4:0];

  reg [31:0] dino_row_bits;

  always @(*)
  begin
    dino_row_bits = 32'd0;

    if (dino_airborne)
    begin
      case (local_y)
        5'd0:
          dino_row_bits = 32'b00000000000111111111111111111000;
        5'd1:
          dino_row_bits = 32'b00000000011111111111111111111110;
        5'd2:
          dino_row_bits = 32'b00000000011111111111111111111110;
        5'd3:
          dino_row_bits = 32'b00000000011111111111111111111110;
        5'd4:
          dino_row_bits = 32'b00000000011100011111111111111110;
        5'd5:
          dino_row_bits = 32'b00000000011100011111111111111110;
        5'd6:
          dino_row_bits = 32'b00000000011100011111111111111110;
        5'd7:
          dino_row_bits = 32'b00000000011111111111111111111110;
        5'd8:
          dino_row_bits = 32'b00000000011111111111111111111110;
        5'd9:
          dino_row_bits = 32'b00000000011111111111111111111110;
        5'd10:
          dino_row_bits = 32'b00000000011111111111111111111110;
        5'd11:
          dino_row_bits = 32'b00000000011111111111111111111110;
        5'd12:
          dino_row_bits = 32'b00000000011111111111111100000000;
        5'd13:
          dino_row_bits = 32'b00000000011111111111111100000000;
        5'd14:
          dino_row_bits = 32'b00000000011111111111111100000000;
        5'd15:
          dino_row_bits = 32'b00000000011111111111111111111000;
        5'd16:
          dino_row_bits = 32'b00000000011111111111111111111000;
        5'd17:
          dino_row_bits = 32'b00000000011111111111111111111000;
        5'd18:
          dino_row_bits = 32'b00000000011111111111111111111000;
        5'd19:
          dino_row_bits = 32'b00000001111111111110000000000000;
        5'd20:
          dino_row_bits = 32'b00000001111111111110000000000000;
        5'd21:
          dino_row_bits = 32'b00000111111111111110000000000000;
        5'd22:
          dino_row_bits = 32'b10000111111111111110000000000000;
        5'd23:
          dino_row_bits = 32'b11001111111111111111111100000000;
        5'd24:
          dino_row_bits = 32'b11001111111111111111111100000000;
        5'd25:
          dino_row_bits = 32'b11011111111111111100011100000000;
        5'd26:
          dino_row_bits = 32'b11011111111111111100011100000000;
        5'd27:
          dino_row_bits = 32'b11111111111111111100011100000000;
        5'd28:
          dino_row_bits = 32'b00111111111111111100000000000000;
        5'd29:
          dino_row_bits = 32'b00011111111111111000000000000000;
        5'd30:
          dino_row_bits = 32'b00000111000001110000000000000000;
        5'd31:
          dino_row_bits = 32'b00000111100001111000000000000000;
        default:
          dino_row_bits = 32'b00000000000000000000000000000000;
      endcase
    end
    else if (dino_frame == 1'b0)
    begin
      case (local_y)
        5'd0:
          dino_row_bits = 32'b00000000000111111111111111111000;
        5'd1:
          dino_row_bits = 32'b00000000011111111111111111111110;
        5'd2:
          dino_row_bits = 32'b00000000011111111111111111111110;
        5'd3:
          dino_row_bits = 32'b00000000011111111111111111111110;
        5'd4:
          dino_row_bits = 32'b00000000011100011111111111111110;
        5'd5:
          dino_row_bits = 32'b00000000011100011111111111111110;
        5'd6:
          dino_row_bits = 32'b00000000011100011111111111111110;
        5'd7:
          dino_row_bits = 32'b00000000011111111111111111111110;
        5'd8:
          dino_row_bits = 32'b00000000011111111111111111111110;
        5'd9:
          dino_row_bits = 32'b00000000011111111111111111111110;
        5'd10:
          dino_row_bits = 32'b00000000011111111111111111111110;
        5'd11:
          dino_row_bits = 32'b00000000011111111111111111111110;
        5'd12:
          dino_row_bits = 32'b00000000011111111111111100000000;
        5'd13:
          dino_row_bits = 32'b00000000011111111111111100000000;
        5'd14:
          dino_row_bits = 32'b00000000011111111111111100000000;
        5'd15:
          dino_row_bits = 32'b00000000011111111111111111111000;
        5'd16:
          dino_row_bits = 32'b00000000011111111111111111111000;
        5'd17:
          dino_row_bits = 32'b00000000011111111111111111111000;
        5'd18:
          dino_row_bits = 32'b00000000011111111111111111111000;
        5'd19:
          dino_row_bits = 32'b00000001111111111110000000000000;
        5'd20:
          dino_row_bits = 32'b00000001111111111110000000000000;
        5'd21:
          dino_row_bits = 32'b00000111111111111110000000000000;
        5'd22:
          dino_row_bits = 32'b10000111111111111110000000000000;
        5'd23:
          dino_row_bits = 32'b11001111111111111111111100000000;
        5'd24:
          dino_row_bits = 32'b11001111111111111111111100000000;
        5'd25:
          dino_row_bits = 32'b11011111111111111100011100000000;
        5'd26:
          dino_row_bits = 32'b11011111111111111100011100000000;
        5'd27:
          dino_row_bits = 32'b11111111111111111100011100000000;
        5'd28:
          dino_row_bits = 32'b00111111111111111100000000000000;
        5'd29:
          dino_row_bits = 32'b00011111111111111000000000000000;
        5'd30:
          dino_row_bits = 32'b00000111000001110000000000000000;
        5'd31:
          dino_row_bits = 32'b00000111100001111000000000000000;
        default:
          dino_row_bits = 32'b00000000000000000000000000000000;
      endcase
    end
    else
    begin
      case (local_y)
        5'd0:
          dino_row_bits = 32'b00000000000111111111111111111000;
        5'd1:
          dino_row_bits = 32'b00000000011111111111111111111110;
        5'd2:
          dino_row_bits = 32'b00000000011111111111111111111110;
        5'd3:
          dino_row_bits = 32'b00000000011111111111111111111110;
        5'd4:
          dino_row_bits = 32'b00000000011100011111111111111110;
        5'd5:
          dino_row_bits = 32'b00000000011100011111111111111110;
        5'd6:
          dino_row_bits = 32'b00000000011100011111111111111110;
        5'd7:
          dino_row_bits = 32'b00000000011111111111111111111110;
        5'd8:
          dino_row_bits = 32'b00000000011111111111111111111110;
        5'd9:
          dino_row_bits = 32'b00000000011111111111111111111110;
        5'd10:
          dino_row_bits = 32'b00000000011111111111111111111110;
        5'd11:
          dino_row_bits = 32'b00000000011111111111111111111110;
        5'd12:
          dino_row_bits = 32'b00000000011111111111111100000000;
        5'd13:
          dino_row_bits = 32'b00000000011111111111111100000000;
        5'd14:
          dino_row_bits = 32'b00000000011111111111111100000000;
        5'd15:
          dino_row_bits = 32'b00000000011111111111111111111000;
        5'd16:
          dino_row_bits = 32'b00000000011111111111111111111000;
        5'd17:
          dino_row_bits = 32'b00000000011111111111111111111000;
        5'd18:
          dino_row_bits = 32'b00000000011111111111111111111000;
        5'd19:
          dino_row_bits = 32'b00000001111111111110000000000000;
        5'd20:
          dino_row_bits = 32'b00000001111111111110000000000000;
        5'd21:
          dino_row_bits = 32'b00000111111111111110000000000000;
        5'd22:
          dino_row_bits = 32'b10000111111111111110000000000000;
        5'd23:
          dino_row_bits = 32'b11001111111111111111111100000000;
        5'd24:
          dino_row_bits = 32'b11001111111111111111111100000000;
        5'd25:
          dino_row_bits = 32'b11011111111111111100011100000000;
        5'd26:
          dino_row_bits = 32'b11011111111111111100011100000000;
        5'd27:
          dino_row_bits = 32'b11111111111111111100011100000000;
        5'd28:
          dino_row_bits = 32'b00111111111111111100000000000000;
        5'd29:
          dino_row_bits = 32'b00011111111111111000000000000000;
        5'd30:
          dino_row_bits = 32'b00000111000001110000000000000000;
        5'd31:
          dino_row_bits = 32'b00000001111111100000000000000000;
        default:
          dino_row_bits = 32'b00000000000000000000000000000000;
      endcase
    end
  end

  wire dino_pixel = in_dino_box && dino_row_bits[31 - local_x];

  // =========================
  // Cactus bitmap 24x32
  // =========================
  wire in_obs_box =
       (pixel_x >= obs_x) && (pixel_x < obs_x + OBS_W) &&
       (pixel_y >= obs_y) && (pixel_y < obs_y + OBS_H);

  wire [9:0] obs_local_x_full = pixel_x - obs_x;
  wire [9:0] obs_local_y_full = pixel_y - obs_y;
  wire [4:0] obs_local_x = obs_local_x_full[4:0];
  wire [4:0] obs_local_y = obs_local_y_full[4:0];

  reg [23:0] cactus_row_bits;

  always @(*)
  begin
    case (obs_local_y)
      5'd0:
        cactus_row_bits = 24'b000000000011110000000000;
      5'd1:
        cactus_row_bits = 24'b000000000111111000000000;
      5'd2:
        cactus_row_bits = 24'b000000000111111000000000;
      5'd3:
        cactus_row_bits = 24'b000000000111111000000000;
      5'd4:
        cactus_row_bits = 24'b000000000111111000000000;
      5'd5:
        cactus_row_bits = 24'b000000000111111000000000;
      5'd6:
        cactus_row_bits = 24'b000000000111111000000000;
      5'd7:
        cactus_row_bits = 24'b000000000111111000000000;
      5'd8:
        cactus_row_bits = 24'b000000000111111000000000;
      5'd9:
        cactus_row_bits = 24'b000000001111111100000000;
      5'd10:
        cactus_row_bits = 24'b000000011111111110000000;
      5'd11:
        cactus_row_bits = 24'b000000011111111110000000;
      5'd12:
        cactus_row_bits = 24'b000011011111111110000000;
      5'd13:
        cactus_row_bits = 24'b000011011111111110000000;
      5'd14:
        cactus_row_bits = 24'b000011011111111110011000;
      5'd15:
        cactus_row_bits = 24'b000011011111111110011000;
      5'd16:
        cactus_row_bits = 24'b000011011111111110011000;
      5'd17:
        cactus_row_bits = 24'b000011011111111110011000;
      5'd18:
        cactus_row_bits = 24'b000011011111111110011000;
      5'd19:
        cactus_row_bits = 24'b000011111101111110011000;
      5'd20:
        cactus_row_bits = 24'b000011111101111110011000;
      5'd21:
        cactus_row_bits = 24'b000000111101111110011000;
      5'd22:
        cactus_row_bits = 24'b000000000111111000011000;
      5'd23:
        cactus_row_bits = 24'b000000000111111000011000;
      5'd24:
        cactus_row_bits = 24'b000000000111111000000000;
      5'd25:
        cactus_row_bits = 24'b000000000111111000000000;
      5'd26:
        cactus_row_bits = 24'b000000000111111000000000;
      5'd27:
        cactus_row_bits = 24'b000000000111111000000000;
      5'd28:
        cactus_row_bits = 24'b000000000111111000000000;
      5'd29:
        cactus_row_bits = 24'b000000000111111000000000;
      5'd30:
        cactus_row_bits = 24'b000000000111111000000000;
      5'd31:
        cactus_row_bits = 24'b000000000000000000000000;
      default:
        cactus_row_bits = 24'b000000000000000000000000;
    endcase
  end

  wire on_obs = in_obs_box && cactus_row_bits[23 - obs_local_x];

  // =========================
  // Chữ KO
  // =========================
  localparam K_X = 10'd290;
  localparam K_Y = 10'd180;
  localparam K_W = 10'd30;
  localparam K_H = 10'd40;

  localparam O_X = 10'd330;
  localparam O_Y = 10'd180;
  localparam O_W = 10'd30;
  localparam O_H = 10'd40;

  wire game_over_active = (state == S_GAME_OVER);

  wire k_left =
       game_over_active &&
       (pixel_x >= K_X) && (pixel_x < K_X + 10'd4) &&
       (pixel_y >= K_Y) && (pixel_y < K_Y + K_H);

  wire [9:0] k_up_lhs = pixel_y - K_Y;
  wire [9:0] k_up_rhs = (K_X + K_W - 10'd1) - pixel_x;

  wire k_diag_up =
       game_over_active &&
       (pixel_x >= K_X + 10'd4) && (pixel_x < K_X + K_W) &&
       (pixel_y >= K_Y) && (pixel_y < K_Y + 10'd20) &&
       (
         (k_up_lhs == k_up_rhs) ||
         (k_up_lhs == k_up_rhs + 10'd1) ||
         (k_up_rhs == k_up_lhs + 10'd1) ||
         (k_up_lhs == k_up_rhs + 10'd2) ||
         (k_up_rhs == k_up_lhs + 10'd2)
       );

  wire [9:0] k_down_lhs = pixel_y - (K_Y + 10'd20);
  wire [9:0] k_down_rhs = pixel_x - (K_X + 10'd4);

  wire k_diag_down =
       game_over_active &&
       (pixel_x >= K_X + 10'd4) && (pixel_x < K_X + K_W) &&
       (pixel_y >= K_Y + 10'd20) && (pixel_y < K_Y + K_H) &&
       (
         (k_down_lhs == k_down_rhs) ||
         (k_down_lhs == k_down_rhs + 10'd1) ||
         (k_down_rhs == k_down_lhs + 10'd1) ||
         (k_down_lhs == k_down_rhs + 10'd2) ||
         (k_down_rhs == k_down_lhs + 10'd2)
       );

  wire on_k = k_left || k_diag_up || k_diag_down;

  wire o_top =
       game_over_active &&
       (pixel_x >= O_X) && (pixel_x < O_X + O_W) &&
       (pixel_y >= O_Y) && (pixel_y < O_Y + 10'd4);

  wire o_bottom =
       game_over_active &&
       (pixel_x >= O_X) && (pixel_x < O_X + O_W) &&
       (pixel_y >= O_Y + O_H - 10'd4) && (pixel_y < O_Y + O_H);

  wire o_left =
       game_over_active &&
       (pixel_x >= O_X) && (pixel_x < O_X + 10'd4) &&
       (pixel_y >= O_Y) && (pixel_y < O_Y + O_H);

  wire o_right =
       game_over_active &&
       (pixel_x >= O_X + O_W - 10'd4) && (pixel_x < O_X + O_W) &&
       (pixel_y >= O_Y) && (pixel_y < O_Y + O_H);

  wire on_o = o_top || o_bottom || o_left || o_right;

  always @(*)
  begin
    if (!visible)
    begin
      red   = 2'b00;
      green = 2'b00;
      blue  = 2'b00;
    end
    else if (dino_pixel || on_obs || on_ground)
    begin
      red   = 2'b00;
      green = 2'b00;
      blue  = 2'b00;
    end
    else if (on_k || on_o)
    begin
      red   = 2'b11;
      green = 2'b00;
      blue  = 2'b00;
    end
    else
    begin
      red   = 2'b11;
      green = 2'b11;
      blue  = 2'b11;
    end
  end

endmodule
// ==========================================
// VGA HVSYNC Generator (640x480 @ 60Hz, 25MHz Clock)
// ==========================================
module hvsync_generator (
    input  wire clk,
    input  wire reset,
    output wire hsync,
    output wire vsync,
    output wire display_on,
    output wire [9:0] hpos,
    output wire [9:0] vpos
);
    // Các thông số Timing chuẩn cho độ phân giải 640x480 @ 60Hz
    localparam H_DISPLAY       = 640;
    localparam H_FRONT_PORCH   = 16;
    localparam H_SYNC_PULSE    = 96;
    localparam H_BACK_PORCH    = 48;
    localparam H_MAX           = H_DISPLAY + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH - 1;

    localparam V_DISPLAY       = 480;
    localparam V_FRONT_PORCH   = 10;
    localparam V_SYNC_PULSE    = 2;
    localparam V_BACK_PORCH    = 33;
    localparam V_MAX           = V_DISPLAY + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH - 1;

    reg [9:0] h_count;
    reg [9:0] v_count;

    always @(posedge clk) begin
        if (reset) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end else begin
            if (h_count == H_MAX) begin
                h_count <= 10'd0;
                if (v_count == V_MAX)
                    v_count <= 10'd0;
                else
                    v_count <= v_count + 10'd1;
            end else begin
                h_count <= h_count + 10'd1;
            end
        end
    end

    // Tạo xung đồng bộ (Active Low chuẩn cho các DAC màn hình)
    assign hsync = ~(h_count >= (H_DISPLAY + H_FRONT_PORCH) && h_count < (H_DISPLAY + H_FRONT_PORCH + H_SYNC_PULSE));
    assign vsync = ~(v_count >= (V_DISPLAY + V_FRONT_PORCH) && v_count < (V_DISPLAY + V_FRONT_PORCH + V_SYNC_PULSE));
    
    // Tín hiệu Visible (chỉ vẽ hình khi đang ở vùng hiển thị)
    assign display_on = (h_count < H_DISPLAY) && (v_count < V_DISPLAY);
    
    // Đẩy tọa độ ra cho Renderer xử lý hình ảnh
    assign hpos = h_count;
    assign vpos = v_count;
    
endmodule
