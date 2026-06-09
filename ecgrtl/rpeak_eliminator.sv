// False R-Peak Elimination Module (R_1 Generator) — v2
//
// KEY CHANGES vs uploaded version:
//  • REFRACTORY_LIMIT : 5 → 7   (7×16/360 = 311 ms)
//      Uploads used 5 d4 = 222 ms which is shorter than normal QRS duration
//      and allowed secondary QRS deflections through. 7 d4-samples matches
//      the standard absolute refractory period of the ventricle.
//
//  • TWAVE_LIMIT : 8 → 11   (11×16/360 = 489 ms)
//      Uploads used 8 d4 = 356 ms which missed T-waves occurring at 360–450 ms
//      post-QRS. 11 d4-samples covers the full T-wave window up to ~490 ms.

module rpeak_eliminator (
    input  logic        clk,
    input  logic        reset,

    input  logic [15:0] peak_val_in,
    input  logic [11:0] peak_pos_in,
    input  logic        peak_valid_in,

    input  logic        sample_tick,    // d4_valid — one tick per d4 sample

    output logic [15:0] r1_val_out,
    output logic [11:0] r1_pos_out,
    output logic        r1_valid_out
);

    localparam REFRACTORY_LIMIT = 12'd7;    // 311 ms
    localparam TWAVE_LIMIT      = 12'd11;   // 489 ms

    logic [15:0] pending_val;
    logic [11:0] pending_pos;
    logic        has_pending;
    logic [11:0] current_sample_cnt;
	 logic [11:0] interval;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            pending_val        <= 16'd0;
            pending_pos        <= 12'd0;
            has_pending        <= 1'b0;
            current_sample_cnt <= 12'd0;
            r1_val_out         <= 16'd0;
            r1_pos_out         <= 12'd0;
            r1_valid_out       <= 1'b0;
        end else begin
            r1_valid_out <= 1'b0;

            // Advance absolute d4 time counter
            if (sample_tick) begin
                current_sample_cnt <= current_sample_cnt + 1'b1;

                // Release pending beat once it has survived the full T-wave window
                if (has_pending &&
                    ((current_sample_cnt - pending_pos) >= TWAVE_LIMIT)) begin
                    r1_val_out   <= pending_val;
                    r1_pos_out   <= pending_pos;
                    r1_valid_out <= 1'b1;
                    has_pending  <= 1'b0;
                end
            end

            // Evaluate newly arriving candidate peaks
            if (peak_valid_in) begin
                if (!has_pending) begin
                    // First candidate after silence: store unconditionally
                    pending_val <= peak_val_in;
                    pending_pos <= peak_pos_in;
                    has_pending <= 1'b1;
                end else begin
                    
                    interval = peak_pos_in - pending_pos;

                    if (interval < REFRACTORY_LIMIT) begin
                        // Rule A: < 311 ms — discard (same QRS, noise)
                        // no action
                    end else if (interval < TWAVE_LIMIT) begin
                        // Rule B: 311–489 ms — T-wave window; keep larger amplitude
                        if (peak_val_in > pending_val) begin
                            pending_val <= peak_val_in;
                            pending_pos <= peak_pos_in;
                        end
                    end
                    // interval >= TWAVE_LIMIT handled by the sample_tick branch above
                end
            end
        end
    end

endmodule
