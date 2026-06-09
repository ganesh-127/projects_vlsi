// power_mgmt.sv — FPGA-safe Power Management FSM
// Uses clock enable instead of clock gating (FPGA-compatible)
// States: ACTIVE → STANDBY → RETENTION (→ SHUTDOWN not used on FPGA)
// Any access_req or bist_enable wakes back to ACTIVE
`timescale 1ns/1ps

module power_mgmt (
    input  logic clk,
    input  logic rst_n,
    input  logic bist_enable,
    input  logic access_req,
    output logic clk_en,      // Clock enable (replaces clock gate — FPGA safe)
    output logic iso,         // Isolation flag
    output logic ret,         // Retention mode flag
    output logic shutdown     // Shutdown flag
);
    typedef enum logic [1:0] {
        ACTIVE    = 2'b00,
        STANDBY   = 2'b01,
        RETENTION = 2'b10,
        SHUTDOWN  = 2'b11
    } pwr_t;

    pwr_t        pwr_state;
    logic [15:0] idle_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwr_state <= ACTIVE;
            idle_cnt  <= 16'd0;
        end else begin
            case (pwr_state)
                ACTIVE: begin
                    if (access_req || bist_enable) begin
                        idle_cnt <= 16'd0;
                    end else begin
                        idle_cnt <= idle_cnt + 16'd1;
                    end
                    if (!access_req && !bist_enable && idle_cnt > 16'd1000)
                        pwr_state <= STANDBY;
                end

                STANDBY: begin
                    if (access_req || bist_enable) begin
                        pwr_state <= ACTIVE;
                        idle_cnt  <= 16'd0;
                    end else if (idle_cnt > 16'd5000) begin
                        pwr_state <= RETENTION;
                    end else begin
                        idle_cnt <= idle_cnt + 16'd1;
                    end
                end

                RETENTION: begin
                    if (access_req || bist_enable) begin
                        pwr_state <= ACTIVE;
                        idle_cnt  <= 16'd0;
                    end
                end

                SHUTDOWN: begin
                    // On FPGA, just go back to ACTIVE
                    pwr_state <= ACTIVE;
                    idle_cnt  <= 16'd0;
                end

                default: pwr_state <= ACTIVE;
            endcase
        end
    end

    // Output assignments based on state
    assign clk_en   = (pwr_state == ACTIVE);
    assign iso      = (pwr_state == RETENTION || pwr_state == SHUTDOWN);
    assign ret      = (pwr_state == RETENTION);
    assign shutdown  = (pwr_state == SHUTDOWN);
endmodule
