// =====================================================================
//  FILE        : rtl/periph/apb_regs8.v
//  MODULE      : apb_regs8
//  DESCRIPTION : 16-Byte Register File (0x0..0xF) with W1C IRQ Flags
// =====================================================================
`timescale 1ns/1ps

module apb_regs8 (
    input  wire       clk,
    input  wire       rst_n,
    // CPU Bus Interface
    input  wire       cs,
    input  wire       we,
    input  wire [3:0] addr,
    input  wire [7:0] wdata,
    output reg  [7:0] rdata,
    // Timer Configuration & Status
    output reg  [7:0] tmr_ctrl,
    output reg  [7:0] tmr_presc,
    output reg  [7:0] tmr_load,
    output reg  [7:0] tmr_cmp,
    input  wire [7:0] tmr_cnt,
    // ADC Configuration & Status
    output reg  [7:0] adc_ctrl,
    output wire       adc_sw_start,
    output reg  [7:0] adc_smp,
    output reg  [7:0] adc_div,
    output reg  [7:0] adc_thr_lo,
    output reg  [7:0] adc_thr_hi,
    input  wire [7:0] fifo_data,
    input  wire [1:0] fifo_ch,
    input  wire [3:0] fifo_level,
    input  wire       fifo_empty,
    input  wire       fifo_full,
    input  wire       adc_busy,
    output wire       fifo_pop,
    // Interrupt events & output
    input  wire       ev_tmr_ovf,   // bit 0
    input  wire       ev_tmr_cmp,   // bit 1
    input  wire       ev_adc_eoc,   // bit 2
    input  wire       ev_adc_wd,    // bit 3
    input  wire       ev_fifo_ovr,  // bit 4
    output wire       irq
);

    localparam [3:0] ADDR_TMR_CTRL   = 4'h0,
                     ADDR_TMR_PRESC  = 4'h1,
                     ADDR_TMR_LOAD   = 4'h2,
                     ADDR_TMR_CMP    = 4'h3,
                     ADDR_TMR_CNT    = 4'h4,
                     ADDR_ADC_CTRL   = 4'h5,
                     ADDR_ADC_SMP    = 4'h6,
                     ADDR_ADC_DIV    = 4'h7,
                     ADDR_ADC_THR_LO = 4'h8,
                     ADDR_ADC_THR_HI = 4'h9,
                     ADDR_ADC_DATA   = 4'hA,
                     ADDR_ADC_RCH    = 4'hB,
                     ADDR_ADC_STAT   = 4'hC,
                     ADDR_IRQ_EN     = 4'hD,
                     ADDR_IRQ_STAT   = 4'hE,
                     ADDR_ID         = 4'hF;

    reg [7:0] irq_en;
    reg [7:0] irq_stat;

    // Single-cycle pulse when writing 1 to ADC_CTRL[1] (START)
    assign adc_sw_start = cs && we && (addr == ADDR_ADC_CTRL) && wdata[1];

    // Reading ADC_DATA (0xA) pops the FIFO
    assign fifo_pop = cs && !we && (addr == ADDR_ADC_DATA);

    wire [7:0] adc_rch_val  = {!fifo_empty, 5'd0, fifo_ch};
    wire [7:0] adc_stat_val = {1'b0, adc_busy, fifo_full, fifo_empty, fifo_level};
    wire [7:0] hw_events    = {3'b000, ev_fifo_ovr, ev_adc_wd, ev_adc_eoc, ev_tmr_cmp, ev_tmr_ovf};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tmr_ctrl   <= 8'h00;
            tmr_presc  <= 8'h00;
            tmr_load   <= 8'hFF;
            tmr_cmp    <= 8'h00;
            adc_ctrl   <= 8'h00;
            adc_smp    <= 8'h03;
            adc_div    <= 8'h00;
            adc_thr_lo <= 8'h00;
            adc_thr_hi <= 8'hFF;
            irq_en     <= 8'h00;
            irq_stat   <= 8'h00;
        end else begin
            // Default W1C + hardware event latching for IRQ_STAT
            if (cs && we && (addr == ADDR_IRQ_STAT)) begin
                irq_stat <= (irq_stat & ~wdata) | hw_events;
            end else begin
                irq_stat <= irq_stat | hw_events;
            end

            // Register writes
            if (cs && we) begin
                case (addr)
                    ADDR_TMR_CTRL  : tmr_ctrl   <= wdata;
                    ADDR_TMR_PRESC : tmr_presc  <= wdata;
                    ADDR_TMR_LOAD  : tmr_load   <= wdata;
                    ADDR_TMR_CMP   : tmr_cmp    <= wdata;
                    ADDR_ADC_CTRL  : adc_ctrl   <= {wdata[7:2], 1'b0, wdata[0]}; // bit 1 is self-clearing START
                    ADDR_ADC_SMP   : adc_smp    <= wdata;
                    ADDR_ADC_DIV   : adc_div    <= wdata;
                    ADDR_ADC_THR_LO: adc_thr_lo <= wdata;
                    ADDR_ADC_THR_HI: adc_thr_hi <= wdata;
                    ADDR_IRQ_EN    : irq_en     <= wdata;
                    default        : ;
                endcase
            end
        end
    end

    // Combinational Read Mux (0-wait-state)
    always @(*) begin
        case (addr)
            ADDR_TMR_CTRL  : rdata = tmr_ctrl;
            ADDR_TMR_PRESC : rdata = tmr_presc;
            ADDR_TMR_LOAD  : rdata = tmr_load;
            ADDR_TMR_CMP   : rdata = tmr_cmp;
            ADDR_TMR_CNT   : rdata = tmr_cnt;
            ADDR_ADC_CTRL  : rdata = adc_ctrl;
            ADDR_ADC_SMP   : rdata = adc_smp;
            ADDR_ADC_DIV   : rdata = adc_div;
            ADDR_ADC_THR_LO: rdata = adc_thr_lo;
            ADDR_ADC_THR_HI: rdata = adc_thr_hi;
            ADDR_ADC_DATA  : rdata = fifo_data;
            ADDR_ADC_RCH   : rdata = adc_rch_val;
            ADDR_ADC_STAT  : rdata = adc_stat_val;
            ADDR_IRQ_EN    : rdata = irq_en;
            ADDR_IRQ_STAT  : rdata = irq_stat;
            ADDR_ID        : rdata = 8'hA8;
            default        : rdata = 8'h00;
        endcase
    end

    assign irq = |(irq_stat & irq_en);

endmodule