// sram_top.sv — BIST-Enabled SRAM Controller with Signal Tap Probes
// TB_MODE=1: Testbench mode (external AHB drive)
// TB_MODE=0: FPGA mode with internal sequencer and pushbutton controls
`timescale 1ns/1ps

module sram_top #(
    parameter TB_MODE = 0  // 1=testbench, 0=FPGA standalone
)(
    // Clock & Reset
    input  logic        hclk,
    input  logic        hresetn,

    // === Testbench AHB ports (TB_MODE=1) ===
    input  logic [31:0] haddr_tb,
    input  logic        hwrite_tb,
    input  logic [2:0]  hsize_tb,
    input  logic [31:0] hwdata_tb,
    input  logic        htrans_valid_tb,    // Transfer valid flag
    input  logic        bist_enable_tb,

    // === Pushbutton inputs (TB_MODE=0, FPGA mode) ===
    input  logic        btn_bist_start,     // Start BIST when pressed
    input  logic        btn_access,         // Trigger single AHB access
    input  logic        btn_test_auto,      // Start auto-test sequencer

    // === LED outputs (for FPGA demo) ===
    output logic        led_test_pass,      // Green: test passed
    output logic        led_test_fail,      // Red: test failed
    output logic        led_bist_active,    // Yellow: BIST running

    // === Status outputs (both modes) ===
    output logic        bist_done,
    output logic        bist_fail,
    output logic        clk_en,
    output logic        iso,
    output logic        ret,
    output logic        shutdown,
    output logic        tap_test_pass,
    output logic        tap_test_fail,

    // AHB read data output (needed by TB)
    output logic [31:0] hrdata_out,
    output logic        hready_out,

    // === Signal Tap Probe Ports ===
    output logic [7:0]  tap_sram_addr,
    output logic [31:0] tap_sram_wdata,
    output logic [31:0] tap_sram_rdata,
    output logic        tap_we_n,
    output logic        tap_cs_n,
    output logic [3:0]  tap_be,
    output logic [3:0]  tap_bist_mode,
    output logic [7:0]  tap_bist_step,
    output logic [3:0]  tap_phase_id
);

    // =========================================================
    // Internal AHB bus signals
    // =========================================================
    logic [31:0] haddr;
    logic        hwrite;
    logic [2:0]  hsize;
    logic [31:0] hwdata;
    logic        htrans_valid;
    logic [31:0] hrdata;
    logic        hready;
    logic [1:0]  hresp;
    logic        bist_enable;

    // Synchronized buttons (replaces external debounce)
    logic bist_btn_sync_0, bist_btn_sync_1, bist_btn_deb;
    logic access_btn_sync_0, access_btn_sync_1, access_btn_deb;
    logic auto_btn_sync_0, auto_btn_sync_1, auto_btn_deb;
    
    // Pulse generators
    logic bist_btn_r, access_btn_r, auto_btn_r;
    logic bist_btn_pulse, access_btn_pulse, auto_btn_pulse;

    // Internal wires: AHB controller → MUX
    logic [7:0]  ctrl_addr;
    logic [31:0] ctrl_wdata;
    logic        ctrl_we_n, ctrl_cs_n;
    logic [3:0]  ctrl_be;

    // Internal wires: BIST controller → MUX
    logic [7:0]  bist_addr;
    logic [31:0] bist_wdata;
    logic        bist_we_n, bist_cs_n;

    // Internal wires: MUX → SRAM
    logic [7:0]  sram_addr;
    logic [31:0] sram_wdata;
    logic        sram_we_n, sram_cs_n;
    logic [3:0]  sram_be;
    logic [31:0] sram_rdata;

    // Access request for power management
    logic        access_req;

    // Auto-test state
    logic        auto_test_active;

    assign hrdata_out = hrdata;
    assign hready_out = hready;
    assign access_req = htrans_valid || bist_enable || auto_test_active;

    // =========================================================
    // Button Synchronization (replaces external debounce.sv)
    // =========================================================
    always_ff @(posedge hclk or negedge hresetn) begin
        if (!hresetn) begin
            bist_btn_sync_0   <= 1'b0; bist_btn_sync_1   <= 1'b0;
            access_btn_sync_0 <= 1'b0; access_btn_sync_1 <= 1'b0;
            auto_btn_sync_0   <= 1'b0; auto_btn_sync_1   <= 1'b0;
            bist_btn_r        <= 1'b0;
            access_btn_r      <= 1'b0;
            auto_btn_r        <= 1'b0;
        end else begin
            // Double-flop synchronizers
            bist_btn_sync_0   <= btn_bist_start;
            bist_btn_sync_1   <= bist_btn_sync_0;
            access_btn_sync_0 <= btn_access;
            access_btn_sync_1 <= access_btn_sync_0;
            auto_btn_sync_0   <= btn_test_auto;
            auto_btn_sync_1   <= auto_btn_sync_0;
            
            // Pulse detection (rising edge)
            bist_btn_r        <= bist_btn_sync_1;
            access_btn_r      <= access_btn_sync_1;
            auto_btn_r        <= auto_btn_sync_1;
        end
    end

    assign bist_btn_deb     = bist_btn_sync_1;
    assign access_btn_deb   = access_btn_sync_1;
    assign auto_btn_deb     = auto_btn_sync_1;
    assign bist_btn_pulse   = bist_btn_sync_1 && !bist_btn_r;
    assign access_btn_pulse = access_btn_sync_1 && !access_btn_r;
    assign auto_btn_pulse   = auto_btn_sync_1 && !auto_btn_r;

    // =========================================================
    // AHB Bus Source Selection
    // =========================================================
    generate
        if (TB_MODE == 1) begin : gen_tb_mode
            // TB drives AHB signals directly
            assign haddr        = haddr_tb;
            assign hwrite       = hwrite_tb;
            assign hsize        = hsize_tb;
            assign hwdata       = hwdata_tb;
            assign htrans_valid = htrans_valid_tb;
            assign bist_enable  = bist_enable_tb;
            assign tap_phase_id  = 4'h0;
            assign tap_test_pass = 1'b0;
            assign tap_test_fail = 1'b0;
            assign auto_test_active = 1'b0;
        end else begin : gen_fpga_mode
            // Internal sequencer + manual button control
            logic [3:0] seq_phase_id;
            logic       seq_test_pass, seq_test_fail;
            logic       seq_htrans_valid;

            // Auto-test sequencer
            test_sequencer u_seq (
                .clk           (hclk),
                .rst_n         (hresetn),
                .haddr         (haddr),
                .hwrite        (hwrite),
                .hsize         (hsize),
                .hwdata        (hwdata),
                .htrans_valid  (seq_htrans_valid),
                .bist_enable   (bist_enable),
                .bist_done     (bist_done),
                .bist_fail     (bist_fail),
                .hrdata        (hrdata),
                .hready        (hready),
                .phase_id      (seq_phase_id),
                .test_pass     (seq_test_pass),
                .test_fail_flag(seq_test_fail),
                .auto_start    (auto_btn_deb)
            );

            assign htrans_valid     = seq_htrans_valid;
            assign tap_phase_id     = seq_phase_id;
            assign tap_test_pass    = seq_test_pass;
            assign tap_test_fail    = seq_test_fail;
            assign auto_test_active = (seq_phase_id != 4'd0);

            // LED outputs
            assign led_test_pass    = seq_test_pass;
            assign led_test_fail    = seq_test_fail;
            assign led_bist_active  = bist_enable;
        end
    endgenerate

    // =========================================================
    // AHB-Lite SRAM Controller
    // =========================================================
    ahblite_sram_ctrl u_ctrl (
        .hclk        (hclk),
        .hresetn     (hresetn),
        .haddr       (haddr),
        .hwrite      (hwrite),
        .hsize       (hsize),
        .htrans_valid(htrans_valid),
        .hwdata      (hwdata),
        .hrdata      (hrdata),
        .hready      (hready),
        .hresp       (hresp),
        .cs_n        (ctrl_cs_n),
        .we_n        (ctrl_we_n),
        .be          (ctrl_be),
        .sram_addr   (ctrl_addr),
        .sram_wdata  (ctrl_wdata),
        .sram_rdata  (sram_rdata)
    );

    // =========================================================
    // BIST Controller
    // =========================================================
    bist_ctrl u_bist (
        .clk         (hclk),
        .rst_n       (hresetn),
        .bist_enable (bist_enable),
        .bist_addr   (bist_addr),
        .bist_wdata  (bist_wdata),
        .bist_we_n   (bist_we_n),
        .bist_cs_n   (bist_cs_n),
        .bist_rdata  (sram_rdata),
        .bist_done   (bist_done),
        .bist_fail   (bist_fail),
        .bist_mode   (tap_bist_mode),
        .bist_step   (tap_bist_step)
    );

    // =========================================================
    // SRAM MUX: selects between AHB Controller and BIST
    // =========================================================
    sram_mux u_mux (
        .bist_enable (bist_enable),
        .ctrl_addr   (ctrl_addr),
        .ctrl_wdata  (ctrl_wdata),
        .ctrl_we_n   (ctrl_we_n),
        .ctrl_cs_n   (ctrl_cs_n),
        .ctrl_be     (ctrl_be),
        .bist_addr   (bist_addr),
        .bist_wdata  (bist_wdata),
        .bist_we_n   (bist_we_n),
        .bist_cs_n   (bist_cs_n),
        .sram_addr   (sram_addr),
        .sram_wdata  (sram_wdata),
        .sram_we_n   (sram_we_n),
        .sram_cs_n   (sram_cs_n),
        .sram_be     (sram_be)
    );

    // =========================================================
    // SRAM Array (256 x 32-bit = 1 KB)
    // =========================================================
    sram_array u_sram (
        .clk        (hclk),
        .rst_n      (hresetn),
        .clk_en     (clk_en),
        .cs_n       (sram_cs_n),
        .we_n       (sram_we_n),
        .be         (sram_be),
        .sram_addr  (sram_addr),
        .sram_wdata (sram_wdata),
        .sram_rdata (sram_rdata)
    );

    // =========================================================
    // Power Management FSM
    // =========================================================
    power_mgmt u_pwr (
        .clk         (hclk),
        .rst_n       (hresetn),
        .bist_enable (bist_enable),
        .access_req  (access_req),
        .clk_en      (clk_en),
        .iso         (iso),
        .ret         (ret),
        .shutdown    (shutdown)
    );

    // =========================================================
    // Signal Tap probes — registered for stable Quartus SignalTap capture
    // FIX: tap_cs_n and tap_we_n are now registered (FF Q outputs).
    // Combinational-only signals lose their netlist node after fitting
    // and show as X/red in Signal Tap. Registering them guarantees
    // Quartus always preserves the node name.  The 1-cycle latency on
    // these probe wires has zero effect on functional logic.
    // =========================================================
    assign tap_sram_addr  = sram_addr;
    assign tap_sram_wdata = sram_wdata;
    assign tap_sram_rdata = sram_rdata;
    assign tap_be         = sram_be;

    always_ff @(posedge hclk or negedge hresetn) begin
        if (!hresetn) begin
            tap_cs_n <= 1'b1;   // Deasserted (active-low) at reset
            tap_we_n <= 1'b1;   // Deasserted (active-low) at reset
        end else begin
            tap_cs_n <= sram_cs_n;
            tap_we_n <= sram_we_n;
        end
    end

    // =========================================================
    // Default LED values for TB mode
    // =========================================================
    generate
        if (TB_MODE == 1) begin : gen_tb_leds
            assign led_test_pass   = 1'b0;
            assign led_test_fail   = 1'b0;
            assign led_bist_active = bist_enable;
        end
    endgenerate

endmodule
