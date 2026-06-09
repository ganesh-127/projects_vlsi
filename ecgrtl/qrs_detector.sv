// QRS Complex Detection Module — v5
//
// KEY CHANGES vs uploaded version:
//  • MAX_SAMPLES  : 23 → 8
//      Calibrate threshold on first 8 d4 samples (≈ first 128 raw samples).
//      Using 23 samples delayed threshold and caused the detector to miss
//      early beats while still in FIND_MAX state.
//
//  • BLANK_PERIOD : (none) → 5 d4-samples = 222 ms
//      Post-QRS blanking window added via new BLANK state.
//      Previous version had no blanking → double-triggered on single QRS.
//      Previous fix set BLANK=13 (578 ms) which blocked ALL records with
//      HR > ~91 BPM (records 102,104,105,112,119,122,124,203,205,208,209,
//      210,212,213,215,217,221,222,228,233,234 all affected).
//      BLANK=5 (222 ms) is safe for HR up to ~180 BPM (RR ≈ 7.5 d4-samples).
//
//  • FSM: FIND_MAX → DETECT → TRACK → BLANK → DETECT (added BLANK state)

module qrs_detector (
    input  logic               clk,
    input  logic               reset,
    input  logic signed [15:0] d4_in,
    input  logic               valid_in,
    output logic               qrs_found,
    output logic [15:0]        peak_value,
    output logic [11:0]        peak_pos,
    output logic               peak_valid
);

    localparam THRESH_MULT  = 18;   // threshold = 18 % of calibration max
    localparam MAX_SAMPLES  = 8;    // number of d4 samples used for calibration
    localparam BLANK_PERIOD = 5;    // post-peak blanking in d4-sample ticks

    typedef enum logic [1:0] {
        FIND_MAX = 2'b00,
        DETECT   = 2'b01,
        TRACK    = 2'b10,
        BLANK    = 2'b11
    } state_t;
    state_t state;

    logic [15:0] max_val;
    logic [15:0] threshold;
    logic [11:0] sample_cnt;    // absolute d4-sample counter (never reset)
    logic [15:0] current_peak;
    logic [11:0] current_pos;
    logic [3:0]  blank_cnt;

    // |d4|  (two's-complement safe)
    logic [15:0] abs_d4;
    assign abs_d4 = d4_in[15] ? (~d4_in + 1'b1) : d4_in;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state        <= FIND_MAX;
            max_val      <= 16'd0;
            threshold    <= 16'd0;
            sample_cnt   <= 12'd0;
            current_peak <= 16'd0;
            current_pos  <= 12'd0;
            blank_cnt    <= 4'd0;
            qrs_found    <= 1'b0;
            peak_valid   <= 1'b0;
            peak_value   <= 16'd0;
            peak_pos     <= 12'd0;
        end else begin
            qrs_found  <= 1'b0;
            peak_valid <= 1'b0;

            if (valid_in)
                sample_cnt <= sample_cnt + 1'b1;

            case (state)
                // -------------------------------------------------------
                FIND_MAX: begin
                    if (valid_in) begin
                        if (sample_cnt < MAX_SAMPLES) begin
                            if (abs_d4 > max_val) max_val <= abs_d4;
                        end else begin
                            threshold <= (max_val * THRESH_MULT) / 100;
                            state     <= DETECT;
                        end
                    end
                end

                // -------------------------------------------------------
                DETECT: begin
                    if (valid_in && abs_d4 > threshold) begin
                        current_peak <= abs_d4;
                        current_pos  <= sample_cnt;
                        qrs_found    <= 1'b1;
                        state        <= TRACK;
                    end
                end

                // -------------------------------------------------------
                TRACK: begin
                    if (valid_in) begin
                        if (abs_d4 >= current_peak) begin
                            current_peak <= abs_d4;
                            current_pos  <= sample_cnt;
                        end
                        if (abs_d4 < threshold) begin
                            peak_value <= current_peak;
                            peak_pos   <= current_pos;
                            peak_valid <= 1'b1;
                            blank_cnt  <= 4'd0;
                            state      <= BLANK;
                        end
                    end
                end

                // -------------------------------------------------------
                BLANK: begin
                    if (valid_in) begin
                        if (blank_cnt < (BLANK_PERIOD - 1))
                            blank_cnt <= blank_cnt + 1'b1;
                        else
                            state <= DETECT;
                    end
                end

                default: state <= DETECT;
            endcase
        end
    end

endmodule
