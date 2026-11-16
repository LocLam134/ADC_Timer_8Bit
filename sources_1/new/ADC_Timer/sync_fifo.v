// =====================================================================
//  FILE        : rtl/periph/sync_fifo.v
//  MODULE      : sync_fifo
//  DESCRIPTION : 8-Entry Synchronous FIFO for {channel[1:0], data[7:0]}
// =====================================================================
`timescale 1ns/1ps

module sync_fifo #(
    parameter WIDTH = 10,
    parameter DEPTH = 8
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             clr,
    input  wire             push,
    input  wire [WIDTH-1:0] din,
    input  wire             pop,
    output wire [WIDTH-1:0] dout,
    output wire             empty,
    output wire             full,
    output reg  [3:0]       level
);

    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [2:0]       wptr;
    reg [2:0]       rptr;
    integer         i;

    assign empty = (level == 4'd0);
    assign full  = (level == 4'd8);
    assign dout  = empty ? {WIDTH{1'b0}} : mem[rptr];

    wire do_push = push && !full;
    wire do_pop  = pop  && !empty;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wptr  <= 3'd0;
            rptr  <= 3'd0;
            level <= 4'd0;
            for (i = 0; i < DEPTH; i = i + 1) mem[i] <= {WIDTH{1'b0}};
        end else if (clr) begin
            wptr  <= 3'd0;
            rptr  <= 3'd0;
            level <= 4'd0;
        end else begin
            if (do_push) begin
                mem[wptr] <= din;
                wptr      <= wptr + 3'd1;
            end
            if (do_pop) begin
                rptr <= rptr + 3'd1;
            end
            case ({do_push, do_pop})
                2'b10: level <= level + 4'd1;
                2'b01: level <= level - 4'd1;
                default: level <= level;
            endcase
        end
    end

endmodule