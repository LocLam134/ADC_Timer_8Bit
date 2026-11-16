// =====================================================================
//  FILE        : rtl/periph/sar_adc_ctrl.v
//  MODULE      : sar_adc_ctrl
//  DESCRIPTION : 8-bit 4-Channel SAR ADC Controller with Clock Divider,
//                Sample Window, and Window Watchdog Comparator
// =====================================================================
`timescale 1ns/1ps

module sar_adc_ctrl (
    input  wire       clk,
    input  wire       rst_n,        // Asynchronous active-low reset
    // Control & configuration
    input  wire       adc_en,       // ADC_CTRL[0]
    input  wire       sw_start,     // 1-clock pulse from ADC_CTRL[1] write
    input  wire [1:0] trig_sel,     // ADC_CTRL[3:2]: 0=SW, 1=TMR_OVF, 2=TMR_CMP, 3=CONT
    input  wire [1:0] cfg_ch,       // ADC_CTRL[5:4]: Channel select (0..3)
    input  wire [7:0] smp_len,      // ADC_SMP      : Sample clocks = smp_len + 1
    input  wire [7:0] clk_div,      // ADC_DIV      : ADC step every (clk_div + 1) clocks
    input  wire [7:0] thr_lo,       // ADC_THR_LO   : Window low threshold
    input  wire [7:0] thr_hi,       // ADC_THR_HI   : Window high threshold
    // Timer triggers
    input  wire       tmr_ovf,
    input  wire       tmr_cmp,
    // Status & FIFO interface
    output wire       busy,
    output reg        eoc_pulse,    // End of conversion pulse (pushes FIFO)
    output reg        wd_pulse,     // Window watchdog violation pulse
    output reg  [7:0] conv_data,    // Final 8-bit conversion result
    output reg  [1:0] conv_ch,      // Channel of the completed conversion
    // Analog Front-End (AFE) interface
    output reg        adc_sample,   // 1 = S&H switch closed
    output reg  [1:0] adc_ch,       // Active analog multiplexer channel
    output reg  [7:0] adc_dac,      // 8-bit SAR DAC trial code
    input  wire       adc_cmp       // 1 if Vin >= Vdac (or Vdac <= Vin)
);

    localparam [1:0] ST_IDLE    = 2'd0,
                     ST_SAMPLE  = 2'd1,
                     ST_CONVERT = 2'd2,
                     ST_DONE    = 2'd3;

    reg [1:0] state;
    reg [7:0] div_cnt;
    reg [7:0] smp_cnt;
    reg [2:0] bit_idx;
    reg [7:0] sar_reg;

    wire hw_trig = (trig_sel == 2'd1) ? tmr_ovf :
                   (trig_sel == 2'd2) ? tmr_cmp :
                   (trig_sel == 2'd3) ? 1'b1    : 1'b0;
  
    wire start_req = adc_en && (sw_start || hw_trig);
    wire step_en   = (div_cnt == clk_div);

    assign busy = (state != ST_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            div_cnt    <= 8'd0;
            smp_cnt    <= 8'd0;
            bit_idx    <= 3'd7;
            sar_reg    <= 8'h00;
            adc_sample <= 1'b0;
            adc_ch     <= 2'd0;
            adc_dac    <= 8'h00;
            conv_data  <= 8'h00;
            conv_ch    <= 2'd0;
            eoc_pulse  <= 1'b0;
            wd_pulse   <= 1'b0;
        end else begin
            eoc_pulse <= 1'b0;
            wd_pulse  <= 1'b0;

            if (!adc_en) begin
                state      <= ST_IDLE;
                adc_sample <= 1'b0;
                adc_dac    <= 8'h00;
                div_cnt    <= 8'd0;
            end else begin
                case (state)
                    ST_IDLE: begin
                        adc_sample <= 1'b0;
                        adc_dac    <= 8'h00;
                        if (start_req) begin
                            adc_ch     <= cfg_ch;
                            conv_ch    <= cfg_ch;
                            adc_sample <= 1'b1;
                            smp_cnt    <= 8'd0;
                            div_cnt    <= 8'd0;
                            state      <= ST_SAMPLE;
                        end
                    end

                    ST_SAMPLE: begin
                        if (div_cnt < clk_div) begin
                            div_cnt <= div_cnt + 8'd1;
                        end else begin
                            div_cnt <= 8'd0;
                            if (smp_cnt < smp_len) begin
                                smp_cnt <= smp_cnt + 8'd1;
                            end else begin
                                adc_sample <= 1'b0; // Freeze S&H
                                bit_idx    <= 3'd7;
                                sar_reg    <= 8'h80;
                                adc_dac    <= 8'h80; // MSB trial first
                                state      <= ST_CONVERT;
                            end
                        end
                    end

                    ST_CONVERT: begin
                        if (div_cnt < clk_div) begin
                            div_cnt <= div_cnt + 8'd1;
                        end else begin
                            div_cnt <= 8'd0;
                            // Resolve current trial bit:
                            // adc_cmp == 1 means Vin >= Vdac (keep bit 1), else clear bit
                            if (bit_idx > 3'd0) begin
                                bit_idx <= bit_idx - 3'd1;
                                if (adc_cmp) begin
                                    sar_reg <= sar_reg | (8'h01 << (bit_idx - 3'd1));
                                    adc_dac <= sar_reg | (8'h01 << (bit_idx - 3'd1));
                                end else begin
                                    sar_reg <= (sar_reg & ~(8'h01 << bit_idx)) | (8'h01 << (bit_idx - 3'd1));
                                    adc_dac <= (sar_reg & ~(8'h01 << bit_idx)) | (8'h01 << (bit_idx - 3'd1));
                                end
                            end else begin
                                // Bit 0 resolved
                                state <= ST_DONE;
                                if (adc_cmp) begin
                                    conv_data <= sar_reg;
                                end else begin
                                    conv_data <= sar_reg & 8'hFE;
                                end
                            end
                        end
                    end

                    ST_DONE: begin
                        eoc_pulse <= 1'b1;
                        if ((conv_data < thr_lo) || (conv_data > thr_hi)) begin
                            wd_pulse <= 1'b1;
                        end
                        adc_dac <= 8'h00;
                        state   <= ST_IDLE;
                    end

                    default: state <= ST_IDLE;
                endcase
            end
        end
    end

endmodule