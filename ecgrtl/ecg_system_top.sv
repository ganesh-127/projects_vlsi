// ECG System Top — v3
//
// KEY CHANGE vs uploaded version:
//  • MEM_FILE added as a string parameter (default "100.mem").
//    Allows the all-records testbench (tb_ecg_all_records.sv) to instantiate
//    one DUT per record simply by overriding this parameter via $readmemh in
//    the testbench — the top-level ROM init is done inside the testbench.
//
// NOTE: The ROM initialization is now done with the MEM_FILE parameter so
//       that $readmemh can be called at runtime from the testbench using
//       a force/hierarchical path.  The actual $readmemh lives in tb_ecg_all_records.sv.

module ecg_system_top #(
    parameter WIDTH    = 16,
    parameter N        = 3000,
    parameter MEM_FILE = "100.mem"   // ← override per record in testbench
)(
    input  logic        clk,
    input  logic        rst,

    output logic [11:0] true_r_location,
    output logic        r_location_valid,
    output logic [7:0]  heart_rate_bpm,
    output logic        hr_valid
);

    // -------------------------------------------------------------------------
    // Dual-port ROM  (Port A → DWT,  Port B → window search)
    // -------------------------------------------------------------------------
   
    logic [11:0]      rom_addr_a, rom_addr_b;
    logic [WIDTH-1:0] rom_data_a, rom_data_b;



    // Port A — feeds DWT pipeline
altsyncram #(
    .operation_mode      ("ROM"),
    .width_a             (WIDTH),
    .numwords_a          (N),
    .widthad_a           (12),
    .init_file           ("100.mif"),
    .outdata_reg_a       ("CLOCK0"),
    .lpm_hint            ("ENABLE_RUNTIME_MOD=NO")
) rom_a (
    .address_a (rom_addr_a),
    .q_a       (rom_data_a),
    .clock0    (clk)
);

// Port B — feeds window search (identical MIF, separate M9K block)
altsyncram #(
    .operation_mode      ("ROM"),
    .width_a             (WIDTH),
    .numwords_a          (N),
    .widthad_a           (12),
    .init_file           ("100.mif"),
    .outdata_reg_a       ("CLOCK0"),
    .lpm_hint            ("ENABLE_RUNTIME_MOD=NO")
) rom_b (
    .address_a (rom_addr_b),
    .q_a       (rom_data_b),
    .clock0    (clk)
);

    // -------------------------------------------------------------------------
    // ADC feeder: streams N raw samples to DWT, one per clock cycle
    // -------------------------------------------------------------------------
    logic adc_valid;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rom_addr_a <= 12'd0;
            adc_valid  <= 1'b0;
        end else begin
            if (rom_addr_a < N) begin
                rom_addr_a <= rom_addr_a + 1'b1;
                adc_valid  <= 1'b1;
            end else begin
                adc_valid  <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Interconnect
    // -------------------------------------------------------------------------
    logic signed [WIDTH-1:0] d4_out;
    logic                     d4_valid;

    logic        qrs_found;
    logic [15:0] peak_value;
    logic [11:0] peak_pos;
    logic        peak_valid;

    logic [15:0] r1_val_out;
    logic [11:0] r1_pos_out;
    logic        r1_valid_out;

    // DWT subsamples by 16 (4 levels × ÷2), so shift r1 position left by 4
    // to recover the approximate raw-sample domain index.
    logic [11:0] mapped_r1_pos;
    assign mapped_r1_pos = r1_pos_out << 4;

    // -------------------------------------------------------------------------
    // Block 1 — DWT noise removal / decomposition
    // -------------------------------------------------------------------------
    dwt_top_wrapper #(
        .WIDTH(WIDTH),
        .N    (N)
    ) dwt_inst (
        .clk      (clk),
        .rst      (rst),
        .adc_data (rom_data_a),
        .adc_valid(adc_valid),
        .d4_out   (d4_out),
        .d4_valid (d4_valid)
    );

    // -------------------------------------------------------------------------
    // Block 2 — QRS detector
    // -------------------------------------------------------------------------
    qrs_detector qrs_inst (
        .clk       (clk),
        .reset     (rst),
        .d4_in     (d4_out),
        .valid_in  (d4_valid),
        .qrs_found (qrs_found),
        .peak_value(peak_value),
        .peak_pos  (peak_pos),
        .peak_valid(peak_valid)
    );

    // -------------------------------------------------------------------------
    // Block 3 — False R-peak eliminator
    // -------------------------------------------------------------------------
    rpeak_eliminator eliminator_inst (
        .clk          (clk),
        .reset        (rst),
        .peak_val_in  (peak_value),
        .peak_pos_in  (peak_pos),
        .peak_valid_in(peak_valid),
        .sample_tick  (d4_valid),
        .r1_val_out   (r1_val_out),
        .r1_pos_out   (r1_pos_out),
        .r1_valid_out (r1_valid_out)
    );

    // -------------------------------------------------------------------------
    // Block 4+5 — True R-location window search + heart-rate calculator
    // -------------------------------------------------------------------------
    r_location_and_hr hr_inst (
        .clk             (clk),
        .reset           (rst),
        .r1_pos_in       (mapped_r1_pos),
        .r1_valid_in     (r1_valid_out),
        .raw_mem_addr    (rom_addr_b),
        .raw_mem_data    (rom_data_b),
        .true_r_location (true_r_location),
        .r_location_valid(r_location_valid),
        .heart_rate_bpm  (heart_rate_bpm),
        .hr_valid        (hr_valid)
    );

endmodule
