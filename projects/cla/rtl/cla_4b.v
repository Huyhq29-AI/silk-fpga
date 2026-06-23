module cla_4b 
(
    input [3:0] a,
    input [3:0] b,
    input cin,
    output [3:0] sum,
    output cout 
);
wire [3:0] g,p;
genvar j;
// create g and p
generate 
    for (j = 0; j < 4; j = j + 1)
    begin: create_g_and_p
        assign g[j] = a[j] & b[j];
        assign p[j] = a[j] ^ b[j];
    end 
endgenerate
// cout
// khong lam kieu nay, mac du function van dung
// wire [4:0] c;
// assign c[0] = cin;
// assign c[1]   = g[0] | (p[0] & c[0]);
// assign c[2]   = g[1] | (p[1] & c[1]);
// assign c[3]   = g[2] | (p[2] & c[2]);
// assign c[4]   = g[3] | (p[3] & c[3]);
// assign cout   = c[4];
// lam nhu ben duoi
wire [4:0] c;
assign c[0] = cin;
assign c[1] = g[0] | (p[0] & cin);
assign c[2] = g[1] | (p[1] & (g[0] | (p[0] & cin)));
assign c[3] = g[2] | (p[2] & (g[1] | (p[1] & (g[0] | (p[0] & cin)))));
assign c[4] = g[3] | (p[3] & (g[2] | (p[2] & (g[1] | (p[1] & (g[0] | (p[0] & cin)))))));
assign cout = c[4];
// create sum
genvar l;
generate 
    for (l = 0; l < 4; l = l + 1)
    begin: create_sum
        assign sum[l] =  p[l] ^ c[l];
    end 
endgenerate

endmodule
