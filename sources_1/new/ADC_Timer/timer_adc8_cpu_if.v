// =====================================================================
//  FILE        : rtl/periph/timer_adc8_cpu_if.v
//  MODULE      : timer_adc8_cpu_if
//  DESCRIPTION : CPU Bus Wrapper for Timer + 8-bit SAR ADC Peripheral
// =====================================================================
`timescale 1ns/1ps

module timer_adc8_cpu_if (
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

    timer_adc8_top u_top (
        .clk        (clk),
        .rst_n      (rst_n),
        .cs         (cs),
        .we         (we),
        .addr       (addr),
        .wdata      (wdata),
        .rdata      (rdata),
        .irq        (irq),
        .adc_sample (adc_sample),
        .adc_ch     (adc_ch),
        .adc_dac    (adc_dac),
        .adc_cmp    (adc_cmp),
        .pwm_out    (pwm_out)
    );

endmodule
