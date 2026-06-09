// bist_ctrl.sv — March-C BIST Controller, FPGA-safe
// Implements full March C- Algorithm: {⇑(w0); ⇑(r0,w1); ⇑(r1,w0); ⇓(r0,w1); ⇓(r1,w0); ⇑(r0)}
// Each read/write is separated into distinct clock cycles for correct SRAM timing
`timescale 1ns/1ps

module bist_ctrl (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        bist_enable,
    output logic [7:0]  bist_addr,
    output logic [31:0] bist_wdata,
    output logic        bist_we_n,
    output logic        bist_cs_n,
    input  logic [31:0] bist_rdata,
    output logic        bist_done,
    output logic        bist_fail,
    // Signal Tap probes
    output logic [3:0]  bist_mode,
    output logic [7:0]  bist_step
);

    // States: each read+write March phase needs two sub-states
    // March C- Algorithm: M0:⇑(w0), M1:⇑(r0,w1), M2:⇑(r1,w0), M3:⇓(r0,w1), M4:⇓(r1,w0), M5:⇑(r0)
    localparam [3:0] B_IDLE   = 4'd0;
    localparam [3:0] B_M0_W0  = 4'd1;     // M0 ⇑ w0
    localparam [3:0] B_M1_R0  = 4'd2;     // M1 ⇑ r0
    localparam [3:0] B_M1_W1  = 4'd3;     // M1 ⇑ w1
    localparam [3:0] B_M2_R1  = 4'd4;     // M2 ⇑ r1
    localparam [3:0] B_M2_W0  = 4'd5;     // M2 ⇑ w0
    localparam [3:0] B_M3_R0  = 4'd6;     // M3 ⇓ r0
    localparam [3:0] B_M3_W1  = 4'd7;     // M3 ⇓ w1
    localparam [3:0] B_M4_R1  = 4'd8;     // M4 ⇓ r1
    localparam [3:0] B_M4_W0  = 4'd9;     // M4 ⇓ w0
    localparam [3:0] B_M5_R0  = 4'd10;    // M5 ⇑/any r0
    localparam [3:0] B_DONE   = 4'd11;

    logic [3:0]  state, state_next;
    logic [7:0]  addr_cnt;
    logic        fail_r;

    assign bist_mode = state;
    assign bist_step = addr_cnt;
    assign bist_fail = fail_r;

    // State register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= B_IDLE;
        else
            state <= state_next;
    end

    // Pipelined read verification
    logic check_pending;
    logic [31:0] check_exp;

    // Address counter and pipelined fail verification
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr_cnt <= 8'd0;
            fail_r   <= 1'b0;
            check_pending <= 1'b0;
            check_exp <= 32'h0;
        end else begin
            // Check previous cycle's read
            if (check_pending && bist_rdata !== check_exp) begin
                fail_r <= 1'b1;
            end

            if (!bist_enable) begin
                fail_r <= 1'b0;
                check_pending <= 1'b0;
                addr_cnt <= 8'd0;
            end else begin
                // Schedule a check for next cycle if a read is happening
                if (state != B_IDLE && state != B_DONE && bist_we_n == 1'b1) begin
                    check_pending <= 1'b1;
                    check_exp <= (state == B_M2_R1 || state == B_M4_R1) ? 32'hFFFF_FFFF : 32'h0000_0000;
                end else begin
                    check_pending <= 1'b0;
                end

                case (state)
                    B_M0_W0: begin
                        if (addr_cnt == 8'd255) addr_cnt <= 8'd0;
                        else                    addr_cnt <= addr_cnt + 8'd1;
                    end
                    B_M1_R0: begin end // Read cycle, hold address
                    B_M1_W1: begin
                        if (addr_cnt == 8'd255) addr_cnt <= 8'd0;
                        else                    addr_cnt <= addr_cnt + 8'd1;
                    end
                    B_M2_R1: begin end // Read cycle, hold address
                    B_M2_W0: begin
                        if (addr_cnt == 8'd255) addr_cnt <= 8'd255; // Set boundary for descending M3
                        else                    addr_cnt <= addr_cnt + 8'd1;
                    end
                    B_M3_R0: begin end // Read cycle, hold address
                    B_M3_W1: begin
                        if (addr_cnt == 8'd0) addr_cnt <= 8'd255;  // M4 also must start at max bound (descending)
                        else                  addr_cnt <= addr_cnt - 8'd1;
                    end
                    B_M4_R1: begin end // Read cycle, hold address
                    B_M4_W0: begin
                        if (addr_cnt == 8'd0) addr_cnt <= 8'd0;    // Set boundary for ascending M5
                        else                  addr_cnt <= addr_cnt - 8'd1;
                    end
                    B_M5_R0: begin
                        if (addr_cnt == 8'd255) addr_cnt <= 8'd0;
                        else                    addr_cnt <= addr_cnt + 8'd1;
                    end
                    B_DONE: begin
                        addr_cnt <= 8'd0;
                    end
                    default: ;
                endcase
            end
        end
    end

    // Next state logic
    always_comb begin
        state_next = state;
        case (state)
            B_IDLE: begin
                if (bist_enable) state_next = B_M0_W0;
                else             state_next = B_IDLE;
            end
            B_M0_W0: begin
                if (addr_cnt == 8'd255) state_next = B_M1_R0;
                else                    state_next = B_M0_W0;
            end
            B_M1_R0: state_next = B_M1_W1;
            B_M1_W1: begin
                if (addr_cnt == 8'd255) state_next = B_M2_R1;
                else                    state_next = B_M1_R0;
            end
            B_M2_R1: state_next = B_M2_W0;
            B_M2_W0: begin
                if (addr_cnt == 8'd255) state_next = B_M3_R0;
                else                    state_next = B_M2_R1;
            end
            B_M3_R0: state_next = B_M3_W1;
            B_M3_W1: begin
                if (addr_cnt == 8'd0) state_next = B_M4_R1;
                else                  state_next = B_M3_R0;
            end
            B_M4_R1: state_next = B_M4_W0;
            B_M4_W0: begin
                if (addr_cnt == 8'd0) state_next = B_M5_R0;
                else                  state_next = B_M4_R1;
            end
            B_M5_R0: begin
                if (addr_cnt == 8'd255) state_next = B_DONE;
                else                    state_next = B_M5_R0;
            end
            B_DONE: begin
                if (bist_enable) state_next = B_DONE;
                else             state_next = B_IDLE;
            end
            default: state_next = B_IDLE;
        endcase
    end

    // Output logic
    always_comb begin
        bist_addr  = addr_cnt;
        bist_cs_n  = 1'b1;
        bist_we_n  = 1'b1;
        bist_wdata = 32'h0;
        bist_done  = (state == B_DONE);

        if (bist_enable || state != B_IDLE) begin
            bist_cs_n = 1'b0;   // Chip select active during entire BIST

            case (state)
                B_M0_W0: begin bist_we_n = 1'b0; bist_wdata = 32'h0000_0000; end
                B_M1_R0: begin bist_we_n = 1'b1; bist_wdata = 32'h0;         end
                B_M1_W1: begin bist_we_n = 1'b0; bist_wdata = 32'hFFFF_FFFF; end
                B_M2_R1: begin bist_we_n = 1'b1; bist_wdata = 32'h0;         end
                B_M2_W0: begin bist_we_n = 1'b0; bist_wdata = 32'h0000_0000; end
                B_M3_R0: begin bist_we_n = 1'b1; bist_wdata = 32'h0;         end
                B_M3_W1: begin bist_we_n = 1'b0; bist_wdata = 32'hFFFF_FFFF; end
                B_M4_R1: begin bist_we_n = 1'b1; bist_wdata = 32'h0;         end
                B_M4_W0: begin bist_we_n = 1'b0; bist_wdata = 32'h0000_0000; end
                B_M5_R0: begin bist_we_n = 1'b1; bist_wdata = 32'h0;         end
                B_DONE:  begin bist_we_n = 1'b1; bist_wdata = 32'h0;         end
                default: begin bist_we_n = 1'b1; bist_wdata = 32'h0;         end
            endcase
        end
    end
endmodule
