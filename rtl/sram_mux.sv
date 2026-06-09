// sram_mux.sv — 2:1 MUX between AHB Controller and BIST paths
// When bist_enable=1, BIST controller drives the SRAM
// When bist_enable=0, AHB controller drives the SRAM
`timescale 1ns/1ps

module sram_mux (
    input  logic        bist_enable,
    // From AHB controller
    input  logic [7:0]  ctrl_addr,
    input  logic [31:0] ctrl_wdata,
    input  logic        ctrl_we_n,
    input  logic        ctrl_cs_n,
    input  logic [3:0]  ctrl_be,
    // From BIST controller
    input  logic [7:0]  bist_addr,
    input  logic [31:0] bist_wdata,
    input  logic        bist_we_n,
    input  logic        bist_cs_n,
    // To SRAM array
    output logic [7:0]  sram_addr,
    output logic [31:0] sram_wdata,
    output logic        sram_we_n,
    output logic        sram_cs_n,
    output logic [3:0]  sram_be
);
    always_comb begin
        if (bist_enable) begin
            sram_addr  = bist_addr;
            sram_wdata = bist_wdata;
            sram_we_n  = bist_we_n;
            sram_cs_n  = bist_cs_n;
            sram_be    = 4'b1111;         // BIST always uses full word
        end else begin
            sram_addr  = ctrl_addr;
            sram_wdata = ctrl_wdata;
            sram_we_n  = ctrl_we_n;
            sram_cs_n  = ctrl_cs_n;
            sram_be    = ctrl_be;
        end
    end
endmodule
