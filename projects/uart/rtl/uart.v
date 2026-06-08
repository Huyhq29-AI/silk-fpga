module uart 
(
    input        clk,
    input        rst_n,
    input  [7:0] SW, //khong dung switch4
    input        uart_rx,
    output       uart_tx
);
    // ==========================================
    // KHAI BÁO CÁC CHÂN & DÂY NỐI
    // ==========================================
    // Ánh xạ dựa trên MODE_UART
    wire uart_rx_pin = uart_rx;
    wire uart_tx_pin;
    assign uart_tx = uart_tx_pin;

    // Tín hiệu nội bộ
    wire rx_valid;
    wire [7:0] rx_data;
    wire tx_busy;
    reg rx_read_ack;

    // Buffer 1 byte để cất dữ liệu, tránh tràn khi TX đang bận gửi
    reg [7:0] tx_buffer;
    reg has_data;

    // ==========================================
    // MODULE NHẬN UART (RX)
    // ==========================================
    /* verilator lint_off PINCONNECTEMPTY */
    uart_rx #(
        .CLK_HZ(25_000_000),  // clock 25MHz
        .BIT_RATE(115200),    //
        .PAYLOAD_BITS(8), 
        .STOP_BITS(1)
    ) rx_inst (
        .clk(clk),
        .resetn(rst_n),
        .uart_rxd(uart_rx_pin),
        .uart_rts(), // Không dùng 
        .uart_rx_read(rx_read_ack),
        .uart_rx_valid(rx_valid),
        .uart_rx_data(rx_data)
    );

    // ==========================================
    // MODULE PHÁT UART (TX)
    // ==========================================
    // Logic kích hoạt TX: Có data trong buffer VÀ bộ TX đang rảnh rỗi
    wire tx_en = has_data && !tx_busy;

    uart_tx #(
        .CLK_HZ(25_000_000), 
        .BIT_RATE(115200), 
        .PAYLOAD_BITS(8), 
        .STOP_BITS(1)
    ) tx_inst (
        .clk(clk),
        .resetn(rst_n),
        .uart_txd(uart_tx_pin),
        .uart_tx_busy(tx_busy),
        .uart_tx_en(tx_en),
        .uart_tx_data(tx_buffer)
    );

    // ==========================================
    // LOGIC LOOPBACK (MÁY TRẠNG THÁI ECHO)
    // ==========================================
    always @(posedge clk) begin
        if (!rst_n) begin
            has_data <= 1'b0;
            rx_read_ack <= 1'b0;
            tx_buffer <= 8'h00;
        end else begin
            
            if (rx_valid && !has_data) begin
                tx_buffer <= rx_data;
                has_data <= 1'b1;       
                rx_read_ack <= 1'b1;    
            end else begin
                rx_read_ack <= 1'b0;
            end

            
            if (tx_en) begin
                has_data <= 1'b0;
            end
        end
    end
endmodule

// =========================================================================
// UART TX
// =========================================================================

module uart_tx #(parameter 
    BIT_RATE     = 9600,       
    CLK_HZ       = 50_000_000, 
    PAYLOAD_BITS = 8,          
    STOP_BITS    = 1           
) (
    input  wire         clk         , 
    input  wire         resetn      , 
    output wire         uart_txd    , 
    output wire         uart_tx_busy, 
    input  wire         uart_tx_en  , 
    input  wire [PAYLOAD_BITS-1:0]   uart_tx_data  
);
    localparam       CYCLES_PER_BIT     = (CLK_HZ - 1) / BIT_RATE;
    localparam       COUNT_REG_LEN      = 1+$clog2(CYCLES_PER_BIT);

    reg txd_reg;
    reg [PAYLOAD_BITS-1:0] data_to_send;
    reg [COUNT_REG_LEN-1:0] cycle_counter;
    reg [3:0] fsm_state;

    localparam FSM_IDLE = 0;
    localparam FSM_START= 1;
    localparam FSM_SEND = 2;
    localparam FSM_STOP = 2 + PAYLOAD_BITS;
    localparam FSM_END = FSM_STOP + STOP_BITS - 1;

    assign uart_tx_busy = fsm_state != FSM_IDLE;
    assign uart_txd     = txd_reg;

    wire next_bit     = cycle_counter == CYCLES_PER_BIT[COUNT_REG_LEN-1:0];

    function [3:0] next_fsm_state(input tx_en);
        if (fsm_state == FSM_IDLE) begin
            if (tx_en) next_fsm_state = FSM_START;
            else next_fsm_state = FSM_IDLE;
        end else begin
            if (next_bit) begin
                if (fsm_state == FSM_END) next_fsm_state = FSM_IDLE;
                else next_fsm_state = fsm_state + 1;
            end else begin
                next_fsm_state = fsm_state;
            end
        end
    endfunction

    always @(posedge clk) begin : p_data_to_send
        if(!resetn) begin
            data_to_send <= {PAYLOAD_BITS{1'b0}};
        end else if(fsm_state == FSM_IDLE && uart_tx_en) begin
            data_to_send <= uart_tx_data;
        end else if(fsm_state >= FSM_SEND && fsm_state < FSM_STOP && next_bit) begin
            data_to_send <= {1'b0, data_to_send[PAYLOAD_BITS-1:1]};
        end
    end

    always @(posedge clk) begin : p_cycle_counter
        if(!resetn) begin
            cycle_counter <= {COUNT_REG_LEN{1'b0}};
        end else if(next_bit) begin
            cycle_counter <= {COUNT_REG_LEN{1'b0}};
        end else if(fsm_state != FSM_IDLE) begin
            cycle_counter <= cycle_counter + 1'b1;
        end
    end

    always @(posedge clk) begin : p_fsm_state
        if(!resetn) begin
            fsm_state <= FSM_IDLE;
        end else begin
            fsm_state <= next_fsm_state(uart_tx_en);
        end
    end

    always @(posedge clk) begin : p_txd_reg
        if(!resetn) begin
            txd_reg <= 1'b1;
        end else if(fsm_state == FSM_START) begin
            txd_reg <= 1'b0;
        end else if(fsm_state >= FSM_SEND && fsm_state < FSM_STOP) begin
            txd_reg <= data_to_send[0];
        end else begin
            txd_reg <= 1'b1;
        end
    end
endmodule


// =========================================================================
// UART RX 
// =========================================================================
module uart_rx #(parameter 
    BIT_RATE     = 9600,       
    CLK_HZ       = 50_000_000, 
    PAYLOAD_BITS = 8,          
    STOP_BITS    = 1           
) (
    input  wire        clk          , 
    input  wire        resetn       , 
    input  wire        uart_rxd     , 
    output reg         uart_rts     , 
    input  wire        uart_rx_read , 
    output wire        uart_rx_valid, 
    output wire [PAYLOAD_BITS-1:0] uart_rx_data   
);
    localparam       CYCLES_PER_BIT     = (CLK_HZ - 1) / BIT_RATE;
    localparam       COUNT_REG_LEN      = 1+$clog2(CYCLES_PER_BIT);
    localparam       BIT_CNT_WIDTH      = $clog2(PAYLOAD_BITS);

    reg [1:0] rxd_reg;
    reg [PAYLOAD_BITS-1:0] recieved_data;
    reg [COUNT_REG_LEN-1:0] cycle_counter;
    
    // THANH GHI ĐẾM BIT MỚI (Tách khỏi FSM)
    reg [BIT_CNT_WIDTH:0] bit_cnt; 
    reg bit_sample;
    
    // FSM STATES THUẦN TÚY
    reg [2:0] fsm_state;
    localparam FSM_IDLE  = 3'd0;
    localparam FSM_START = 3'd1;
    localparam FSM_RECV  = 3'd2;
    localparam FSM_STOP  = 3'd3;
    localparam FSM_READY = 3'd4;

    assign uart_rx_valid = (fsm_state == FSM_READY);
    assign uart_rx_data  = recieved_data;

    wire next_bit = (cycle_counter == CYCLES_PER_BIT[COUNT_REG_LEN-1:0]);
    wire mid_bit  = (cycle_counter == CYCLES_PER_BIT[COUNT_REG_LEN-1:0] / 2);

    always @(posedge clk) begin : p_fsm_state
        if(!resetn) begin
            fsm_state <= FSM_IDLE;
        end else begin
            case(fsm_state)
                FSM_IDLE : fsm_state <= rxd_reg[0]  ? FSM_IDLE  : FSM_START;
                FSM_START: fsm_state <= next_bit    ? FSM_RECV  : FSM_START;
                // Điều kiện nhảy từ RECV -> STOP là đếm đủ PAYLOAD_BITS
                FSM_RECV : fsm_state <= (next_bit && bit_cnt == PAYLOAD_BITS - 1) ? FSM_STOP : FSM_RECV;
                FSM_STOP : fsm_state <= mid_bit     ? (rxd_reg[0] ? FSM_READY : FSM_IDLE) : FSM_STOP;
                FSM_READY: fsm_state <= uart_rx_read? FSM_IDLE  : FSM_READY;
                default  : fsm_state <= FSM_IDLE;
            endcase
        end
    end


    always @(posedge clk) begin : p_bit_cnt
        if(!resetn) begin
            bit_cnt <= 0;
        end else if (fsm_state == FSM_IDLE || fsm_state == FSM_READY) begin
            bit_cnt <= 0;
        end else if (fsm_state == FSM_RECV && next_bit) begin
            bit_cnt <= bit_cnt + 1'b1;
        end
    end


    always @(posedge clk) begin : p_recieved_data
        if(fsm_state == FSM_RECV && next_bit) begin
            recieved_data <= {bit_sample, recieved_data[PAYLOAD_BITS-1:1]};
        end
    end


    always @(posedge clk) begin : p_bit_sample
        if(!resetn) begin
            bit_sample <= 1'b0;
        end else if (mid_bit) begin
            bit_sample <= rxd_reg[0];
        end
    end

    always @(posedge clk) begin : p_cycle_counter
        if(!resetn) begin
            cycle_counter <= 0;
        end else if(next_bit || fsm_state == FSM_IDLE || fsm_state == FSM_READY) begin
            cycle_counter <= 0;
        end else begin
            cycle_counter <= cycle_counter + 1'b1;
        end
    end

    always @(posedge clk) begin : p_rts
        if (!resetn) begin
            uart_rts <= 1'b1;
        end else begin
            uart_rts <= (fsm_state == FSM_RECV || fsm_state == FSM_STOP || fsm_state == FSM_READY);
        end
    end

    always @(posedge clk) begin : p_rxd_reg
        if(!resetn) begin
            rxd_reg     <= 2'b11;
        end else begin
            rxd_reg     <= {uart_rxd, rxd_reg[1]};
        end
    end
endmodule
