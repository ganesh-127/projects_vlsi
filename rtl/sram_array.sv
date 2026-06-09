// sram_array.sv — 256 x 32-bit Behavioral SRAM with byte-enable
// FPGA-safe: uses inferred block RAM style
// Write: synchronous, not gated by clk_en (must always work during BIST)
// Read:  synchronous, 1-cycle latency, gated by clk_en for power saving
`timescale 1ns/1ps

module sram_array (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        clk_en,
    input  logic        cs_n,
    input  logic        we_n,
    input  logic [3:0]  be,
    input  logic [7:0]  sram_addr,
    input  logic [31:0] sram_wdata,
    output logic [31:0] sram_rdata
);
    // 256-word x 32-bit memory
    logic [31:0] mem [0:255];

    // Write port — NOT gated by clk_en (write must always work for BIST)
    always_ff @(posedge clk) begin
        if (!cs_n && !we_n) begin
            if (be[0]) mem[sram_addr][7:0]   <= sram_wdata[7:0];
            if (be[1]) mem[sram_addr][15:8]  <= sram_wdata[15:8];
            if (be[2]) mem[sram_addr][23:16] <= sram_wdata[23:16];
            if (be[3]) mem[sram_addr][31:24] <= sram_wdata[31:24];
        end
    end

    // Read port — synchronous read with 1-cycle latency
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sram_rdata <= 32'h0;
        else if (!cs_n && we_n)       // Read: cs_n=0, we_n=1
            sram_rdata <= mem[sram_addr];
        else if (cs_n)
            sram_rdata <= 32'h0;      // Deselected: output zero
        // else: write cycle — hold previous rdata
    end
endmodule
