`default_nettype none
`define COLOR_CYAN 3'd5

module huy (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] SW,       // 8 switch control
    output wire       hsync,    // xung dong bo ngang
    output wire       vsync,    // xung dong bo doc
    output reg  [1:0] r,      // 2-bit red
    output reg  [1:0] g,    // 2-bit green
    output reg  [1:0] b,     // 2-bit blue
    output wire       video_active  // video active
);

  parameter LOGO_SIZE = 160;      // Size of the logo in pixels
  parameter DISPLAY_WIDTH = 640;  // VGA display width
  parameter DISPLAY_HEIGHT = 480; // VGA display height

  wire [9:0] pix_x;
  wire [9:0] pix_y;

  // ==========================================
  // CAI DAT CHE DO
  // ==========================================
  wire cfg_tile  = SW[0]; // bat/tat lap lai nhieu logo
  wire cfg_color = SW[1]; // bat/tat doi mau

  reg [9:0] prev_y;

  // ==========================================
  // VGA TIMING
  // ==========================================
  hvsync_generator vga_sync_gen (
      .clk(clk),
      .reset(~rst_n),
      .hsync(hsync),
      .vsync(vsync),
      .display_on(video_active), 
      .hpos(pix_x),
      .vpos(pix_y)
  );

  // ==========================================
  // BOUNCING LOGIC & GRAPHICS
  // ==========================================
  reg [9:0] logo_left;
  reg [9:0] logo_top;
  reg dir_x;
  reg dir_y;

  wire pixel_value;
  reg [2:0] color_index;
  wire [5:0] color;

  wire [9:0] x = pix_x - logo_left;
  wire [9:0] y = pix_y - logo_top;

  wire logo_pixels = cfg_tile || (x < LOGO_SIZE && y < LOGO_SIZE);

  // Instantiation ROM
  bitmap_rom rom1 (
      .x(x[7:3]),
      .y(y[7:3]),
      .pixel(pixel_value)
  );

  palette palette_inst (
      .color_index(cfg_color ? color_index : `COLOR_CYAN),
      .rrggbb(color)
  );

  // RGB output logic
  always @(posedge clk) begin
    if (~rst_n) begin
      r   <= 2'b00;
      g <= 2'b00;
      b  <= 2'b00;
    end else begin
      r   <= 2'b00;
      g <= 2'b00;
      b  <= 2'b00;
      
      if (video_active && logo_pixels) begin
        r   <= pixel_value ? color[5:4] : 2'b00;
        g <= pixel_value ? color[3:2] : 2'b00;
        b  <= pixel_value ? color[1:0] : 2'b00;
      end
    end
  end

  // Bouncing logic
  always @(posedge clk) begin
    if (~rst_n) begin
      logo_left   <= 200;
      logo_top    <= 200;
      dir_y       <= 0;
      dir_x       <= 1;
      color_index <= 0;
      prev_y      <= 0;
    end else begin
      prev_y <= pix_y;
      if (pix_y == 0 && prev_y != pix_y) begin
        logo_left <= logo_left + (dir_x ? 1 : -1);
        logo_top  <= logo_top + (dir_y ? 1 : -1);
        
        if (logo_left - 1 == 0 && !dir_x) begin
          dir_x <= 1;
          color_index <= color_index + 1;
        end
        if (logo_left + 1 == DISPLAY_WIDTH - LOGO_SIZE && dir_x) begin
          dir_x <= 0;
          color_index <= color_index + 1;
        end
        if (logo_top - 1 == 0 && !dir_y) begin
          dir_y <= 1;
          color_index <= color_index + 1;
        end
        if (logo_top + 1 == DISPLAY_HEIGHT - LOGO_SIZE && dir_y) begin
          dir_y <= 0;
          color_index <= color_index + 1;
        end
      end
    end
  end

endmodule
