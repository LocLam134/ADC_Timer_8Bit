// =====================================================================
//  FILE        : rtl/periph/timer8.v
//  MODULE      : timer8
//  DESCRIPTION : 8-bit Timer with Prescaler, One-Shot, Compare & PWM
// =====================================================================
`timescale 1ns/1ps

module timer8 (
    input  wire       clk,
    input  wire       rst_n,        // Asynchronous active-low reset
    input  wire       en,           // TMR_CTRL[0]: Timer Enable
    input  wire       oneshot,      // TMR_CTRL[1]: One-shot mode
    input  wire [7:0] presc,        // TMR_PRESC  : Tick every (presc + 1) clocks
    input  wire [7:0] load,         // TMR_LOAD   : Period - 1 (wrap value)
    input  wire [7:0] cmp,          // TMR_CMP    : Compare / PWM duty threshold
    output reg  [7:0] cnt,          // TMR_CNT    : Current counter value
    output reg        ovf_pulse,    // 1-clock pulse on counter wrap
    output reg        cmp_pulse,    // 1-clock pulse on cnt == cmp
    output wire       pwm_out       // PWM output: high when en && (cnt < cmp)
);

    reg [7:0] pre_cnt;
    reg       stopped_oneshot;

    wire tick = en && !stopped_oneshot && (pre_cnt == presc);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pre_cnt         <= 8'd0;
            cnt             <= 8'd0;
            ovf_pulse       <= 1'b0;
            cmp_pulse       <= 1'b0;
            stopped_oneshot <= 1'b0;
        end else begin
            ovf_pulse <= 1'b0;
            cmp_pulse <= 1'b0;

            if (!en) begin
                pre_cnt         <= 8'd0;
                cnt             <= 8'd0;
                stopped_oneshot <= 1'b0;
            end else if (!stopped_oneshot) begin
                if (pre_cnt < presc) begin
                    pre_cnt <= pre_cnt + 8'd1;
                end else begin
                    pre_cnt <= 8'd0;

                    // Compare match check on tick
                    if (cnt == cmp) begin
                        cmp_pulse <= 1'b1;
                    end

                    // Counter progression & wrap
                    if (cnt < load) begin
                        cnt <= cnt + 8'd1;
                    end else begin
                        cnt       <= 8'd0;
                        ovf_pulse <= 1'b1;
                        if (oneshot) begin
                            stopped_oneshot <= 1'b1;
                        end
                    end
                end
            end
        end
    end

    assign pwm_out = en && !stopped_oneshot && (cnt < cmp);

endmodule