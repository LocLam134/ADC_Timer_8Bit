// =====================================================================
//  FILE        : tb/tb_risc8_soc.v
//  MODULE      : tb_risc8_soc
//  DESCRIPTION : System Testbench for RISC-8 SoC (22 Self-Checking Tests)
// =====================================================================
`timescale 1ns/1ps

module tb_risc8_soc;

    reg        clk;
    reg        rst;
    wire       halted;
    wire [7:0] pc_out;
    wire       irq;
    wire       pwm_out;
    wire       adc_sample;
    wire [1:0] adc_ch;
    wire [7:0] adc_dac;
    wire       adc_cmp;

    // Instantiate SoC Top
    risc8_soc #(
        .IMEM_FILE("soc_demo.mem")
    ) dut (
        .clk        (clk),
        .rst        (rst),
        .halted     (halted),
        .pc_out     (pc_out),
        .irq        (irq),
        .pwm_out    (pwm_out),
        .adc_sample (adc_sample),
        .adc_ch     (adc_ch),
        .adc_dac    (adc_dac),
        .adc_cmp    (adc_cmp)
    );

    // Instantiate Behavioral Analog Front-End
    afe_model u_afe (
        .adc_sample (adc_sample),
        .adc_ch     (adc_ch),
        .adc_dac    (adc_dac),
        .adc_cmp    (adc_cmp)
    );

    // 100 MHz clock (10 ns period)
    initial clk = 1'b0;
    always #5 clk = ~clk;

    integer cycle_cnt;
    integer io_access_cnt;
    integer trace_fd;
    integer pass_cnt;
    integer fail_cnt;
    integer pwm_hi_cnt;
    integer i;
    reg     irq_seen_high;

    task check_mem;
        input [7:0]   addr;
        input [7:0]   exp;
        input [255:0] label;
        reg   [7:0]   got;
        begin
            got = dut.u_cpu.u_dmem.mem[addr];
            if (got === exp) begin
                $display("PASS: MEM[%02x] = %02x  %0s", addr, got, label);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL: MEM[%02x] = %02x (expected %02x)  %0s", addr, got, exp, label);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    initial begin
        `ifdef DUMP
            $dumpfile("risc8_soc.vcd");
            $dumpvars(0, tb_risc8_soc);
        `endif

        trace_fd = $fopen("io_trace.csv", "w");
        $fwrite(trace_fd, "cycle,pc,exmem_addr,io_cs,io_we,io_addr,io_wdata,io_rdata\n");

        rst           = 1'b1;
        cycle_cnt     = 0;
        io_access_cnt = 0;
        pass_cnt      = 0;
        fail_cnt      = 0;
        pwm_hi_cnt    = 0;
        irq_seen_high = 1'b0;

        repeat (2) @(posedge clk);
        rst = 1'b0;

        // Run until CPU halts or timeout
        while (!halted && cycle_cnt < 5000) begin
            @(posedge clk);
            cycle_cnt = cycle_cnt + 1;

            if (irq) irq_seen_high = 1'b1;

            if (dut.io_cs) begin
                io_access_cnt = io_access_cnt + 1;
            end

            $fwrite(trace_fd, "%0d,%02x,%02x,%0d,%0d,%01x,%02x,%02x\n",
                    cycle_cnt, pc_out, dut.u_cpu.exmem_addr,
                    dut.io_cs, dut.io_we, dut.io_addr, dut.io_wdata, dut.io_rdata);
        end

        $display("CPU halted after %0d cycles, %0d I/O accesses", cycle_cnt, io_access_cnt);

        // 18 Memory checks (0x80..0x91)
        check_mem(8'h80, 8'hA8, "A: ID register");
        check_mem(8'h81, 8'h81, "B: ADC_RCH = valid, ch1");
        check_mem(8'h82, 8'h56, "B: ch1 code (1.111 V)");
        check_mem(8'h83, 8'h82, "C: ADC_RCH = valid, ch2");
        check_mem(8'h84, 8'h9B, "C: ch2 code (2.0 V), timer start");
        check_mem(8'h85, 8'h82, "C: ADC_RCH = valid, ch2");
        check_mem(8'h86, 8'h9B, "C: ch2 code (2.0 V), timer start");
        check_mem(8'h87, 8'h82, "C: ADC_RCH = valid, ch2");
        check_mem(8'h88, 8'h9B, "C: ch2 code (2.0 V), timer start");
        check_mem(8'h89, 8'h82, "C: ADC_RCH = valid, ch2");
        check_mem(8'h8A, 8'h9B, "C: ch2 code (2.0 V), timer start");
        check_mem(8'h8B, 8'h07, "C: IRQ_STAT = OVF|CMP|EOC");
        check_mem(8'h8C, 8'h03, "C: IRQ_STAT after W1C 0x04");
        check_mem(8'h8D, 8'h0C, "D: IRQ_STAT = EOC|WD");
        check_mem(8'h8E, 8'hE8, "D: ch3 code (3.0 V)");
        check_mem(8'h8F, 8'h1F, "F: 1st pop, ch0 code (0.40 V)");
        check_mem(8'h90, 8'h56, "F: 2nd pop, ch1 code (1.111 V)");
        check_mem(8'h91, 8'h10, "F: ADC_STAT = empty after 2 pops");

        // Check 19 & 20: irq pin rose during Part D and is now cleared (0)
        if (irq_seen_high && (irq === 1'b0)) begin
            $display("PASS: irq pin went high during part D and was cleared");
            pass_cnt = pass_cnt + 2;
        end else begin
            $display("FAIL: irq check (seen_high=%b, current_irq=%b)", irq_seen_high, irq);
            fail_cnt = fail_cnt + 2;
        end

        // Check 21 & 22: Measure PWM over 100 clocks after HLT (expect 30 clocks high)
        for (i = 0; i < 100; i = i + 1) begin
            @(posedge clk);
            if (pwm_out) pwm_hi_cnt = pwm_hi_cnt + 1;
        end

        if (pwm_hi_cnt == 30) begin
            $display("PASS: PWM high for %0d of 100 clocks", pwm_hi_cnt);
            pass_cnt = pass_cnt + 2;
        end else begin
            $display("FAIL: PWM high for %0d of 100 clocks (expected 30)", pwm_hi_cnt);
            fail_cnt = fail_cnt + 2;
        end

        $fclose(trace_fd);

        if (fail_cnt == 0) begin
            $display("*** SOC TEST PASSED *** (%0d checks)", pass_cnt);
        end else begin
            $display("*** SOC TEST FAILED *** (%0d passed, %0d failed)", pass_cnt, fail_cnt);
        end
        $display("==========================================");
        $display("Student Name: Lam Duy Loc");
        $display("Student ID: SE190907");
        $display("==========================================");
        
        $finish;
    end

endmodule