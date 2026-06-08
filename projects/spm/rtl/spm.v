module spm(clk, rst, x, y, p);
  parameter size = 32;
  input clk, rst;
  input y;
  input[size-1:0] x;
  output p;

  wire[size-1:1] pp;
  wire[size-1:0] xy;

  genvar i;

  CSADD csa0 (.clk(clk), .rst(rst), .x(x[0]&y), .y(pp[1]), .sum(p));
  generate for(i=1; i<size-1; i=i+1)
    begin
      CSADD csa (.clk(clk), .rst(rst), .x(x[i]&y), .y(pp[i+1]), .sum(pp[i]));
    end
  endgenerate
  TCMP tcmp (.clk(clk), .rst(rst), .a(x[size-1]&y), .s(pp[size-1]));

endmodule

module TCMP(clk, rst, a, s);
  input clk, rst;
  input a;
  output reg s;

  reg z;

  always @(posedge clk or posedge rst)
  begin
    if (rst)
    begin
      //Reset logic goes here.
      s <= 1'b0;
      z <= 1'b0;
    end
    else
    begin
      //Sequential logic goes here.
      z <= a | z;
      s <= a ^ z;
    end
  end
endmodule

module CSADD(clk, rst, x, y, sum);
  input clk, rst;
  input x, y;
  output reg sum;

  reg sc;

  // Half Adders logic
  wire hsum1, hco1;
  assign hsum1 = y ^ sc;
  assign hco1 = y & sc;

  wire hsum2, hco2;
  assign hsum2 = x ^ hsum1;
  assign hco2 = x & hsum1;

  always @(posedge clk or posedge rst)
  begin
    if (rst)
    begin
      //Reset logic goes here.
      sum <= 1'b0;
      sc <= 1'b0;
    end
    else
    begin
      //Sequential logic goes here.
      sum <= hsum2;
      sc <= hco1 ^ hco2;
    end
  end
endmodule


// module spm_with_fa
//   #(parameter size = 16)
//    (
//      input clk,          // clk
//      input rst,          // rst
//      input [size-1:0] a, // first op;
//      input [size-1:0] b, // second op;
//      input start,         // start spm
//      //output valid,       // valid means p is ready
//      output [2*size-1:0] p //spm output
//    );
//   wire [2*size-1:0] product; //output from fa (8b)
//   reg [2*size-1:0] pp; //partial product (8b)
//   wire [2*size-2:0] cout;
//   wire [2*size-2:0] cin;              //carry
//   reg [size-1:0] bshift; // b shift
//   reg [2*size-1:0] ashift; // a shift

//   always @(posedge clk or posedge rst)
//   begin
//     if (rst)
//     begin
//       pp <= 0;
//       bshift <= 0;
//       ashift <= 0;
//     end
//     else if (start)
//     begin
//       bshift <= b; //load b once after start signal
//       ashift <= a; //load a once after start signal
//       pp     <= 0; //reset product
//     end
//     else
//     begin
//       pp <= product; // each clk update product with partial product
//       bshift <= {1'b0,bshift[size-1:1]}; //shift right b each clk
//       ashift <= {ashift[2*size-2:0],1'b0}; //shift left a each clk
//     end
//   end
//   //pp
//   assign product[2*size-1]=cout[2*size-2]; // product 7 is cout 6
//   assign cin[0] = 1'b0;
//   genvar i;
//   generate
//     for (i = 0; i < 2*size -1; i = i + 1 ) //0 to 6 fa
//     begin: create_partial_product
//       if (i < 2*size - 2) begin // max i = 5
//           assign cin[i+1] = cout[i]; // cin[6] need cout[5], cin[5] need cout[4], etc.
//       end
//       fa my_fa((ashift[i]&bshift[0]), pp[i], cin[i], product[i], cout[i]); // max i = 6
//       ////////// a                     b      cin     sum         cout
//     end
//   endgenerate
//   // final p
//   assign p = pp;
// endmodule

// module fa (a,b,cin,sum,cout);
//   input a;
//   input b;
//   input cin;
//   output sum;
//   output cout;
//   wire axorb = a^b;
//   assign sum = axorb ^ cin;
//   assign cout = a&b | axorb & cin;
// endmodule

