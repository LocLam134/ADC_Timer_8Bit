// =====================================================================
//  FILE        : rtl/periph/timer_adc8_top.v
//  MODULE      : timer_adc8_top
//  DESCRIPTION : Interconnects Registers, 8-bit Timer, SAR ADC & FIFO
// =====================================================================
`timescale 1ns/1ps

module timer_adc8_top (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       cs,
    input  wire       we,
    input  wire [3:0] addr,
    input  wire [7:0] wdata,
    output wire [7:0] rdata,
    output wire       irq,
    output wire       adc_sample,
    output wire [1:0] adc_ch,
    output wire [7:0] adc_dac,
    input  wire       adc_cmp,
    output wire       pwm_out
);

    wire [7:0] tmr_ctrl, tmr_presc, tmr_load, tmr_cmp, tmr_cnt;
    wire       tmr_ovf, tmr_cmp_ev;

    wire [7:0] adc_ctrl, adc_smp, adc_div, adc_thr_lo, adc_thr_hi;
    wire       adc_sw_start, adc_busy, adc_eoc, adc_wd;
    wire [7:0] conv_data;
    wire [1:0] conv_ch;

    wire [9:0] fifo_dout;
    wire       fifo_empty, fifo_full, fifo_pop;
    wire [3:0] fifo_level;
    wire       fifo_ovr = adc_eoc && fifo_full;

    apb_regs8 u_regs (
        .clk          (clk),
        .rst_n        (rst_n),
        .cs           (cs),
        .we           (we),
        .addr         (addr),
        .wdata        (wdata),
        .rdata        (rdata),
        .tmr_ctrl     (tmr_ctrl),
        .tmr_presc    (tmr_presc),
        .tmr_load     (tmr_load),
        .tmr_cmp      (tmr_cmp),
        .tmr_cnt      (tmr_cnt),
        .adc_ctrl     (adc_ctrl),
        .adc_sw_start (adc_sw_start),
        .adc_smp      (adc_smp),
        .adc_div      (adc_div),
        .adc_thr_lo   (adc_thr_lo),
        .adc_thr_hi   (adc_thr_hi),
        .fifo_data    (fifo_dout[7:0]),
        .fifo_ch      (fifo_dout[9:8]),
        .fifo_level   (fifo_level),
        .fifo_empty   (fifo_empty),
        .fifo_full    (fifo_full),
        .adc_busy     (adc_busy),
        .fifo_pop     (fifo_pop),
        .ev_tmr_ovf   (tmr_ovf),
        .ev_tmr_cmp   (tmr_cmp_ev),
        .ev_adc_eoc   (adc_eoc),
        .ev_adc_wd    (adc_wd),
        .ev_fifo_ovr  (fifo_ovr),
        .irq          (irq)
    );

    timer8 u_timer (
        .clk       (clk),
        .rst_n     (rst_n),
        .en        (tmr_ctrl[0]),
        .oneshot   (tmr_ctrl[1]),
        .presc     (tmr_presc),
        .load      (tmr_load),
        .cmp       (tmr_cmp),
        .cnt       (tmr_cnt),
        .ovf_pulse (tmr_ovf),
        .cmp_pulse (tmr_cmp_ev),
        .pwm_out   (pwm_out)
    );

 
    wire is_writing_adc_ctrl = (cs && we && (addr == 4'h5));
    wire       next_adc_en   = is_writing_adc_ctrl ? wdata[0]   : adc_ctrl[0];
    wire [1:0] next_trig_sel = is_writing_adc_ctrl ? wdata[3:2] : adc_ctrl[3:2];
    wire [1:0] next_cfg_ch   = is_writing_adc_ctrl ? wdata[5:4] : adc_ctrl[5:4];
    // --------------------------------------------------------------

    sar_adc_ctrl u_adc (
        .clk        (clk),
        .rst_n      (rst_n),
        .adc_en     (next_adc_en),     // Bypassed
        .sw_start   (adc_sw_start),
        .trig_sel   (next_trig_sel),   // Bypassed
        .cfg_ch     (next_cfg_ch),     // Bypassed
        .smp_len    (adc_smp),
        .clk_div    (adc_div),
        .thr_lo     (adc_thr_lo),
        .thr_hi     (adc_thr_hi),
        .tmr_ovf    (tmr_ovf),
        .tmr_cmp    (tmr_cmp_ev),
        .busy       (adc_busy),
        .eoc_pulse  (adc_eoc),
        .wd_pulse   (adc_wd),
        .conv_data  (conv_data),
        .conv_ch    (conv_ch),
        .adc_sample (adc_sample),
        .adc_ch     (adc_ch),
        .adc_dac    (adc_dac),
        .adc_cmp    (adc_cmp)
    );

    sync_fifo #(.WIDTH(10), .DEPTH(8)) u_fifo (
        .clk   (clk),
        .rst_n (rst_n),
        .clr   (!adc_ctrl[0]),
        .push  (adc_eoc),
        .din   ({conv_ch, conv_data}),
        .pop   (fifo_pop),
        .dout  (fifo_dout),
        .empty (fifo_empty),
        .full  (fifo_full),
        .level (fifo_level)
    );

endmodule