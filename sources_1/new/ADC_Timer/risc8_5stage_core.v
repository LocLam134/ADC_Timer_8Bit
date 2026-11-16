// =====================================================================
//  FILE        : rtl/risc8_5stage_core.v
//  MODULE      : risc8_5stage_core
//  DESCRIPTION : 8-bit 5-Stage Pipelined RISC CPU with Memory-Mapped I/O
// =====================================================================
`timescale 1ns/1ps

module risc8_5stage_core #(
    parameter       IMEM_FILE = "soc_demo.mem", // passed down to imem
    parameter       IO_ENABLE = 0,             // 1 = map I/O page to io_* port
    parameter [3:0] IO_PAGE   = 4'hF           // I/O page addresses IO_PAGE:0..F
) (
    input  wire       clk,        // system clock
    input  wire       rst,        // synchronous reset, active high
    output reg        halted,     // 1 after HLT has left the pipeline
    output wire [7:0] pc_out,     // current PC (debug output)
    output wire [1:0] flags_out,  // {Z, C} status flags (debug output)
    output wire       instr_done, // 1 when an instruction completes WB

    // I/O port (memory-mapped peripherals, used in Stage 4 MEM)
    output wire       io_cs,      // 1 = LD/ST to the I/O page this clock
    output wire       io_we,      // 1 = store, 0 = load
    output wire [3:0] io_addr,    // register number inside the page
    output wire [7:0] io_wdata,   // store data
    input  wire [7:0] io_rdata    // load data from the peripheral
);

    // =================================================================
    //  STAGE 1 : INSTRUCTION FETCH (IF)
    // =================================================================
    reg  [7:0]  pc;
    wire [15:0] if_instr;

    imem #(.INIT_FILE(IMEM_FILE)) u_imem (
        .addr  (pc),
        .instr (if_instr)
    );

    reg [15:0] ifid_instr;
    reg        ifid_valid;

    // =================================================================
    //  STAGE 2 : INSTRUCTION DECODE (ID)
    // =================================================================
    wire [3:0] id_opcode = ifid_instr[15:12];
    wire [2:0] id_rd     = ifid_instr[11:9];
    wire [2:0] id_rs1    = ifid_instr[8:6];
    wire [2:0] id_rs2    = ifid_instr[5:3];
    wire [7:0] id_imm8   = ifid_instr[7:0];

    wire [2:0] id_alu_op;
    wire id_alu_src_imm, id_ra_is_rd, id_rb_is_rd, id_uses_a, id_uses_b,
         id_reg_we, id_mem_to_reg, id_mem_we, id_flag_we,
         id_jump, id_br_z, id_br_nz, id_halt;

    control_unit u_ctrl (
        .opcode      (id_opcode),
        .alu_op      (id_alu_op),
        .alu_src_imm (id_alu_src_imm),
        .ra_is_rd    (id_ra_is_rd),
        .rb_is_rd    (id_rb_is_rd),
        .uses_a      (id_uses_a),
        .uses_b      (id_uses_b),
        .reg_we      (id_reg_we),
        .mem_to_reg  (id_mem_to_reg),
        .mem_we      (id_mem_we),
        .flag_we     (id_flag_we),
        .jump        (id_jump),
        .br_z        (id_br_z),
        .br_nz       (id_br_nz),
        .halt        (id_halt)
    );

    wire [2:0] id_ra_addr = id_ra_is_rd ? id_rd : id_rs1;
    wire [2:0] id_rb_addr = id_rb_is_rd ? id_rd : id_rs2;
    wire [7:0] id_ra_data, id_rb_data;

    reg        memwb_valid;
    reg        memwb_reg_we;
    reg  [2:0] memwb_rd;
    reg  [7:0] memwb_data;
    reg        memwb_halt;
    wire [7:0] wb_data = memwb_data;

    regfile u_rf (
        .clk     (clk),
        .rst     (rst),
        .ra_addr (id_ra_addr), .ra_data (id_ra_data),
        .rb_addr (id_rb_addr), .rb_data (id_rb_data),
        .we      (memwb_reg_we),
        .wr_addr (memwb_rd),
        .wr_data (wb_data)
    );

    reg        idex_valid;
    reg  [2:0] idex_alu_op;
    reg        idex_alu_src_imm, idex_uses_a, idex_uses_b;
    reg        idex_reg_we, idex_mem_to_reg, idex_mem_we, idex_flag_we;
    reg        idex_jump, idex_br_z, idex_br_nz, idex_halt;
    reg  [2:0] idex_rd, idex_ra_addr, idex_rb_addr;
    reg  [7:0] idex_ra_data, idex_rb_data, idex_imm;

    reg        exmem_valid;
    reg        exmem_reg_we, exmem_mem_to_reg, exmem_mem_we, exmem_halt;
    reg  [2:0] exmem_rd;
    reg  [7:0] exmem_alu_y;
    reg  [7:0] exmem_addr;
    reg  [7:0] exmem_store_data;

    // =================================================================
    //  HAZARD UNIT
    // =================================================================
    wire [1:0] fwd_a_sel, fwd_b_sel;
    wire       stall;

    hazard_unit u_hazard (
        .id_valid       (ifid_valid),
        .id_ra_addr     (id_ra_addr),
        .id_rb_addr     (id_rb_addr),
        .id_uses_a      (id_uses_a),
        .id_uses_b      (id_uses_b),
        .ex_valid       (idex_valid),
        .ex_mem_to_reg  (idex_mem_to_reg),
        .ex_rd          (idex_rd),
        .ex_ra_addr     (idex_ra_addr),
        .ex_rb_addr     (idex_rb_addr),
        .ex_uses_a      (idex_uses_a),
        .ex_uses_b      (idex_uses_b),
        .mem_reg_we     (exmem_reg_we),
        .mem_mem_to_reg (exmem_mem_to_reg),
        .mem_rd         (exmem_rd),
        .wb_reg_we      (memwb_reg_we),
        .wb_rd          (memwb_rd),
        .fwd_a_sel      (fwd_a_sel),
        .fwd_b_sel      (fwd_b_sel),
        .stall          (stall)
    );

    // =================================================================
    //  STAGE 3 : EXECUTE (EX)
    // =================================================================
    wire [7:0] ex_opA = (fwd_a_sel == 2'b10) ? exmem_alu_y :
                        (fwd_a_sel == 2'b01) ? wb_data     : idex_ra_data;
    wire [7:0] ex_opB = (fwd_b_sel == 2'b10) ? exmem_alu_y :
                        (fwd_b_sel == 2'b01) ? wb_data     : idex_rb_data;

    wire [7:0] ex_alu_b = idex_alu_src_imm ? idex_imm : ex_opB;
    wire [7:0] ex_alu_y;
    wire       ex_alu_c, ex_alu_z;

    alu u_alu (
        .a      (ex_opA),
        .b      (ex_alu_b),
        .alu_op (idex_alu_op),
        .y      (ex_alu_y),
        .c      (ex_alu_c),
        .z      (ex_alu_z)
    );

    reg flag_z, flag_c;

    wire take_branch = idex_valid &&
                       (idex_jump || (idex_br_z && flag_z) || (idex_br_nz && !flag_z));
    wire [7:0] branch_target = idex_imm;

    wire ex_halt = idex_valid && idex_halt;
    reg  draining;
    wire fetch_stop = draining || ex_halt;

    // =================================================================
    //  STAGE 4 : MEMORY ACCESS (MEM) & I/O PAGE DECODE
    // =================================================================
    wire [7:0] mem_rdata;
    wire       mem_we = exmem_mem_we && !halted; // already gated by 'valid'

    // Address decode: data RAM or I/O page
    wire io_hit = (IO_ENABLE != 0) && (exmem_addr[7:4] == IO_PAGE);

    assign io_cs    = io_hit && (exmem_mem_we || exmem_mem_to_reg) && !halted;
    assign io_we    = exmem_mem_we;
    assign io_addr  = exmem_addr[3:0];
    assign io_wdata = exmem_store_data;

    dmem u_dmem (
        .clk   (clk),
        .we    (mem_we && !io_hit), // RAM is not written for the I/O page
        .addr  (exmem_addr),
        .wdata (exmem_store_data),
        .rdata (mem_rdata)
    );

    // Data returned by LD: peripheral for the I/O page, RAM otherwise.
    wire [7:0] ld_data    = io_hit ? io_rdata : mem_rdata;
    wire [7:0] mem_result = exmem_mem_to_reg ? ld_data : exmem_alu_y;

    // =================================================================
    //  SEQUENTIAL LOGIC : all pipeline registers, PC, flags, halt
    // =================================================================
    always @(posedge clk) begin
        if (rst) begin
            pc               <= 8'h00;
            ifid_instr       <= 16'h0000;
            ifid_valid       <= 1'b0;
            idex_valid       <= 1'b0;
            idex_alu_op      <= 3'd0;
            idex_alu_src_imm <= 1'b0;
            idex_uses_a      <= 1'b0;
            idex_uses_b      <= 1'b0;
            idex_reg_we      <= 1'b0;
            idex_mem_to_reg  <= 1'b0;
            idex_mem_we      <= 1'b0;
            idex_flag_we     <= 1'b0;
            idex_jump        <= 1'b0;
            idex_br_z        <= 1'b0;
            idex_br_nz       <= 1'b0;
            idex_halt        <= 1'b0;
            idex_rd          <= 3'd0;
            idex_ra_addr     <= 3'd0;
            idex_rb_addr     <= 3'd0;
            idex_ra_data     <= 8'h00;
            idex_rb_data     <= 8'h00;
            idex_imm         <= 8'h00;
            exmem_valid      <= 1'b0;
            exmem_reg_we     <= 1'b0;
            exmem_mem_to_reg <= 1'b0;
            exmem_mem_we     <= 1'b0;
            exmem_halt       <= 1'b0;
            exmem_rd         <= 3'd0;
            exmem_alu_y      <= 8'h00;
            exmem_addr       <= 8'h00;
            exmem_store_data <= 8'h00;
            memwb_valid      <= 1'b0;
            memwb_reg_we     <= 1'b0;
            memwb_rd         <= 3'd0;
            memwb_data       <= 8'h00;
            memwb_halt       <= 1'b0;
            flag_z           <= 1'b0;
            flag_c           <= 1'b0;
            draining         <= 1'b0;
            halted           <= 1'b0;
        end else if (!halted) begin
            // PC and IF/ID
            if (take_branch) begin
                pc         <= branch_target;
                ifid_instr <= 16'h0000;
                ifid_valid <= 1'b0;
            end else if (fetch_stop) begin
                ifid_instr <= 16'h0000;
                ifid_valid <= 1'b0;
            end else if (stall) begin
                // keep PC and IF/ID unchanged
            end else begin
                pc         <= pc + 8'd1;
                ifid_instr <= if_instr;
                ifid_valid <= 1'b1;
            end

            // ID/EX
            if (take_branch || fetch_stop || stall) begin
                idex_valid <= 1'b0;
            end else begin
                idex_valid       <= ifid_valid;
                idex_alu_op      <= id_alu_op;
                idex_alu_src_imm <= id_alu_src_imm;
                idex_uses_a      <= id_uses_a;
                idex_uses_b      <= id_uses_b;
                idex_reg_we      <= id_reg_we;
                idex_mem_to_reg  <= id_mem_to_reg;
                idex_mem_we      <= id_mem_we;
                idex_flag_we     <= id_flag_we;
                idex_jump        <= id_jump;
                idex_br_z        <= id_br_z;
                idex_br_nz       <= id_br_nz;
                idex_halt        <= id_halt;
                idex_rd          <= id_rd;
                idex_ra_addr     <= id_ra_addr;
                idex_rb_addr     <= id_rb_addr;
                idex_ra_data     <= id_ra_data;
                idex_rb_data     <= id_rb_data;
                idex_imm         <= id_imm8;
            end

            // EX/MEM
            exmem_valid      <= idex_valid;
            exmem_reg_we     <= idex_valid && idex_reg_we;
            exmem_mem_to_reg <= idex_valid && idex_mem_to_reg;
            exmem_mem_we     <= idex_valid && idex_mem_we;
            exmem_halt       <= ex_halt;
            exmem_rd         <= idex_rd;
            exmem_alu_y      <= ex_alu_y;
            exmem_addr       <= ex_opA;
            exmem_store_data <= ex_opB;

            if (idex_valid && idex_flag_we) begin
                flag_z <= ex_alu_z;
                flag_c <= ex_alu_c;
            end

            if (ex_halt) draining <= 1'b1;

            // MEM/WB
            memwb_valid  <= exmem_valid;
            memwb_reg_we <= exmem_reg_we;
            memwb_rd     <= exmem_rd;
            memwb_data   <= mem_result;
            memwb_halt   <= exmem_halt;

            if (memwb_halt) halted <= 1'b1;
        end else begin
            memwb_reg_we <= 1'b0;
        end
    end

    assign pc_out     = pc;
    assign flags_out  = {flag_z, flag_c};
    assign instr_done = memwb_valid;

endmodule