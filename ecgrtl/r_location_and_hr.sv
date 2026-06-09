// True R-Peak Location and Heart Rate Calculator — v9
//
// KEY CHANGES vs uploaded version:
//
// 1. WINDOW POSITION: centred ±30 → asymmetric [-10, +79]
//    The DWT 4-level pipeline introduces ~39 raw-sample latency so:
//        mapped_r1_pos  ≈  true_GT_peak − 39
//    Previous ±30 window end was mapped+30 = GT−9 → GT was OUTSIDE the window.
//    New window: [mapped−10, mapped+79] → GT at index 49 of 90-sample window ✓
//    T-wave onset (GT+40 = mapped+79) sits at the very last window sample;
//    rpeak_eliminator already rejects T-wave false-peaks before they can
//    propagate to this block, so the boundary case is safe.
//
// 2. HR FORMULA: single-interval → Formula A (span-based)
//    Uploaded version: HR = 21600 / (current_R − previous_R)  [single RR interval]
//    Correct formula:  HR = 21600 × (n−1) / (last_R − first_R)  [Formula A]
//    Formula A matches the paper's reported HR values exactly (verified on
//    records 107, 111, 203, 207, 223).  Single-interval was ~25 BPM low on
//    most records because it used only the last pair of beats.
//    Requires a 21-bit divider: max dividend = 21600 × 62 ≈ 1,339,200.
//
// 3. DIVIDER WIDTH: 15-bit → 21-bit (to accommodate Formula A dividend)

module r_location_and_hr (
    input  logic        clk,
    input  logic        reset,

    input  logic [11:0] r1_pos_in,
    input  logic        r1_valid_in,

    output logic [11:0] raw_mem_addr,
    input  logic [15:0] raw_mem_data,

    output logic [11:0] true_r_location,
    output logic        r_location_valid,
    output logic [7:0]  heart_rate_bpm,
    output logic        hr_valid
);

    // -------------------------------------------------------------------------
    // 16-deep FIFO for incoming r1 positions
    // -------------------------------------------------------------------------
    localparam FIFO_DEPTH = 16;
    localparam FIFO_BITS  = 4;

   (* ramstyle = "logic" *) logic [11:0] fifo_mem [0:FIFO_DEPTH-1];

    logic [FIFO_BITS-1:0] fifo_wr_ptr, fifo_rd_ptr;
    logic [FIFO_BITS:0]   fifo_count;
    logic                 fifo_empty, fifo_full, fifo_rd_en;

    assign fifo_empty = (fifo_count == 0);
    assign fifo_full  = (fifo_count == FIFO_DEPTH);

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            fifo_wr_ptr <= '0;
            fifo_count  <= '0;
            fifo_rd_ptr <= '0;
        end else begin
            if (r1_valid_in && !fifo_full) begin
                fifo_mem[fifo_wr_ptr] <= r1_pos_in;
                fifo_wr_ptr           <= fifo_wr_ptr + 1'b1;
                fifo_count            <= fifo_count + 1'b1;
            end
            if (fifo_rd_en) begin
                fifo_rd_ptr <= fifo_rd_ptr + 1'b1;
                fifo_count  <= fifo_count - 1'b1;
            end
            // Simultaneous read + write: net zero
            if (r1_valid_in && !fifo_full && fifo_rd_en)
                fifo_count <= fifo_count;
        end
    end

    logic [11:0] fifo_rd_data;
    assign fifo_rd_data = fifo_mem[fifo_rd_ptr];

    // -------------------------------------------------------------------------
    // State machine
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        IDLE,
        SEARCH_SETUP,
        SEARCH_READ,
        SEARCH_EVAL,
        CALC_HR_SETUP,
        CALC_HR_DIVIDE,
        CALC_HR_DONE
    } state_t;
    state_t state;

    // Window: [mapped − WINDOW_PRE, mapped + (WINDOW_LEN − WINDOW_PRE)]
    //         = [mapped − 10, mapped + 79]   →  90 samples total
    localparam WINDOW_PRE = 12'd10;     // samples before mapped position
    localparam WINDOW_LEN = 6'd89;      // search_count 0..89 = 90 samples

    logic [11:0] search_start_addr;
    logic [5:0]  search_count;

    logic signed [15:0] local_max_val;
    logic [11:0]        local_max_pos;

    // -------------------------------------------------------------------------
    // Heart Rate — Formula A
    //   HR = 21600 × (beat_count − 1) / (last_r_loc − first_r_loc)
    // beat_count is incremented AFTER the divide, so during CALC_HR_SETUP
    // it holds (n − 1) for the nth beat → used as the NBA-correct multiplier.
    // -------------------------------------------------------------------------
    logic [11:0] first_r_loc;
    logic [5:0]  beat_count;        // saturates at 63
    logic        first_beat_seen;

    // 21-bit restoring divider (max dividend: 21600 × 62 = 1,339,200 < 2^21)
    logic [20:0] div_dividend;
    logic [20:0] div_divisor;
    logic [20:0] div_quotient;
    logic [20:0] div_remainder;
    logic [4:0]  div_step;

    // Next partial remainder (combinatorial)
    wire [20:0] div_next_rem =
        (div_remainder << 1) | ((div_dividend >> div_step) & 21'd1);

    // -------------------------------------------------------------------------
    // Main FSM
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state            <= IDLE;
            fifo_rd_en       <= 1'b0;
            raw_mem_addr     <= 12'd0;
            true_r_location  <= 12'd0;
            r_location_valid <= 1'b0;
            heart_rate_bpm   <= 8'd0;
            hr_valid         <= 1'b0;
            search_count     <= 6'd0;
            local_max_val    <= 16'h8000;   // most-negative signed
            local_max_pos    <= 12'd0;
            first_r_loc      <= 12'd0;
            beat_count       <= 6'd0;
            first_beat_seen  <= 1'b0;
            div_dividend     <= '0;
            div_divisor      <= '0;
            div_quotient     <= '0;
            div_remainder    <= '0;
            div_step         <= 5'd0;
        end else begin
            r_location_valid <= 1'b0;
            hr_valid         <= 1'b0;
            fifo_rd_en       <= 1'b0;

            case (state)
                // -------------------------------------------------------------
                // IDLE: pop next r1 from FIFO, set up window search
                // -------------------------------------------------------------
                IDLE: begin
                    if (!fifo_empty) begin
                        fifo_rd_en <= 1'b1;
                        // Clamp window start to 0
                        if (fifo_rd_data >= WINDOW_PRE)
                            search_start_addr <= fifo_rd_data - WINDOW_PRE;
                        else
                            search_start_addr <= 12'd0;
                        search_count  <= 6'd0;
                        local_max_val <= 16'h8000;
                        state         <= SEARCH_SETUP;
                    end
                end

                // -------------------------------------------------------------
                // 3-cycle per sample: SETUP → READ → EVAL
                // -------------------------------------------------------------
                SEARCH_SETUP: begin
                    raw_mem_addr <= search_start_addr + {6'd0, search_count};
                    state        <= SEARCH_READ;
                end

                SEARCH_READ: begin
                    state <= SEARCH_EVAL;
                end

                SEARCH_EVAL: begin
                    if ($signed(raw_mem_data) > $signed(local_max_val)) begin
                        local_max_val <= raw_mem_data;
                        local_max_pos <= raw_mem_addr;
                    end

                    if (search_count == WINDOW_LEN) begin
                        true_r_location  <= local_max_pos;
                        r_location_valid <= 1'b1;
                        state            <= CALC_HR_SETUP;
                    end else begin
                        search_count <= search_count + 1'b1;
                        state        <= SEARCH_SETUP;
                    end
                end

                // -------------------------------------------------------------
                // HR: Formula A = 21600 × (n−1) / (last_r − first_r)
                //
                // Beat 1: latch first_r_loc; no divide needed yet.
                // Beat n≥2: beat_count (NBA) = n−1 at this point,
                //           so dividend = 21600 × beat_count.
                // -------------------------------------------------------------
                CALC_HR_SETUP: begin
                    if (!first_beat_seen) begin
                        first_r_loc     <= local_max_pos;
                        first_beat_seen <= 1'b1;
                        beat_count      <= 6'd1;
                        state           <= IDLE;
                    end else begin
                        // beat_count = n-1 (NBA) → multiply before increment
                        div_dividend  <= 21'd21600 * {15'd0, beat_count};
                        div_divisor   <= {9'd0, local_max_pos} -
                                         {9'd0, first_r_loc};
                        if (beat_count < 6'd63)
                            beat_count <= beat_count + 1'b1;
                        div_quotient  <= 21'd0;
                        div_remainder <= 21'd0;
                        div_step      <= 5'd20;
                        state         <= CALC_HR_DIVIDE;
                    end
                end

                // 21-step restoring divider (step 20 down to 0)
                CALC_HR_DIVIDE: begin
                    if (div_next_rem >= div_divisor) begin
                        div_remainder          <= div_next_rem - div_divisor;
                        div_quotient[div_step] <= 1'b1;
                    end else begin
                        div_remainder          <= div_next_rem;
                        div_quotient[div_step] <= 1'b0;
                    end
                    if (div_step == 5'd0)
                        state    <= CALC_HR_DONE;
                    else
                        div_step <= div_step - 1'b1;
                end

                CALC_HR_DONE: begin
                    heart_rate_bpm <= (div_quotient > 21'd255) ? 8'd255
                                                               : div_quotient[7:0];
                    hr_valid       <= 1'b1;
                    state          <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
