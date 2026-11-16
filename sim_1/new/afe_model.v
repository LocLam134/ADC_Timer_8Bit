// =====================================================================
//  FILE        : tb/afe_model.v
//  MODULE      : afe_model
//  DESCRIPTION : Behavioral Analog Front-End (4-ch Mux, S&H, DAC, Comp)
// =====================================================================
`timescale 1ns/1ps

module afe_model (
    input  wire       adc_sample,
    input  wire [1:0] adc_ch,
    input  wire [7:0] adc_dac,
    output wire       adc_cmp
);

    localparam real VREF = 3.3;
    localparam real LSB  = VREF / 256.0;

    real vin_ch [0:3];
    real vhold;
    real vdac;

    initial begin
        vin_ch[0] = 0.400; // code 31  (0x1F)
        vin_ch[1] = 1.111; // code 86  (0x56)
        vin_ch[2] = 2.000; // code 155 (0x9B)
        vin_ch[3] = 3.000; // code 232 (0xE8)
        vhold     = 0.0;
    end

    // Track input when adc_sample is high, hold when it falls
    always @(*) begin
        if (adc_sample) begin
            vhold = vin_ch[adc_ch];
        end
    end

    always @(*) begin
        vdac = adc_dac * LSB;
    end

    // Comparator output: 1 when held voltage is at or above DAC trial voltage
    assign adc_cmp = (vhold >= vdac);

endmodule