// 2-stage pipelined RISC-V processor for Assignment 4
// Stage 1: IF + ID + EXE
// Stage 2: MEM + WB
//
// Optional: simple data forwarding from Stage 2 -> Stage 1 (ENABLE_FORWARDING=1)

module processor #(
    parameter int WIDTH = 32,
    parameter int NUM_REGS = 32,
    parameter int DATA_WIDTH = 8,
    parameter int MEM_DEPTH = 256,
    parameter bit ENABLE_FORWARDING = 1'b0
) (
    input  logic             clock,
    input  logic             reset,
    input  logic             memEn,
    input  logic [WIDTH-1:0] memData,
    input  logic [WIDTH-1:0] memAddr,
    output logic [WIDTH-1:0] gp,
    output logic [WIDTH-1:0] a7,
    output logic [WIDTH-1:0] a0
);

  localparam int MEM_AW = $clog2(MEM_DEPTH);

  // ------------------------------------
  // Memories and register file
  // ------------------------------------
  logic [DATA_WIDTH-1:0] mainMemory [0:MEM_DEPTH-1];
  logic [WIDTH-1:0]      registers  [0:NUM_REGS-1];

  // ------------------------------------
  // Stage 1 signals (IF/ID/EXE)
  // ------------------------------------
  logic [WIDTH-1:0] pc, next_pc;
  logic [WIDTH-1:0] ins_s1;
  logic [4:0]       rs1_s1, rs2_s1, rd_s1, opcode_s1;
  logic [2:0]       funct3_s1;
  logic [6:0]       funct7_s1;
  logic [WIDTH-1:0] imm_s1;

  logic             isArithmetic_s1, isImm_s1, isMemRead_s1, isLoadUI_s1, isMemWrite_s1;
  logic             isBranch_s1, isJAL_s1, isJALR_s1, isMUL_s1, isAUIPC_s1;
  logic             isBranchR_s1, isBranchC_s1;
  logic             regWriteEn_s1;

  logic [WIDTH-1:0] rs1_val_s1, rs2_val_s1;
  logic [WIDTH-1:0] opA_s1, opB_s1;     // possibly forwarded
  logic [WIDTH-1:0] src1_s1, src2_s1;
  logic [3:0]       aluOp_s1;
  logic [WIDTH-1:0] aluOut_s1;
  logic [WIDTH-1:0] pc_plus4_s1;

  // Truncated instruction fetch address (byte address)
  logic [MEM_AW-1:0] pc_b;
  assign pc_b = pc[MEM_AW-1:0];

  // ------------------------------------
  // Stage 2 pipeline registers (MEM/WB inputs)
  // ------------------------------------
  logic [WIDTH-1:0] aluOut_s2;
  logic [WIDTH-1:0] storeData_s2;
  logic [WIDTH-1:0] pc_plus4_s2;
  logic [2:0]       funct3_s2;
  logic [4:0]       rd_s2;

  logic             isMemRead_s2, isMemWrite_s2;
  logic             isJAL_s2, isJALR_s2;
  logic             regWriteEn_s2;

  // Truncated data memory address (byte address)
  logic [MEM_AW-1:0] alu_b_s2;
  assign alu_b_s2 = aluOut_s2[MEM_AW-1:0];

  // Stage 2 outputs
  logic [WIDTH-1:0] memRead_s2;
  logic [WIDTH-1:0] regDataIn_s2;

  // ------------------------------------
  // Program counter update (Stage 1 decides next PC)
  // ------------------------------------
  always_ff @(posedge clock) begin
    if (reset) pc <= '0;
    else       pc <= next_pc;
  end

  // ------------------------------------
  // Memory programming (used only when memEn=1)
  // Also performs STORE writes from Stage 2 when memEn=0.
  // ------------------------------------
  always_ff @(posedge clock) begin : MemoryUpdate
    if (memEn) begin
      mainMemory[memAddr[MEM_AW-1:0]] <= memData[7:0];
    end else if (isMemWrite_s2) begin
      // Store data formatting (little-endian in byte-addressed memory)
      unique case (funct3_s2)
        3'b000: begin // SB
          mainMemory[alu_b_s2] <= storeData_s2[7:0];
        end
        3'b001: begin // SH
          mainMemory[alu_b_s2]   <= storeData_s2[7:0];
          mainMemory[alu_b_s2+1] <= storeData_s2[15:8];
        end
        3'b010: begin // SW
          mainMemory[alu_b_s2]   <= storeData_s2[7:0];
          mainMemory[alu_b_s2+1] <= storeData_s2[15:8];
          mainMemory[alu_b_s2+2] <= storeData_s2[23:16];
          mainMemory[alu_b_s2+3] <= storeData_s2[31:24];
        end
        default: begin
          // no-op
        end
      endcase
    end
  end

  // ------------------------------------
  // Instruction Fetch (Stage 1)
  // ------------------------------------
  assign ins_s1      = (~memEn) ? {mainMemory[pc_b+3], mainMemory[pc_b+2], mainMemory[pc_b+1], mainMemory[pc_b]} : 32'h00000013;
  assign pc_plus4_s1 = pc + 4;

  // ------------------------------------
  // Decode + Immediate generation (Stage 1)
  // ------------------------------------
  always_comb begin
    {funct7_s1, rs2_s1, rs1_s1, funct3_s1, rd_s1, opcode_s1} = ins_s1[31:2];

    isArithmetic_s1 = (opcode_s1 == 5'b01100) & (funct7_s1[0] == 1'b0);
    isMUL_s1        = (opcode_s1 == 5'b01100) & (funct7_s1[0] == 1'b1); // MUL/DIV group
    isImm_s1        = (opcode_s1 == 5'b00100);
    isMemRead_s1    = (opcode_s1 == 5'b00000);
    isLoadUI_s1     = (opcode_s1 == 5'b01101);
    isMemWrite_s1   = (opcode_s1 == 5'b01000);
    isBranch_s1     = (opcode_s1 == 5'b11000);
    isJAL_s1        = (opcode_s1 == 5'b11011);
    isJALR_s1       = (opcode_s1 == 5'b11001);
    isAUIPC_s1      = (opcode_s1 == 5'b00101);

    // Immediate generation (matches the original processor behavior)
    if (isImm_s1 | isMemRead_s1 | isJALR_s1)         imm_s1 = WIDTH'($signed(ins_s1[31:20]));                                            // I-imm
    else if (isLoadUI_s1 | isAUIPC_s1)               imm_s1 = {ins_s1[31:12], 12'b0};                                                     // U-imm
    else if (isMemWrite_s1)                          imm_s1 = WIDTH'($signed({ins_s1[31:25], ins_s1[11:7]}));                             // S-imm
    else if (isBranch_s1)                            imm_s1 = WIDTH'($signed({ins_s1[31], ins_s1[7], ins_s1[30:25], ins_s1[11:8], 1'b0}));// SB-imm
    else if (isJAL_s1)                               imm_s1 = WIDTH'($signed({ins_s1[31], ins_s1[19:12], ins_s1[20], ins_s1[30:21], 1'b0}));// J-imm
    else                                             imm_s1 = '0;

    // Stage 1 reg write enable (used later in Stage 2 after pipelining)
    regWriteEn_s1 = isArithmetic_s1 | isImm_s1 | isMemRead_s1 | isLoadUI_s1 | isJAL_s1 | isJALR_s1 | isAUIPC_s1 | isMUL_s1;
  end

  // ------------------------------------
  // Register file read (Stage 1)
  // ------------------------------------
  assign rs1_val_s1 = (rs1_s1 == 0) ? '0 : registers[rs1_s1];
  assign rs2_val_s1 = (rs2_s1 == 0) ? '0 : registers[rs2_s1];

  // ------------------------------------
  // Stage 2 read (combinational) - used for forwarding
  // ------------------------------------
  always_comb begin : MemReadStage2
    case (funct3_s2[1:0])
      2'b00: memRead_s2 = (!funct3_s2[2]) ? ({{24{mainMemory[alu_b_s2][7]}}, mainMemory[alu_b_s2]}) :
                                           ({24'b0, mainMemory[alu_b_s2]});
      2'b01: memRead_s2 = (!funct3_s2[2]) ? ({{16{mainMemory[alu_b_s2+1][7]}}, {mainMemory[alu_b_s2+1], mainMemory[alu_b_s2]}}) :
                                           ({16'b0, {mainMemory[alu_b_s2+1], mainMemory[alu_b_s2]}});
      2'b10: memRead_s2 = {mainMemory[alu_b_s2+3], mainMemory[alu_b_s2+2], mainMemory[alu_b_s2+1], mainMemory[alu_b_s2]};
      default: memRead_s2 = 32'b0;
    endcase
  end

  // Writeback mux (Stage 2)
  assign regDataIn_s2 = (isJAL_s2 | isJALR_s2) ? pc_plus4_s2 :
                        (isMemRead_s2 ? memRead_s2 : aluOut_s2);

  // ------------------------------------
  // Optional forwarding (Stage 2 -> Stage 1)
  // ------------------------------------
  always_comb begin : ForwardingMuxes
    opA_s1 = rs1_val_s1;
    opB_s1 = rs2_val_s1;

    if (ENABLE_FORWARDING) begin
      if (regWriteEn_s2 && (rd_s2 != 0) && (rd_s2 == rs1_s1)) opA_s1 = regDataIn_s2;
      if (regWriteEn_s2 && (rd_s2 != 0) && (rd_s2 == rs2_s1)) opB_s1 = regDataIn_s2;
    end
  end

  // ------------------------------------
  // ALU (Stage 1)
  // ------------------------------------
  localparam logic [3:0] ADD=0, SLL=1, SLT=2, SLTU=3, XOR=4, SRL=5, OR=6, AND=7, SUB=8, MUL=9, DIV=10, SRA=13, PASS=15;

  always_comb begin
    if      (isMUL_s1)                                                      aluOp_s1 = (funct3_s1[2] ? DIV : MUL);
    else if (isArithmetic_s1)                                               aluOp_s1 = {funct7_s1[5], funct3_s1};
    else if (isImm_s1)                                                      aluOp_s1 = {funct7_s1[5] & (funct3_s1==3'b101), funct3_s1};
    else if (isAUIPC_s1|isJAL_s1|isJALR_s1|isBranch_s1|isMemRead_s1|isMemWrite_s1) aluOp_s1 = ADD;
    else                                                                    aluOp_s1 = PASS;

    // ALU inputs
    src1_s1 = (isJAL_s1 | isBranch_s1 | isAUIPC_s1) ? pc : opA_s1;
    src2_s1 = (isImm_s1 | isMemRead_s1 | isLoadUI_s1 | isJAL_s1 | isJALR_s1 | isMemWrite_s1 | isBranch_s1 | isAUIPC_s1) ? imm_s1 : opB_s1;

    unique case (aluOp_s1)
      ADD    : aluOut_s1 = src1_s1 + src2_s1;
      SUB    : aluOut_s1 = src1_s1 - src2_s1;
      SLL    : aluOut_s1 = src1_s1 << src2_s1[4:0];
      SLT    : aluOut_s1 = WIDTH'($signed  (src1_s1) < $signed  (src2_s1));
      SLTU   : aluOut_s1 = WIDTH'($unsigned(src1_s1) < $unsigned(src2_s1));
      XOR    : aluOut_s1 = src1_s1 ^ src2_s1;
      SRL    : aluOut_s1 = src1_s1 >> src2_s1[4:0];
      SRA    : aluOut_s1 = $signed(src1_s1) >>> src2_s1[4:0];
      OR     : aluOut_s1 = src1_s1 | src2_s1;
      AND    : aluOut_s1 = src1_s1 & src2_s1;
      MUL    : aluOut_s1 = src1_s1 * src2_s1;
      DIV    : aluOut_s1 = ($signed(src2_s1) == 0) ? 32'hFFFFFFFF :
                           (($signed(src1_s1) == 32'h80000000 && $signed(src2_s1) == -1) ? 32'h80000000 : WIDTH'($signed(src1_s1) / $signed(src2_s1)));
      PASS   : aluOut_s1 = src2_s1;
      default: aluOut_s1 = '0;
    endcase
  end

  // ------------------------------------
  // Branch decision (Stage 1) - uses forwarded operands
  // ------------------------------------
  always_comb begin : BranchComparatorStage1
    case (funct3_s1[2:1])
      2'b00: isBranchC_s1 = (funct3_s1[0]) ^ (opA_s1 == opB_s1);                   // BNE/BEQ
      2'b10: isBranchC_s1 = (funct3_s1[0]) ^ ($signed(opA_s1) < $signed(opB_s1));  // BLT/BGE
      2'b11: isBranchC_s1 = (funct3_s1[0]) ^ (opA_s1 < opB_s1);                    // BLTU/BGEU
      default: isBranchC_s1 = 1'b0;
    endcase
    isBranchR_s1 = isBranch_s1 & isBranchC_s1;
  end

  // Next PC mux
  assign next_pc = (isJAL_s1 | isJALR_s1 | isBranchR_s1) ? aluOut_s1 : (pc + 4);

  // ------------------------------------
  // Pipeline register update (Stage 1 -> Stage 2)
  // ------------------------------------
  always_ff @(posedge clock) begin : PipelineRegs
    if (reset) begin
      aluOut_s2     <= '0;
      storeData_s2  <= '0;
      pc_plus4_s2   <= '0;
      funct3_s2     <= '0;
      rd_s2         <= '0;
      isMemRead_s2  <= 1'b0;
      isMemWrite_s2 <= 1'b0;
      isJAL_s2      <= 1'b0;
      isJALR_s2     <= 1'b0;
      regWriteEn_s2 <= 1'b0;
    end else begin
      aluOut_s2     <= aluOut_s1;
      storeData_s2  <= opB_s1;          // rs2 value (forwarded if enabled) for stores
      pc_plus4_s2   <= pc_plus4_s1;
      funct3_s2     <= funct3_s1;
      rd_s2         <= rd_s1;
      isMemRead_s2  <= isMemRead_s1;
      isMemWrite_s2 <= isMemWrite_s1;
      isJAL_s2      <= isJAL_s1;
      isJALR_s2     <= isJALR_s1;
      regWriteEn_s2 <= regWriteEn_s1;
    end
  end

  // ------------------------------------
  // Register writeback (Stage 2)
  // ------------------------------------
  always_ff @(posedge clock) begin : RegWritebackStage2
    if (regWriteEn_s2 && (rd_s2 != 5'd0)) begin
      registers[rd_s2] <= regDataIn_s2;
    end
  end

  // Verification outputs (same as original processor)
  assign {gp, a7, a0} = {registers[3], registers[17], registers[10]};

endmodule
