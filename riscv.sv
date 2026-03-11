module top(
    input  logic        clk,
    output logic [31:0] WriteData, DataAdr,
    output logic        MemWrite,
    output logic [9:0]  LEDR,
    output logic [31:0] HEX3HEX0,
    output logic [15:0] HEX5HEX4,
    input  logic [9:0]  SW,
    input  logic [1:0]  KEY
);

    localparam logic [31:0] LEDR_BASE      = 32'hFF200000;
    localparam logic [31:0] HEX3_HEX0_BASE = 32'hFF200020;
    localparam logic [31:0] HEX5_HEX4_BASE = 32'hFF200030;
    localparam logic [31:0] SW_BASE        = 32'hFF200040;

    logic [31:0] PC, Instr;
    logic [31:0] dmem_read;
    logic [31:0] cpu_read;
    logic [31:0] ReadData;

    // active-high reset from active-low KEY[0]
    logic reset;
    assign reset = ~KEY[0];

    // value returned to CPU on loads
    assign ReadData = cpu_read;

    // instantiate processor and memories
    riscvsingle rvsingle(
        clk, reset,
        PC, Instr, MemWrite,
        DataAdr, WriteData, ReadData
    );

    imem imem(PC, Instr);
    dmem dmem(clk, MemWrite, DataAdr, WriteData, dmem_read);

    // input mux: switches vs data memory
    always_comb begin
        if (DataAdr == SW_BASE)
            cpu_read = {22'b0, SW};   // SW[9:0] in low bits
        else
            cpu_read = dmem_read;
    end

    // output registers: LEDs and HEX displays
    always_ff @(posedge clk) begin
        if (reset) begin
            LEDR     <= '0;
            HEX3HEX0 <= '0;
            HEX5HEX4 <= '0;
        end
        else if (MemWrite) begin
            unique case (DataAdr)
                LEDR_BASE: begin
                    LEDR <= WriteData[9:0];
                end
                HEX3_HEX0_BASE: begin
                    HEX3HEX0 <= WriteData;
                end
                HEX5_HEX4_BASE: begin
                    HEX5HEX4 <= WriteData[15:0];
                end
                default: ; // do nothing
            endcase
        end
    end

endmodule

module riscvsingle( input  logic  clk, reset,
                    output logic [31:0] PC,
                    input  logic [31:0] Instr,
                    output logic        MemWrite,
                    output logic [31:0] ALUResult, WriteData,
                    input  logic [31:0] ReadData);

logic ALUSrc, RegWrite, Jump, Zero, PCSrc;
logic [1:0] ResultSrc, ImmSrc;
logic [2:0] ALUControl;

// Controller Instance
controller c(Instr[6:0], Instr[14:12], Instr[30], Zero,
             ResultSrc, MemWrite, PCSrc,
             ALUSrc, RegWrite, Jump,
             ImmSrc, ALUControl);

// datapath is the hardware that moves and processes data
datapath dp(clk, reset, ResultSrc, PCSrc,
            ALUSrc, RegWrite,
            ImmSrc, ALUControl,
            Zero, PC, Instr,
            ALUResult, WriteData, ReadData);
endmodule

// Controller module
module controller(input logic [6:0]  op,
                  input logic [2:0]  funct3,
                  input logic        funct7b5,
                  input logic        Zero,
                  output logic [1:0] ResultSrc,
                  output logic       MemWrite,
                  output logic       PCSrc, ALUSrc,
                  output logic       RegWrite, Jump,
                  output logic [1:0] ImmSrc,
                  output logic [2:0] ALUControl);
    logic [1:0] ALUOp;
    logic       Branch;

    maindec md(op, ResultSrc, MemWrite, Branch,
               ALUSrc, RegWrite, Jump, ImmSrc, ALUOp);

    aludec ad(op[5], funct3, funct7b5, ALUOp, ALUControl);

    /* 
    PCSrc is asserted when:
    
      1. Branch instruction AND ALU result is zero (taken branch)
      2. Jump instruction (unconditional)

    Otherwise, PCSrc = 0 and goes to sequential PC (PC+4)
    */
    assign PCSrc = Branch & Zero | Jump;
endmodule

// Main decoder
module maindec( input  logic [6:0] op,
                output logic [1:0] ResultSrc,
                output logic       MemWrite,
                output logic       Branch, ALUSrc,
                output logic       RegWrite, Jump,
                output logic [1:0] ImmSrc,
                output logic [1:0] ALUOp);

logic [10:0] controls;

assign {RegWrite, ImmSrc, ALUSrc, MemWrite,
        ResultSrc, Branch, ALUOp, Jump} = controls;

always_comb 
    case(op)
        7'b0000011: controls = 11'b1_00_1_0_01_0_00_0; // lw
        7'b0100011: controls = 11'b0_01_1_1_00_0_00_0; // sw
        7'b0110011: controls = 11'b1_xx_0_0_00_0_10_0; // R-type
        7'b1100011: controls = 11'b0_10_0_0_00_1_01_0; // beq
        7'b0010011: controls = 11'b1_00_1_0_00_0_10_0; // I-type ALU
        7'b1101111: controls = 11'b1_11_0_0_10_0_00_1; // jal
        default:    controls = 11'bx_xx_x_x_xx_x_xx_x; // ???
    endcase
endmodule

// ALUDecoder
module aludec(input  logic       opb5,
              input  logic [2:0] funct3,
              input  logic       funct7b5,
              input  logic [1:0] ALUOp,
              output logic [2:0] ALUControl);

logic RtypeSub;

assign RtypeSub = funct7b5 & opb5; // TRUE for R-type subtract

always_comb
    case(ALUOp)
        2'b00:          ALUControl = 3'b000; // addition
        2'b01:          ALUControl = 3'b001; // subtraction

        default: case(funct3)
                    3'b000: if (RtypeSub)
                                ALUControl = 3'b001; // sub
                            else
                                ALUControl = 3'b000; // add, addi
                    3'b010:     ALUControl = 3'b101; // slt, slti
                    3'b110:     ALUControl = 3'b011; // or, ori
                    3'b111:     ALUControl = 3'b010; // and, andi
                    default:    ALUControl = 3'bxxx; // ???
                  endcase
    endcase
endmodule

// Datapath
module datapath(input  logic        clk, reset,
                input  logic [1:0]  ResultSrc,
                input  logic        PCSrc, ALUSrc,
                input  logic        RegWrite,
                input  logic [1:0]  ImmSrc,
                input  logic [2:0]  ALUControl,
                output logic        Zero,
                output logic [31:0] PC,
                input  logic [31:0] Instr,
                output logic [31:0] ALUResult, WriteData,
                input  logic [31:0] ReadData);

    logic [31:0] PCNext, PCPlus4, PCTarget;
    logic [31:0] ImmExt;
    logic [31:0] SrcA, SrcB;
    logic [31:0] Result;

    // next PC logic
    flopr #(32) pcreg(clk, reset, PCNext, PC);
    adder       pcadd4(PC, 32'd4, PCPlus4);
    adder       pcaddbranch(PC, ImmExt, PCTarget);
    mux2 #(32)  pcmux(PCPlus4, PCTarget, PCSrc, PCNext);

    // register file logic
    regfile     rf(clk, RegWrite, Instr[19:15], Instr[24:20],
                   Instr[11:7], Result, SrcA, WriteData);
    extend      ext(Instr[31:7], ImmSrc, ImmExt);

    // ALU logic
    mux2 #(32)  srcbmux(WriteData, ImmExt, ALUSrc, SrcB);
    alu         alu(SrcA, SrcB, ALUControl, ALUResult, Zero);
    mux3 #(32)  resultmux(ALUResult, ReadData, PCPlus4, ResultSrc, Result);
endmodule

// Adder
module adder(input [31:0]  a,b, 
             output [31:0] y);

    assign y = a + b;
endmodule

// Extend Unit
module extend(
    input  logic [31:7] instr,
    input  logic [1:0]  immsrc,
    output logic [31:0] immext
);

    always_comb
        case (immsrc)

            // I-type
            2'b00: immext = {{20{instr[31]}}, instr[31:20]};

            // S-type (stores)
            2'b01: immext = {{20{instr[31]}}, instr[31:25], instr[11:7]};

            // B-type (branches)
            2'b10: immext = {{20{instr[31]}}, instr[7], instr[30:25],
                             instr[11:8], 1'b0};

            // J-type (jal)
            2'b11: immext = {{12{instr[31]}}, instr[19:12], instr[20],
                             instr[30:21], 1'b0};

            default: immext = 32'bx;   // undefined

        endcase
endmodule

// Resettable flip-flop
module flopr #(parameter WIDTH = 8) (
    input  logic               clk, reset,
    input  logic [WIDTH-1:0]   d,
    output logic [WIDTH-1:0]   q
);

    always_ff @(posedge clk, posedge reset)
        if (reset)
            q <= 0;
        else
            q <= d;
endmodule

// Resettable flip-flop with enable
module flopenr #(parameter WIDTH = 8) (
    input  logic               clk, reset, en,
    input  logic [WIDTH-1:0]   d,
    output logic [WIDTH-1:0]   q
);

    always_ff @(posedge clk, posedge reset)
        if (reset)
            q <= 0;
        else if (en)
            q <= d;
endmodule

// 2:1 Multiplexer
module mux2 #(parameter WIDTH = 8) (
    input  logic [WIDTH-1:0] d0, d1,
    input  logic             s,
    output logic [WIDTH-1:0] y
);

    assign y = s ? d1 : d0;

endmodule

// 3:1 Multiplexer
module mux3 #(parameter WIDTH = 8) (
    input  logic [WIDTH-1:0] d0, d1, d2,
    input  logic [1:0]       s,
    output logic [WIDTH-1:0] y
);

    assign y = s[1] ? d2 :
               (s[0] ? d1 : d0);

endmodule

module imem(
    input  logic [31:0] a,
    output logic [31:0] rd
);

    logic [31:0] RAM[63:0];

    initial
        $readmemh("imem.txt", RAM);

    assign rd = RAM[a[31:2]];   // word aligned

endmodule

module dmem(
    input  logic        clk, we,
    input  logic [31:0] a, wd,
    output logic [31:0] rd
);

    logic [31:0] RAM[63:0];

    initial
      $readmemh("dmem.txt", RAM);

    assign rd = RAM[a[31:2]];   // word aligned

    always_ff @(posedge clk)
        if (we)
            RAM[a[31:2]] <= wd;

endmodule

// Register File: 32 x 32, x0 hard-wired to 0
module regfile(
    input  logic        clk,
    input  logic        we3,            // write enable
    input  logic [4:0]  a1, a2, a3,     // read addr1, read addr2, write addr
    input  logic [31:0] wd3,            // write data
    output logic [31:0] rd1, rd2);      // read data

    logic [31:0] rf[31:0];

  	always_ff @(posedge clk)
        if(we3 && (a3 != 5'd0))
            rf[a3] <= wd3;

    assign rd1 = (a1 != 5'd0) ? rf[a1] : 32'd0;
    assign rd2 = (a2 != 5'd0) ? rf[a2] : 32'd0;
endmodule

module alu(input  logic [31:0] a, b,
           input  logic [2:0]  alucontrol,
           output logic [31:0] result,
           output logic        zero);

  logic [31:0] condinvb, sum;
  logic        v;              // overflow
  logic        isAddSub;       // true when is add or subtract operation

  assign condinvb = alucontrol[0] ? ~b : b;
  assign sum = a + condinvb + alucontrol[0];
  assign isAddSub = ~alucontrol[2] & ~alucontrol[1] |
                    ~alucontrol[1] & alucontrol[0];

  always_comb
    case (alucontrol)
      3'b000:  result = sum;         // add
      3'b001:  result = sum;         // subtract
      3'b010:  result = a & b;       // and
      3'b011:  result = a | b;       // or
      3'b100:  result = a ^ b;       // xor
      3'b101:  result = sum[31] ^ v; // slt
      3'b110:  result = a << b[4:0]; // sll
      3'b111:  result = a >> b[4:0]; // srl
      default: result = 32'bx;
    endcase

  assign zero = (result == 32'b0);
  assign v = ~(alucontrol[0] ^ a[31] ^ b[31]) & (a[31] ^ sum[31]) & isAddSub;
  
endmodule