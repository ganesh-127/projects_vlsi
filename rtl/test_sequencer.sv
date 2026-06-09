// test_sequencer.sv — Synthesizable auto-test controller for FPGA mode (TB_MODE=0)
// Runs through: Word Write → Word Read → Byte Write → Halfword Write → BIST → Post-BIST → Power idle → Done
// All ROM data initialized via reset (no `initial` blocks — fully synthesizable)
`timescale 1ns/1ps

module test_sequencer (
    input  logic        clk,
    input  logic        rst_n,
    // AHB master outputs
    output logic [31:0] haddr,
    output logic        hwrite,
    output logic [2:0]  hsize,
    output logic [31:0] hwdata,
    output logic        htrans_valid,     // Explicit transfer valid
    // BIST interface
    output logic        bist_enable,
    input  logic        bist_done,
    input  logic        bist_fail,
    // AHB slave inputs
    input  logic [31:0] hrdata,
    input  logic        hready,
    // Status outputs
    output logic [3:0]  phase_id,
    output logic        test_pass,
    output logic        test_fail_flag,
    // Control
    input  logic        auto_start        // Start auto-test when pressed
);

    typedef enum logic [3:0] {
        PHASE_IDLE     = 4'd0,
        PHASE_WRITE    = 4'd1,
        PHASE_READ     = 4'd2,
        PHASE_BYTE_WR  = 4'd3,
        PHASE_HALF_WR  = 4'd4,
        PHASE_BIST     = 4'd5,
        PHASE_POSTBIST = 4'd6,
        PHASE_POWER    = 4'd7,
        PHASE_DONE     = 4'd8
    } phase_t;

    phase_t      phase;
    logic [7:0]  step;
    logic        mismatch;
    logic        started;       // Latch: auto_start received

    // ROM data — synthesizable constant assignments
    // 6 test addresses and data patterns
    logic [31:0] wr_addr_val;
    logic [31:0] wr_data_val;

    // Address/data ROM via combinational lookup
    always_comb begin
        case (step[2:0])
            3'd0: begin wr_addr_val = 32'h000000A0; wr_data_val = 32'hDEAD_BEEF; end
            3'd1: begin wr_addr_val = 32'h000000A4; wr_data_val = 32'hCAFE_BABE; end
            3'd2: begin wr_addr_val = 32'h000000A8; wr_data_val = 32'h1234_5678; end
            3'd3: begin wr_addr_val = 32'h000000AC; wr_data_val = 32'hABCD_EF01; end
            3'd4: begin wr_addr_val = 32'h000000B0; wr_data_val = 32'h5A5A_5A5A; end
            3'd5: begin wr_addr_val = 32'h000000B4; wr_data_val = 32'hA5A5_A5A5; end
            default: begin wr_addr_val = 32'h0; wr_data_val = 32'h0; end
        endcase
    end

    // Previous step's expected data for read comparison
    logic [31:0] prev_data_val;
    always_comb begin
        case (step[2:0])
            3'd1: prev_data_val = 32'hDEAD_BEEF;
            3'd2: prev_data_val = 32'hCAFE_BABE;
            3'd3: prev_data_val = 32'h1234_5678;
            3'd4: prev_data_val = 32'hABCD_EF01;
            3'd5: prev_data_val = 32'h5A5A_5A5A;
            default: prev_data_val = 32'h0;
        endcase
    end

    assign phase_id       = phase;
    assign test_pass      = (phase == PHASE_DONE) && !mismatch && !bist_fail;
    assign test_fail_flag = mismatch || bist_fail;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase       <= PHASE_IDLE;
            step        <= 8'd0;
            haddr       <= 32'h0;
            hwrite      <= 1'b0;
            hsize       <= 3'b010;
            hwdata      <= 32'h0;
            htrans_valid <= 1'b0;
            bist_enable <= 1'b0;
            mismatch    <= 1'b0;
            started     <= 1'b0;
        end else begin
            // Default: deassert every cycle
            hwrite      <= 1'b0;
            haddr       <= 32'h0;
            htrans_valid <= 1'b0;
            bist_enable <= 1'b0;

            case (phase)

                // ------- IDLE: wait for auto_start -------
                PHASE_IDLE: begin
                    if (auto_start && !started) begin
                        started <= 1'b1;
                        step    <= 8'd0;
                        phase   <= PHASE_WRITE;
                    end
                end

                // ------- WORD WRITE: 6 locations -------
                PHASE_WRITE: begin
                    if (step < 8'd6) begin
                        haddr       <= wr_addr_val;
                        hwrite      <= 1'b1;
                        hsize       <= 3'b010;
                        hwdata      <= wr_data_val;
                        htrans_valid <= 1'b1;
                        step        <= step + 8'd1;
                    end else begin
                        step  <= 8'd0;
                        phase <= PHASE_READ;
                    end
                end

                // ------- WORD READ & COMPARE -------
                PHASE_READ: begin
                    if (step < 8'd6) begin
                        haddr       <= wr_addr_val;
                        hwrite      <= 1'b0;
                        hsize       <= 3'b010;
                        htrans_valid <= 1'b1;
                        // Compare with previous step's data (pipeline delay)
                        if (step > 8'd0 && hrdata !== prev_data_val)
                            mismatch <= 1'b1;
                        step <= step + 8'd1;
                    end else begin
                        step  <= 8'd0;
                        phase <= PHASE_BYTE_WR;
                    end
                end

                // ------- BYTE WRITE (be = 0001) -------
                PHASE_BYTE_WR: begin
                    case (step)
                        8'd0: begin    // Write byte
                            haddr       <= 32'h000000C0;
                            hwrite      <= 1'b1;
                            hsize       <= 3'b000;
                            hwdata      <= 32'h000000AB;
                            htrans_valid <= 1'b1;
                            step        <= 8'd1;
                        end
                        8'd1: begin    // Read back
                            haddr       <= 32'h000000C0;
                            hwrite      <= 1'b0;
                            hsize       <= 3'b000;
                            htrans_valid <= 1'b1;
                            step        <= 8'd2;
                        end
                        8'd2: begin    // Verify
                            if (hrdata[7:0] !== 8'hAB)
                                mismatch <= 1'b1;
                            step  <= 8'd0;
                            phase <= PHASE_HALF_WR;
                        end
                        default: step <= 8'd0;
                    endcase
                end

                // ------- HALFWORD WRITE (be = 0011) -------
                PHASE_HALF_WR: begin
                    case (step)
                        8'd0: begin    // Write halfword
                            haddr       <= 32'h000000C4;
                            hwrite      <= 1'b1;
                            hsize       <= 3'b001;
                            hwdata      <= 32'h0000BEEF;
                            htrans_valid <= 1'b1;
                            step        <= 8'd1;
                        end
                        8'd1: begin    // Read back
                            haddr       <= 32'h000000C4;
                            hwrite      <= 1'b0;
                            hsize       <= 3'b001;
                            htrans_valid <= 1'b1;
                            step        <= 8'd2;
                        end
                        8'd2: begin    // Verify
                            if (hrdata[15:0] !== 16'hBEEF)
                                mismatch <= 1'b1;
                            step  <= 8'd0;
                            phase <= PHASE_BIST;
                        end
                        default: step <= 8'd0;
                    endcase
                end

                // ------- BIST: March-C full run -------
                PHASE_BIST: begin
                    bist_enable <= 1'b1;
                    if (bist_done) begin
                        bist_enable <= 1'b0;
                        step        <= 8'd0;
                        phase       <= PHASE_POSTBIST;
                    end
                end

                // ------- POST-BIST READ: expect all zeros -------
                PHASE_POSTBIST: begin
                    if (step < 8'd4) begin
                        haddr       <= wr_addr_val;
                        hwrite      <= 1'b0;
                        hsize       <= 3'b010;
                        htrans_valid <= 1'b1;
                        if (step > 8'd0 && hrdata !== 32'h0000_0000)
                            mismatch <= 1'b1;
                        step <= step + 8'd1;
                    end else begin
                        step  <= 8'd0;
                        phase <= PHASE_POWER;
                    end
                end

                // ------- POWER: idle → trigger STANDBY/RETENTION -------
                PHASE_POWER: begin
                    // No AHB activity — power_mgmt FSM transitions automatically
                    if (step < 8'd200)
                        step <= step + 8'd1;
                    else begin
                        step  <= 8'd0;
                        phase <= PHASE_DONE;
                    end
                end

                // ------- DONE: hold final result -------
                PHASE_DONE: begin
                    haddr       <= 32'h0;
                    hwrite      <= 1'b0;
                    htrans_valid <= 1'b0;
                    // test_pass / test_fail_flag held by assign statements
                end

                default: phase <= PHASE_IDLE;
            endcase
        end
    end
endmodule
