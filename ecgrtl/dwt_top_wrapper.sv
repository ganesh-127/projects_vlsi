module dwt_top_wrapper #(
    parameter WIDTH = 16,
    parameter N = 3000
)(
    input  logic               clk,
    input  logic               rst,
    input  logic signed [WIDTH-1:0] adc_data,
    input  logic               adc_valid,
    output logic signed [WIDTH-1:0] d4_out,
    output logic               d4_valid
);

    logic [2:0] current_level;

    logic signed [WIDTH-1:0] y_even, y_odd;
    logic                     dwt_valid_in;
    logic signed [WIDTH-1:0] approx_out, detail_out;
    logic                     dwt_valid_out;

    // Even/odd split RAM — one read port each, both synthesize as M9K
    localparam HALF_RAM = N / 4;  // 750
    logic signed [WIDTH-1:0] ram_even [0:HALF_RAM-1];
    logic signed [WIDTH-1:0] ram_odd  [0:HALF_RAM-1];
    logic [9:0]  ram_write_addr;  // pair index (0..749)
    logic [9:0]  ram_read_addr;   // pair index (0..749)
    logic        ram_write_odd;   // 0=write even bank, 1=write odd bank

    logic [10:0] pairs_this_level;
    logic [10:0] pair_count;
    logic [10:0] ram_out_count;

    logic signed [WIDTH-1:0] even_buffer;
    logic                     have_even;

    dwt_4level_folded #(
        .WIDTH(WIDTH),
        .FRAC(12)
    ) dwt_core (
        .clk        (clk),
        .rst        (rst),
        .y_even     (y_even),
        .y_odd      (y_odd),
        .valid_in   (dwt_valid_in),
        .approx_out (approx_out),
        .detail_out (detail_out),
        .valid_out  (dwt_valid_out)
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_level    <= 3'd1;
            have_even        <= 1'b0;
            even_buffer      <= '0;
            dwt_valid_in     <= 1'b0;
            ram_write_addr   <= '0;
            ram_read_addr    <= '0;
            ram_write_odd    <= 1'b0;
            ram_out_count    <= '0;
            pair_count       <= '0;
            pairs_this_level <= N >> 1;  // 1500 for Level 1
            d4_valid         <= 1'b0;
            d4_out           <= '0;
        end else begin
            dwt_valid_in <= 1'b0;
            d4_valid     <= 1'b0;

            // -------------------------------------------------------
            // INPUT ROUTING
            // -------------------------------------------------------
            if (current_level == 3'd1) begin
                // Level 1: buffer ADC samples into even/odd pairs
                if (adc_valid) begin
                    if (!have_even) begin
                        even_buffer <= adc_data;
                        have_even   <= 1'b1;
                    end else begin
                        y_even       <= even_buffer;  // ADC even sample
                        y_odd        <= adc_data;      // ADC odd sample
                        dwt_valid_in <= 1'b1;
                        have_even    <= 1'b0;
                        pair_count   <= pair_count + 1'b1;
                    end
                end
            end else begin
                // Levels 2-4: read one pair per cycle from split RAM banks
                if (pair_count < pairs_this_level) begin
                    y_even        <= ram_even[ram_read_addr]; // one read port
                    y_odd         <= ram_odd [ram_read_addr]; // one read port
                    dwt_valid_in  <= 1'b1;
                    ram_read_addr <= ram_read_addr + 1'b1;    // single increment
                    pair_count    <= pair_count + 1'b1;
                end
            end

            // -------------------------------------------------------
            // OUTPUT ROUTING
            // -------------------------------------------------------
            if (dwt_valid_out) begin
                if (current_level < 3'd4) begin
                    // Alternate writes between even and odd banks
                    if (!ram_write_odd)
                        ram_even[ram_write_addr] <= approx_out;
                    else begin
                        ram_odd[ram_write_addr]  <= approx_out;
                        ram_write_addr <= ram_write_addr + 1'b1; // advance after odd
                    end
                    ram_write_odd <= ~ram_write_odd;
                    ram_out_count <= ram_out_count + 1'b1;

                    // Level transition: all approx outputs for this level done
                    if (ram_out_count + 1'b1 == pairs_this_level) begin
                        current_level    <= current_level + 1'b1;
                        ram_read_addr    <= '0;
                        ram_write_addr   <= '0;
                        ram_write_odd    <= 1'b0;  // reset write phase
                        ram_out_count    <= '0;
                        pair_count       <= '0;
                        have_even        <= 1'b0;
                        pairs_this_level <= pairs_this_level >> 1;
                    end
                end else begin
                    // Level 4: emit d4 detail coefficients
                    d4_out   <= detail_out;
                    d4_valid <= 1'b1;
                end
            end
        end
    end

endmodule
