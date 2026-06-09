// ahblite_sram_ctrl.sv — AHB-Lite SRAM Controller (two-phase pipelined)
// Zero wait-state, supports WORD/HALFWORD/BYTE transfers
// Address phase: latched on every rising edge
// Data phase: combinational decode of latched address
`timescale 1ns/1ps

module ahblite_sram_ctrl (
    input  logic        hclk,
    input  logic        hresetn,
    // AHB-Lite Interface
    input  logic [31:0] haddr,
    input  logic        hwrite,
    input  logic [2:0]  hsize,
    input  logic        htrans_valid,   // Transfer valid (replaces addr!=0 hack)
    input  logic [31:0] hwdata,
    output logic [31:0] hrdata,
    output logic        hready,
    output logic [1:0]  hresp,
    // SRAM Interface
    output logic        cs_n,
    output logic        we_n,
    output logic [3:0]  be,
    output logic [7:0]  sram_addr,
    output logic [31:0] sram_wdata,
    input  logic [31:0] sram_rdata
);
    // Latched address-phase signals
    logic [31:0] haddr_r;
    logic        hwrite_r;
    logic [2:0]  hsize_r;
    logic        valid_r;

    // Byte-enable generator based on transfer size and address LSBs
    function automatic logic [3:0] gen_be(
        input logic [2:0] size,
        input logic [1:0] lsb
    );
        case (size)
            3'b000: case (lsb)                         // Byte
                        2'b00: return 4'b0001;
                        2'b01: return 4'b0010;
                        2'b10: return 4'b0100;
                        2'b11: return 4'b1000;
                        default: return 4'b0001;
                    endcase
            3'b001: return (lsb == 2'b10 || lsb == 2'b11) ? 4'b1100 : 4'b0011; // Halfword
            default: return 4'b1111;                     // Word
        endcase
    endfunction

    // Latch address phase signals every clock cycle
    always_ff @(posedge hclk or negedge hresetn) begin
        if (!hresetn) begin
            haddr_r  <= 32'h0;
            hwrite_r <= 1'b0;
            hsize_r  <= 3'b010;
            valid_r  <= 1'b0;
        end else begin
            haddr_r  <= haddr;
            hwrite_r <= hwrite;
            hsize_r  <= hsize;
            valid_r  <= htrans_valid;
        end
    end

    // Data phase assignments outside always_comb to avoid Icarus Verilog part-select bugs
    assign sram_addr  = haddr_r[9:2];
    assign sram_wdata = hwdata;
    assign hrdata     = sram_rdata;
    assign hready     = 1'b1;
    assign hresp      = 2'b00;

    logic [1:0] addr_lsb;
    assign addr_lsb = haddr_r[1:0];

    // Data phase: combinational decode from latched signals
    always_comb begin
        // Defaults: no access
        cs_n       = 1'b1;
        we_n       = 1'b1;
        be         = 4'b1111;

        if (valid_r) begin
            cs_n = 1'b0;
            be   = gen_be(hsize_r, addr_lsb);
            if (hwrite_r)
                we_n = 1'b0;               // Write: assert we_n low
            else
                we_n = 1'b1;               // Read: we_n stays high
        end
    end
endmodule
