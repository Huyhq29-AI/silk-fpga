module sequence_detector (
    input wire clk,
    input wire rst_n,
    input wire data_in,
    output reg matched
);

   
    reg [1:0] state;
    
    localparam IDLE  = 2'd0; 
    localparam S1    = 2'd1; 
    localparam S10   = 2'd2; 
    localparam S101  = 2'd3; 

    
    always @(posedge clk) begin : fsm_block
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            case (state)
                IDLE: state <= data_in ? S1 : IDLE;
                
                S1:   state <= data_in ? S1 : S10;
                
                S10:  state <= data_in ? S101 : IDLE;
                
                S101: state <= data_in ? S1 : S10; 
                
                default: state <= IDLE;
            endcase
        end
    end

    
    always @(posedge clk) begin : output_block
        if (!rst_n) begin
            matched <= 1'b0;
        end else begin
            // Chỉ bật matched lên 1 khi FSM nằm ở trạng thái S101
            matched <= (state == S101);
        end
    end

endmodule
