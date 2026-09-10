// ============================================================================
// axi_lite_slave.sv
// Simple AXI4-Lite compliant slave: 16 x 32-bit memory-mapped register file.
// Supports single-beat read/write transactions per the AXI4-Lite protocol
// (no bursts, no WSTRB partial-write is honored, full 4-byte strobes assumed
// as minimum viable but WSTRB is respected bit-per-byte).
// ============================================================================

module axi_lite_slave #(
    parameter int ADDR_WIDTH = 6,     // 6 bits -> byte address, 16 words (4B each)
    parameter int DATA_WIDTH = 32
) (
    input  logic                      ACLK,
    input  logic                      ARESETn,

    // Write address channel
    input  logic [ADDR_WIDTH-1:0]     AWADDR,
    input  logic                      AWVALID,
    output logic                      AWREADY,

    // Write data channel
    input  logic [DATA_WIDTH-1:0]     WDATA,
    input  logic [(DATA_WIDTH/8)-1:0] WSTRB,
    input  logic                      WVALID,
    output logic                      WREADY,

    // Write response channel
    output logic [1:0]                BRESP,
    output logic                      BVALID,
    input  logic                      BREADY,

    // Read address channel
    input  logic [ADDR_WIDTH-1:0]     ARADDR,
    input  logic                      ARVALID,
    output logic                      ARREADY,

    // Read data channel
    output logic [DATA_WIDTH-1:0]     RDATA,
    output logic [1:0]                RRESP,
    output logic                      RVALID,
    input  logic                      RREADY
);

  localparam int NUM_REGS = (1 << ADDR_WIDTH) / (DATA_WIDTH/8);
  localparam int WORD_OFFSET = $clog2(DATA_WIDTH/8); // =2 for 32-bit

  // Backing storage
  logic [DATA_WIDTH-1:0] mem [0:NUM_REGS-1];

  // ---------------- Write Address channel ----------------
  logic aw_en;
  // Bottom WORD_OFFSET bits of the latched byte address are intentionally
  // unused: this is a word-aligned register file, so only the upper bits
  // (ADDR_WIDTH-1:WORD_OFFSET) select a word; byte-within-word bits are
  // dropped by design, not left over by mistake.
  /* verilator lint_off UNUSEDSIGNAL */
  logic [ADDR_WIDTH-1:0] awaddr_latched;
  /* verilator lint_on UNUSEDSIGNAL */

  always_ff @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      AWREADY <= 1'b0;
      aw_en   <= 1'b1;
      awaddr_latched <= '0;
    end else begin
      if (~AWREADY && AWVALID && WVALID && aw_en) begin
        AWREADY <= 1'b1;
        aw_en   <= 1'b0;
        awaddr_latched <= AWADDR;
      end else if (BVALID && BREADY) begin
        aw_en   <= 1'b1;
        AWREADY <= 1'b0;
      end else begin
        AWREADY <= 1'b0;
      end
    end
  end

  // ---------------- Write Data channel + memory write ----------------
  always_ff @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      WREADY <= 1'b0;
    end else begin
      if (~WREADY && WVALID && AWVALID && aw_en) begin
        WREADY <= 1'b1;
      end else begin
        WREADY <= 1'b0;
      end
    end
  end

  integer bi, ri;
  // Memory write: gated on the cycle where both AWREADY & WREADY are high
  // (i.e. the address+data handshake completed this cycle). Also handles
  // synchronous reset of the whole register file so unwritten locations
  // read back as a known 0, not X.
  always_ff @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      for (ri = 0; ri < NUM_REGS; ri++)
        mem[ri] <= '0;
    end else if (AWREADY && WREADY) begin
      for (bi = 0; bi < DATA_WIDTH/8; bi++) begin
        if (WSTRB[bi])
          mem[awaddr_latched[ADDR_WIDTH-1:WORD_OFFSET]][bi*8 +: 8] <= WDATA[bi*8 +: 8];
      end
    end
  end

  // ---------------- Write Response channel ----------------
  always_ff @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      BVALID <= 1'b0;
      BRESP  <= 2'b00;
    end else begin
      if (AWREADY && WREADY && ~BVALID) begin
        BVALID <= 1'b1;
        BRESP  <= 2'b00; // OKAY
      end else if (BVALID && BREADY) begin
        BVALID <= 1'b0;
      end
    end
  end

  // ---------------- Read Address channel ----------------
  /* verilator lint_off UNUSEDSIGNAL */
  logic [ADDR_WIDTH-1:0] araddr_latched;
  /* verilator lint_on UNUSEDSIGNAL */

  always_ff @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      ARREADY <= 1'b0;
      araddr_latched <= '0;
    end else begin
      if (~ARREADY && ARVALID) begin
        ARREADY <= 1'b1;
        araddr_latched <= ARADDR;
      end else begin
        ARREADY <= 1'b0;
      end
    end
  end

  // ---------------- Read Data channel ----------------
  always_ff @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      RVALID <= 1'b0;
      RDATA  <= '0;
      RRESP  <= 2'b00;
    end else begin
      if (ARREADY && ARVALID && ~RVALID) begin
        RVALID <= 1'b1;
        RDATA  <= mem[araddr_latched[ADDR_WIDTH-1:WORD_OFFSET]];
        RRESP  <= 2'b00; // OKAY
      end else if (RVALID && RREADY) begin
        RVALID <= 1'b0;
      end
    end
  end

endmodule
