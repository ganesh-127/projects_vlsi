
`timescale 1ns/1ps

module fpga_top (
    input  logic        CLOCK_50,       // 50 MHz oscillator
    input  logic [1:0]  KEY,            // KEY[0]=reset, KEY[1]=auto_test
    input  logic [9:0]  SW,             // SW[0]=bist, SW[1]=access
    output logic [9:0]  LEDR            // Status LEDs
);

  
    (* keep, noprune *) wire [7:0]  tap_sram_addr;
    (* keep, noprune *) wire [31:0] tap_sram_wdata;
    (* keep, noprune *) wire [31:0] tap_sram_rdata;
    (* keep, noprune *) wire        tap_we_n;       // now registered in sram_top
    (* keep, noprune *) wire        tap_cs_n;       // now registered in sram_top
    (* keep, noprune *) wire [3:0]  tap_be;
    (* keep, noprune *) wire [3:0]  tap_bist_mode;
    (* keep, noprune *) wire [7:0]  tap_bist_step;
    (* keep, noprune *) wire [3:0]  tap_phase_id;
    (* keep, noprune *) wire        tap_test_pass;
    (* keep, noprune *) wire        tap_test_fail;
    (* keep, noprune *) wire [31:0] hrdata_out_w;
    (* keep, noprune *) wire        hready_out_w;

    // Status wires
    wire bist_done_w, bist_fail_w;
    wire clk_en_w, iso_w, ret_w, shutdown_w;

    sram_top #(.TB_MODE(0)) u_sram_top (
        .hclk            (CLOCK_50),
        .hresetn         (KEY[0]),
        // TB ports — tied off
        .haddr_tb        (32'h0),
        .hwrite_tb       (1'b0),
        .hsize_tb        (3'b0),
        .hwdata_tb       (32'h0),
        .htrans_valid_tb (1'b0),
        .bist_enable_tb  (1'b0),
        // FPGA inputs
        .btn_bist_start  (SW[0]),
        .btn_access      (SW[1]),
        .btn_test_auto   (~KEY[1]),       // Invert: KEY is active-low
        // LEDs
        .led_test_pass   (LEDR[0]),
        .led_test_fail   (LEDR[1]),
        .led_bist_active (LEDR[2]),
        // Status
        .bist_done       (bist_done_w),
        .bist_fail       (bist_fail_w),
        .clk_en          (clk_en_w),
        .iso             (iso_w),
        .ret             (ret_w),
        .shutdown        (shutdown_w),
        .tap_test_pass   (tap_test_pass),
        .tap_test_fail   (tap_test_fail),
        .hrdata_out      (hrdata_out_w),
        .hready_out      (hready_out_w),
        // Signal Tap probes
        .tap_sram_addr   (tap_sram_addr),
        .tap_sram_wdata  (tap_sram_wdata),
        .tap_sram_rdata  (tap_sram_rdata),
        .tap_we_n        (tap_we_n),
        .tap_cs_n        (tap_cs_n),
        .tap_be          (tap_be),
        .tap_bist_mode   (tap_bist_mode),
        .tap_bist_step   (tap_bist_step),
        .tap_phase_id    (tap_phase_id)
    );

    assign LEDR[3] = bist_done_w;
    assign LEDR[4] = bist_fail_w;
    assign LEDR[5] = clk_en_w;
    assign LEDR[6] = iso_w;
    assign LEDR[7] = ret_w;
    assign LEDR[8] = shutdown_w;
    assign LEDR[9] = tap_test_pass;

endmodule
