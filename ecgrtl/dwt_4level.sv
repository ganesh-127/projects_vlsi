// 4-Level Folded Lifting-based DWT for Daubechies 4 Wavelet
// Implements 16-bit fixed-point (Q4.12 format)

module dwt_4level_folded #(
    parameter WIDTH = 16,
    parameter FRAC  = 12
)(
    input  logic clk,
    input  logic rst,
    
    // In a folded architecture, the input comes from either the external ADC (Level 1)
    // or the internal Memory Array Block (Levels 2, 3, 4).
    input  logic signed [WIDTH-1:0] y_even,    // y_2n
    input  logic signed [WIDTH-1:0] y_odd,     // y_2n+1
    input  logic valid_in,

    output logic signed [WIDTH-1:0] approx_out, // a_n (fed back to RAM for next level)
    output logic signed [WIDTH-1:0] detail_out, // d_n (Level 4 output goes to QRS detector)
    output logic valid_out
);

    // ----------------------------------
    // DB4 Lifting Coefficients (Q4.12 format)
    // alpha * 4096 (2^12)
    // ----------------------------------
    // alpha1 = -sqrt(3)        => -1.73205 * 4096 = -7094
    // alpha2 = sqrt(3)/4       =>  0.43301 * 4096 =  1774
    // alpha3 = (sqrt(3)-2)/4   => -0.06699 * 4096 = -274
    // alpha4 = (sqrt(3)+1)/sqrt(2) => 1.93185 * 4096 = 7913
    // alpha5 = (sqrt(3)-1)/sqrt(2) => 0.51764 * 4096 = 2120

    localparam signed [WIDTH-1:0] ALPHA1 = -7094;
    localparam signed [WIDTH-1:0] ALPHA2 =  1774;
    localparam signed [WIDTH-1:0] ALPHA3 = -274;
    localparam signed [WIDTH-1:0] ALPHA4 =  7913;
    localparam signed [WIDTH-1:0] ALPHA5 =  2120;

    // ----------------------------------
    // Pipeline Registers (Delay Elements)
    // ----------------------------------
    logic signed [WIDTH-1:0] y_even_delay;
    logic signed [WIDTH-1:0] d1_curr, d1_prev, d1_prev2;
    logic signed [WIDTH-1:0] a1_curr, a1_prev;
    logic signed [WIDTH-1:0] d2_curr;
    
    logic v1, v2, v3, v4;

    // Multiplier outputs (32-bit to prevent overflow before shifting)
    logic signed [31:0] mult_a1, mult_a2, mult_a3, mult_a4, mult_a5;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            y_even_delay <= 0;
            d1_curr      <= 0;
            d1_prev      <= 0;
            d1_prev2     <= 0;
            a1_curr      <= 0;
            a1_prev      <= 0;
            d2_curr      <= 0;
            approx_out   <= 0;
            detail_out   <= 0;
            {v1, v2, v3, v4, valid_out} <= 0;
        end else begin
            // Shift valid signals through the pipeline
            v1 <= valid_in;
            v2 <= v1;
            v3 <= v2;
            v4 <= v3;
            valid_out <= v4;

            if (valid_in) begin
                // ----------------------------------------------------
                // STEP 1: Calculate intermediate d1_n
                // d1_n = y_2n+1 + (-sqrt(3) * y_2n)
                // ----------------------------------------------------
                mult_a1 = y_even * ALPHA1;
                d1_curr <= y_odd + (mult_a1 >>> FRAC);
                
                // Buffer y_even for the next step because Step 2 needs it
                y_even_delay <= y_even;
            end

            if (v1) begin
                // ----------------------------------------------------
                // STEP 2: Calculate intermediate a1_n
                // This requires d1_curr (which acts as future sample d1_n+1)
                // and d1_prev (which acts as current sample d1_n).
                // a1_n = y_2n + (sqrt(3)/4 * d1_n) + ((sqrt(3)-2)/4 * d1_n+1)
                // ----------------------------------------------------
                d1_prev <= d1_curr;
                
                mult_a2 = d1_prev * ALPHA2;
                mult_a3 = d1_curr * ALPHA3; // d1_curr is the "future" sample here
                
                a1_curr <= y_even_delay + (mult_a2 >>> FRAC) + (mult_a3 >>> FRAC);
            end

            if (v2) begin
                // ----------------------------------------------------
                // STEP 3: Calculate intermediate d2_n
                // This requires a past sample of a1_n (a1_prev)
                // d2_n = d1_n + a1_n-1
                // ----------------------------------------------------
                a1_prev  <= a1_curr;
                d1_prev2 <= d1_prev; // Align d1 with the delayed a1
                
                d2_curr <= d1_prev2 + a1_prev;
            end

            if (v3) begin
                // ----------------------------------------------------
                // STEP 4: Final Scaling
                // a_n = ((sqrt(3)+1)/sqrt(2)) * a1_n
                // d_n = ((sqrt(3)-1)/sqrt(2)) * d2_n
                // ----------------------------------------------------
                mult_a4 = a1_prev * ALPHA4;
                mult_a5 = d2_curr * ALPHA5;

                approx_out <= mult_a4 >>> FRAC;
                detail_out <= mult_a5 >>> FRAC;
            end
        end
    end

endmodule
