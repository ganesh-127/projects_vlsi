`timescale 1ns/1ps
//=============================================================================
// tb_sram_top.sv — Comprehensive Testbench for BIST-Enabled SRAM
// Tests: Reset, Word R/W, Sequential R/W, Byte writes (all lanes),
//        Halfword writes, Boundary addresses, Overwrite, Data patterns,
//        Walking 1s/0s, Checkerboard, BIST March-C, Post-BIST integrity,
//        BIST done clears, Power FSM transitions, MUX isolation,
//        Back-to-back writes, Address aliasing, Read-after-BIST
// No assertions or scoreboard — uses simple pass/fail checking with $display
//=============================================================================
module tb_sram_top;

    // =========================================================
    // Clock & Reset
    // =========================================================
    logic        hclk;
    logic        hresetn;

    // =========================================================
    // TB → DUT AHB ports
    // =========================================================
    logic [31:0] haddr_tb;
    logic        hwrite_tb;
    logic [2:0]  hsize_tb;
    logic [31:0] hwdata_tb;
    logic        htrans_valid_tb;
    logic        bist_enable_tb;

    // =========================================================
    // DUT → TB outputs
    // =========================================================
    logic [31:0] hrdata_out;
    logic        hready_out;
    logic        bist_done;
    logic        bist_fail;
    logic        clk_en;
    logic        iso;
    logic        ret;
    logic        shutdown;
    logic        tap_test_pass;
    logic        tap_test_fail;
    logic [7:0]  tap_sram_addr;
    logic [31:0] tap_sram_wdata;
    logic [31:0] tap_sram_rdata;
    logic        tap_we_n;
    logic        tap_cs_n;
    logic [3:0]  tap_be;
    logic [3:0]  tap_bist_mode;
    logic [7:0]  tap_bist_step;
    logic [3:0]  tap_phase_id;

    // Test counters
    integer pass_count = 0;
    integer fail_count = 0;
    integer test_num   = 0;

    // =========================================================
    // Clock Generation: 50 MHz (20ns period)
    // =========================================================
    initial hclk = 0;
    always #10 hclk = ~hclk;

    // =========================================================
    // DUT Instantiation: TB_MODE=1
    // =========================================================
    sram_top #(.TB_MODE(1)) DUT (
        .hclk            (hclk),
        .hresetn         (hresetn),
        // TB AHB ports
        .haddr_tb        (haddr_tb),
        .hwrite_tb       (hwrite_tb),
        .hsize_tb        (hsize_tb),
        .hwdata_tb       (hwdata_tb),
        .htrans_valid_tb (htrans_valid_tb),
        .bist_enable_tb  (bist_enable_tb),
        // Buttons (unused in TB_MODE=1)
        .btn_bist_start  (1'b0),
        .btn_access      (1'b0),
        .btn_test_auto   (1'b0),
        // LED outputs
        .led_test_pass   (),
        .led_test_fail   (),
        .led_bist_active (),
        // Status outputs
        .bist_done       (bist_done),
        .bist_fail       (bist_fail),
        .clk_en          (clk_en),
        .iso             (iso),
        .ret             (ret),
        .shutdown        (shutdown),
        .tap_test_pass   (tap_test_pass),
        .tap_test_fail   (tap_test_fail),
        .hrdata_out      (hrdata_out),
        .hready_out      (hready_out),
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

    // =========================================================
    // AHB TRANSACTION TASKS
    // =========================================================

    // --- Word Write (32-bit) ---
    task automatic ahb_write_word(input logic [31:0] addr, input logic [31:0] data);
        @(posedge hclk); #1;
        haddr_tb        = addr;
        hwrite_tb       = 1'b1;
        hsize_tb        = 3'b010;
        hwdata_tb       = data;
        htrans_valid_tb = 1'b1;
        @(posedge hclk); #1;
        haddr_tb        = 32'h0;
        hwrite_tb       = 1'b0;
        htrans_valid_tb = 1'b0;
        @(posedge hclk); #1;
        hwdata_tb       = 32'h0;
        @(posedge hclk);
    endtask

    // --- Byte Write (8-bit) ---
    task automatic ahb_write_byte(input logic [31:0] addr, input logic [7:0] data);
        @(posedge hclk); #1;
        haddr_tb        = addr;
        hwrite_tb       = 1'b1;
        hsize_tb        = 3'b000;
        hwdata_tb       = {data, data, data, data};
        htrans_valid_tb = 1'b1;
        @(posedge hclk); #1;
        haddr_tb        = 32'h0;
        hwrite_tb       = 1'b0;
        htrans_valid_tb = 1'b0;
        @(posedge hclk); #1;
        hwdata_tb       = 32'h0;
        @(posedge hclk);
    endtask

    // --- Halfword Write (16-bit) ---
    task automatic ahb_write_half(input logic [31:0] addr, input logic [15:0] data);
        @(posedge hclk); #1;
        haddr_tb        = addr;
        hwrite_tb       = 1'b1;
        hsize_tb        = 3'b001;
        hwdata_tb       = {data, data};
        htrans_valid_tb = 1'b1;
        @(posedge hclk); #1;
        haddr_tb        = 32'h0;
        hwrite_tb       = 1'b0;
        htrans_valid_tb = 1'b0;
        @(posedge hclk); #1;
        hwdata_tb       = 32'h0;
        @(posedge hclk);
    endtask

    // --- Read (any size) ---
    task automatic ahb_read(
        input  logic [31:0] addr,
        input  logic [2:0]  size,
        output logic [31:0] rdata
    );
        @(posedge hclk); #1;
        haddr_tb        <= addr;
        hwrite_tb       <= 1'b0;
        hsize_tb        <= size;
        htrans_valid_tb <= 1'b1;
        @(posedge hclk); #1;
        haddr_tb        <= 32'h0;
        htrans_valid_tb <= 1'b0;
        @(posedge hclk); #1;
        rdata = hrdata_out;
        @(posedge hclk);
    endtask

    // --- Run BIST ---
    task automatic run_bist();
        @(posedge hclk); #1;
        bist_enable_tb = 1'b1;
        $display("  [BIST] Started at %0t", $time);
        wait(bist_done == 1'b1);
        @(posedge hclk); #1;
        bist_enable_tb = 1'b0;
        repeat(3) @(posedge hclk);
        $display("  [BIST] Done | bist_fail=%0b", bist_fail);
    endtask

    // --- Check helper ---
    task automatic check(
        input string       name,
        input logic [31:0] got,
        input logic [31:0] exp
    );
        if (got === exp) begin
            $display("    [PASS] %-45s | Got: 0x%08h", name, got);
            pass_count++;
        end else begin
            $display("    [FAIL] %-45s | Got: 0x%08h | Exp: 0x%08h", name, got, exp);
            fail_count++;
        end
    endtask

    // --- Idle bus (for power management testing) ---
    task automatic ahb_idle(input int cycles);
        haddr_tb        = 32'h0;
        hwrite_tb       = 1'b0;
        htrans_valid_tb = 1'b0;
        bist_enable_tb  = 1'b0;
        repeat(cycles) @(posedge hclk);
    endtask

    // =========================================================
    // MAIN TEST SEQUENCE
    // =========================================================
    logic [31:0] rdata;
    integer i;

    initial begin
        // Initialize all inputs
        haddr_tb        = 32'h0;
        hwrite_tb       = 1'b0;
        hsize_tb        = 3'b010;
        hwdata_tb       = 32'h0;
        htrans_valid_tb = 1'b0;
        bist_enable_tb  = 1'b0;
        hresetn         = 1'b0;

        $display("");
        $display("================================================================");
        $display("  BIST-Enabled SRAM Controller — Full Verification Testbench");
        $display("  Target: Cyclone V 5CGXFC7C7F23C8 | Clock: 50 MHz");
        $display("================================================================");

        // =====================================================
        // TEST 1: RESET VERIFICATION
        // =====================================================
        test_num++;
        $display("\n[TEST %0d] Reset Verification", test_num);
        repeat(6) @(posedge hclk);
        hresetn = 1'b1;
        repeat(2) @(posedge hclk);
        check("cs_n=1 after reset",       {31'h0, tap_cs_n},   32'h1);
        check("we_n=1 after reset",       {31'h0, tap_we_n},   32'h1);
        check("bist_fail=0 after reset",  {31'h0, bist_fail},  32'h0);
        check("clk_en=1 after reset",     {31'h0, clk_en},     32'h1);
        check("iso=0 after reset",        {31'h0, iso},         32'h0);
        check("ret=0 after reset",        {31'h0, ret},         32'h0);
        check("shutdown=0 after reset",   {31'h0, shutdown},    32'h0);
        check("hready=1 after reset",     {31'h0, hready_out}, 32'h1);

        // =====================================================
        // TEST 2: SINGLE WORD WRITE & READ
        // =====================================================
        test_num++;
        $display("\n[TEST %0d] Single Word Write & Read", test_num);
        ahb_write_word(32'h00000010, 32'hDEADBEEF);
        ahb_read(32'h00000010, 3'b010, rdata);
        check("Word Write@0x10 → Read", rdata, 32'hDEADBEEF);

        ahb_write_word(32'h00000014, 32'hCAFEBABE);
        ahb_read(32'h00000014, 3'b010, rdata);
        check("Word Write@0x14 → Read", rdata, 32'hCAFEBABE);

        ahb_write_word(32'h00000018, 32'h12345678);
        ahb_read(32'h00000018, 3'b010, rdata);
        check("Word Write@0x18 → Read", rdata, 32'h12345678);

        // =====================================================
        // TEST 3: SEQUENTIAL WORD WRITE & READ (8 locations)
        // =====================================================
        test_num++;
        $display("\n[TEST %0d] Sequential Word Write & Read (8 locations)", test_num);
        for (i = 0; i < 8; i++)
            ahb_write_word(32'h00000020 + (i*4), 32'hA0000000 + i);
        for (i = 0; i < 8; i++) begin
            ahb_read(32'h00000020 + (i*4), 3'b010, rdata);
            check($sformatf("Seq Read @ 0x%02X", 32'h20 + i*4), rdata, 32'hA0000000 + i);
        end

        // =====================================================
        // TEST 4: BYTE WRITE — ALL 4 BYTE LANES
        // =====================================================
        test_num++;
        $display("\n[TEST %0d] Byte Write — All 4 Byte Lanes", test_num);

        // First, write a known word to clear
        ahb_write_word(32'h00000060, 32'h00000000);

        // Byte lane 0
        ahb_write_byte(32'h00000060, 8'hAA);
        ahb_read(32'h00000060, 3'b010, rdata);
        check("Byte Lane 0 @ 0x60", rdata[7:0], 8'hAA);

        // Byte lane 1
        ahb_write_byte(32'h00000061, 8'hBB);
        ahb_read(32'h00000060, 3'b010, rdata);
        check("Byte Lane 1 @ 0x61", rdata[15:8], 8'hBB);

        // Byte lane 2
        ahb_write_byte(32'h00000062, 8'hCC);
        ahb_read(32'h00000060, 3'b010, rdata);
        check("Byte Lane 2 @ 0x62", rdata[23:16], 8'hCC);

        // Byte lane 3
        ahb_write_byte(32'h00000063, 8'hDD);
        ahb_read(32'h00000060, 3'b010, rdata);
        check("Byte Lane 3 @ 0x63", rdata[31:24], 8'hDD);

        // Verify all lanes together
        ahb_read(32'h00000060, 3'b010, rdata);
        check("All byte lanes combined", rdata, 32'hDDCCBBAA);

        // =====================================================
        // TEST 5: HALFWORD WRITE — BOTH LANES
        // =====================================================
        test_num++;
        $display("\n[TEST %0d] Halfword Write — Both Lanes", test_num);

        // Clear the word first
        ahb_write_word(32'h00000070, 32'h00000000);

        // Lower halfword
        ahb_write_half(32'h00000070, 16'hBEEF);
        ahb_read(32'h00000070, 3'b010, rdata);
        check("Halfword Low @ 0x70", rdata[15:0], 16'hBEEF);

        // Upper halfword
        ahb_write_half(32'h00000072, 16'hDEAD);
        ahb_read(32'h00000070, 3'b010, rdata);
        check("Halfword High @ 0x72", rdata[31:16], 16'hDEAD);

        // Verify full word
        ahb_read(32'h00000070, 3'b010, rdata);
        check("Both halfwords combined", rdata, 32'hDEADBEEF);

        // =====================================================
        // TEST 6: BOUNDARY ADDRESS TEST
        // =====================================================
        test_num++;
        $display("\n[TEST %0d] Boundary Address Test", test_num);

        // Address 0x004 (word 1 — first accessible)
        ahb_write_word(32'h00000004, 32'h11111111);
        ahb_read(32'h00000004, 3'b010, rdata);
        check("Boundary Addr 0x004 (word 1)", rdata, 32'h11111111);

        // Address 0x3FC (word 255 — last word)
        ahb_write_word(32'h000003FC, 32'hFFFFFFFF);
        ahb_read(32'h000003FC, 3'b010, rdata);
        check("Boundary Addr 0x3FC (last word)", rdata, 32'hFFFFFFFF);

        // Address 0x200 (mid-range)
        ahb_write_word(32'h00000200, 32'h55AA55AA);
        ahb_read(32'h00000200, 3'b010, rdata);
        check("Mid-range Addr 0x200", rdata, 32'h55AA55AA);

        // =====================================================
        // TEST 7: OVERWRITE SAME ADDRESS
        // =====================================================
        test_num++;
        $display("\n[TEST %0d] Overwrite Same Address", test_num);
        ahb_write_word(32'h00000090, 32'h11111111);
        ahb_write_word(32'h00000090, 32'h22222222);
        ahb_write_word(32'h00000090, 32'h33333333);
        ahb_read(32'h00000090, 3'b010, rdata);
        check("Overwrite → last value held", rdata, 32'h33333333);

        // =====================================================
        // TEST 8: ALL-ZEROS & ALL-ONES PATTERNS
        // =====================================================
        test_num++;
        $display("\n[TEST %0d] All-Zeros & All-Ones Patterns", test_num);
        ahb_write_word(32'h00000094, 32'h00000000);
        ahb_read(32'h00000094, 3'b010, rdata);
        check("All-Zeros @ 0x94", rdata, 32'h00000000);

        ahb_write_word(32'h00000098, 32'hFFFFFFFF);
        ahb_read(32'h00000098, 3'b010, rdata);
        check("All-Ones @ 0x98", rdata, 32'hFFFFFFFF);

        // =====================================================
        // TEST 9: WALKING 1s PATTERN
        // =====================================================
        test_num++;
        $display("\n[TEST %0d] Walking 1s Pattern (32 bits)", test_num);
        for (i = 0; i < 32; i++) begin
            ahb_write_word(32'h00000100, 32'h1 << i);
            ahb_read(32'h00000100, 3'b010, rdata);
            check($sformatf("Walking1 bit[%0d]", i), rdata, 32'h1 << i);
        end

        // =====================================================
        // TEST 10: WALKING 0s PATTERN
        // =====================================================
        test_num++;
        $display("\n[TEST %0d] Walking 0s Pattern (32 bits)", test_num);
        for (i = 0; i < 32; i++) begin
            ahb_write_word(32'h00000104, ~(32'h1 << i));
            ahb_read(32'h00000104, 3'b010, rdata);
            check($sformatf("Walking0 bit[%0d]", i), rdata, ~(32'h1 << i));
        end

        // =====================================================
        // TEST 11: CHECKERBOARD PATTERN
        // =====================================================
        test_num++;
        $display("\n[TEST %0d] Checkerboard Pattern", test_num);
        ahb_write_word(32'h00000108, 32'h5A5A5A5A);
        ahb_read(32'h00000108, 3'b010, rdata);
        check("Checkerboard 0x5A5A5A5A", rdata, 32'h5A5A5A5A);

        ahb_write_word(32'h0000010C, 32'hA5A5A5A5);
        ahb_read(32'h0000010C, 3'b010, rdata);
        check("Checkerboard 0xA5A5A5A5", rdata, 32'hA5A5A5A5);

        // =====================================================
        // TEST 12: BACK-TO-BACK WRITES TO ADJACENT ADDRESSES
        // =====================================================
        test_num++;
        $display("\n[TEST %0d] Back-to-Back Writes (adjacent addresses)", test_num);
        ahb_write_word(32'h000001A0, 32'hAAAA0001);
        ahb_write_word(32'h000001A4, 32'hBBBB0002);
        ahb_write_word(32'h000001A8, 32'hCCCC0003);
        ahb_write_word(32'h000001AC, 32'hDDDD0004);
        ahb_read(32'h000001A0, 3'b010, rdata);
        check("B2B Read @ 0x1A0", rdata, 32'hAAAA0001);
        ahb_read(32'h000001A4, 3'b010, rdata);
        check("B2B Read @ 0x1A4", rdata, 32'hBBBB0002);
        ahb_read(32'h000001A8, 3'b010, rdata);
        check("B2B Read @ 0x1A8", rdata, 32'hCCCC0003);
        ahb_read(32'h000001AC, 3'b010, rdata);
        check("B2B Read @ 0x1AC", rdata, 32'hDDDD0004);

        // =====================================================
        // TEST 13: ADDRESS ALIASING CHECK
        // =====================================================
        test_num++;
        $display("\n[TEST %0d] Address Aliasing Check", test_num);
        // Write to two addresses that map to different SRAM words
        ahb_write_word(32'h00000050, 32'hFACE0050);
        ahb_write_word(32'h00000054, 32'hFACE0054);
        ahb_read(32'h00000050, 3'b010, rdata);
        check("No aliasing: 0x50 unaffected by 0x54 write", rdata, 32'hFACE0050);
        ahb_read(32'h00000054, 3'b010, rdata);
        check("No aliasing: 0x54 holds own data", rdata, 32'hFACE0054);

        // =====================================================
        // TEST 14: FULL BIST MARCH-C RUN
        // =====================================================
        test_num++;
        $display("\n[TEST %0d] Full BIST March-C Run", test_num);
        run_bist();
        check("BIST Pass (bist_fail=0)", {31'h0, bist_fail}, 32'h0);

        // =====================================================
        // TEST 15: POST-BIST INTEGRITY (expect all zeros)
        // =====================================================
        test_num++;
        $display("\n[TEST %0d] Post-BIST Reads (expect all 0x00000000)", test_num);
        for (i = 0; i < 8; i++) begin
            ahb_read(32'h00000004 + (i*4), 3'b010, rdata);
            check($sformatf("Post-BIST @ 0x%02X", 4 + i*4), rdata, 32'h00000000);
        end

        // =====================================================
        // TEST 16: BIST DONE CLEARS AFTER DISABLE
        // =====================================================
        test_num++;
        $display("\n[TEST %0d] bist_done Clears After Disable", test_num);
        @(posedge hclk); #1;
        bist_enable_tb = 1'b1;
        wait(bist_done);
        @(posedge hclk); #1;
        bist_enable_tb = 1'b0;
        repeat(4) @(posedge hclk);
        check("bist_done cleared after disable", {31'h0, bist_done}, 32'h0);

        // =====================================================
        // TEST 17: WRITE & READ AFTER BIST (data path intact)
        // =====================================================
        test_num++;
        $display("\n[TEST %0d] Write & Read After BIST", test_num);
        ahb_write_word(32'h00000080, 32'hAFB15700);
        ahb_read(32'h00000080, 3'b010, rdata);
        check("Write after BIST works", rdata, 32'hAFB15700);

        // =====================================================
        // TEST 18: POWER MANAGEMENT FSM
        // =====================================================
        test_num++;
        $display("\n[TEST %0d] Power Management FSM", test_num);

        // Currently in ACTIVE after recent access
        check("clk_en=1 in ACTIVE", {31'h0, clk_en}, 32'h1);
        check("iso=0 in ACTIVE",    {31'h0, iso},     32'h0);
        check("ret=0 in ACTIVE",    {31'h0, ret},     32'h0);

        // Wait for STANDBY (>1000 idle cycles)
        $display("    [INFO] Waiting for STANDBY (~1100 idle cycles)...");
        ahb_idle(1100);
        check("clk_en=0 in STANDBY", {31'h0, clk_en}, 32'h0);

        // Wait for RETENTION (>5000 total idle cycles)
        $display("    [INFO] Waiting for RETENTION (~4100 more idle cycles)...");
        ahb_idle(4100);
        check("iso=1 in RETENTION", {31'h0, iso}, 32'h1);
        check("ret=1 in RETENTION", {31'h0, ret}, 32'h1);

        // =====================================================
        // TEST 19: WAKE FROM RETENTION
        // =====================================================
        test_num++;
        $display("\n[TEST %0d] Wake from RETENTION", test_num);
        ahb_write_word(32'h00000200, 32'hDACE1234);
        repeat(3) @(posedge hclk);
        check("clk_en=1 after wake", {31'h0, clk_en}, 32'h1);
        check("iso=0 after wake",    {31'h0, iso},     32'h0);
        check("ret=0 after wake",    {31'h0, ret},     32'h0);

        // =====================================================
        // TEST 20: WRITE & READ AFTER RETENTION WAKE
        // =====================================================
        test_num++;
        $display("\n[TEST %0d] Write & Read After Retention Wake", test_num);
        ahb_write_word(32'h000001B0, 32'hBEEFCAFE);
        ahb_read(32'h000001B0, 3'b010, rdata);
        check("Write after retention wake", rdata, 32'hBEEFCAFE);

        // =====================================================
        // TEST 21: MUX ISOLATION CHECK
        // =====================================================
        test_num++;
        $display("\n[TEST %0d] MUX: BIST addr routed when bist_enable=1", test_num);
        ahb_write_word(32'h000000C0, 32'hFACEFACE);
        @(posedge hclk); #1;
        bist_enable_tb = 1'b1;
        repeat(2) @(posedge hclk); #1;
        // When BIST is active, MUX should route BIST address (not AHB)
        check("MUX routes BIST addr",
              {24'h0, tap_sram_addr},
              {24'h0, DUT.u_bist.bist_addr});
        bist_enable_tb = 1'b0;
        repeat(2) @(posedge hclk);

        // =====================================================
        // TEST 22: BYTE ENABLE CORRECTNESS FOR WRITES
        // =====================================================
        test_num++;
        $display("\n[TEST %0d] Byte Enable — Selective Byte Preservation", test_num);
        // Write a full word, then overwrite only one byte
        ahb_write_word(32'h000000D0, 32'h12345678);
        ahb_write_byte(32'h000000D0, 8'hFF);         // Overwrite byte 0 only
        ahb_read(32'h000000D0, 3'b010, rdata);
        check("Byte 0 overwritten, bytes 1-3 preserved", rdata, 32'h123456FF);

        // Overwrite byte 2 only
        ahb_write_byte(32'h000000D2, 8'hEE);
        ahb_read(32'h000000D0, 3'b010, rdata);
        check("Byte 2 overwritten, others preserved", rdata, 32'h12EE56FF);

        // =====================================================
        // TEST 23: HALFWORD BYTE ENABLE PRESERVATION
        // =====================================================
        test_num++;
        $display("\n[TEST %0d] Halfword Byte Enable — Selective Preservation", test_num);
        ahb_write_word(32'h000000D4, 32'hAABBCCDD);
        ahb_write_half(32'h000000D4, 16'h1122);      // Lower halfword
        ahb_read(32'h000000D4, 3'b010, rdata);
        check("Lower half overwritten, upper preserved", rdata, 32'hAABB1122);

        ahb_write_half(32'h000000D6, 16'h3344);      // Upper halfword
        ahb_read(32'h000000D4, 3'b010, rdata);
        check("Upper half overwritten, lower preserved", rdata, 32'h33441122);

        // =====================================================
        // TEST 24: MULTI-PATTERN STRESS TEST
        // =====================================================
        test_num++;
        $display("\n[TEST %0d] Multi-Pattern Stress Test (16 words)", test_num);
        for (i = 0; i < 16; i++)
            ahb_write_word(32'h00000300 + (i*4), 32'hF000_0000 | (i << 8) | i);
        for (i = 0; i < 16; i++) begin
            ahb_read(32'h00000300 + (i*4), 3'b010, rdata);
            check($sformatf("Stress pattern word[%0d]", i),
                  rdata, 32'hF000_0000 | (i << 8) | i);
        end

        // =====================================================
        // TEST 25: SIGNAL TAP PROBE VERIFICATION
        // =====================================================
        test_num++;
        $display("\n[TEST %0d] Signal Tap Probe Verification", test_num);
        // Perform a write and verify tap signals reflect correct values
        @(posedge hclk); #1;
        haddr_tb        = 32'h00000040;
        hwrite_tb       = 1'b1;
        hsize_tb        = 3'b010;
        hwdata_tb       = 32'h7A9E7E57;
        htrans_valid_tb = 1'b1;
        @(posedge hclk); #1;
        // The data phase is NOW active.
        check("tap_cs_n=0 during write", {31'h0, tap_cs_n}, 32'h0);
        check("tap_we_n=0 during write", {31'h0, tap_we_n}, 32'h0);
        check("tap_sram_addr=0x10", {24'h0, tap_sram_addr}, 32'h00000010);  // addr[9:2] = 0x40>>2 = 0x10

        haddr_tb        = 32'h0;
        hwrite_tb       = 1'b0;
        htrans_valid_tb = 1'b0;
        @(posedge hclk); #1;
        @(posedge hclk);
        hwdata_tb = 32'h0;

        // =====================================================
        // TEST 26: RESET MID-OPERATION
        // =====================================================
        test_num++;
        $display("\n[TEST %0d] Reset Mid-Operation", test_num);
        // Start a write, then assert reset
        ahb_write_word(32'h000000E0, 32'hBEF02E00);
        // Assert reset
        @(posedge hclk); #1;
        hresetn = 1'b0;
        repeat(4) @(posedge hclk);
        hresetn = 1'b1;
        repeat(2) @(posedge hclk);
        // Verify controller is back in idle state
        check("cs_n=1 after mid-op reset", {31'h0, tap_cs_n}, 32'h1);
        check("we_n=1 after mid-op reset", {31'h0, tap_we_n}, 32'h1);
        check("clk_en=1 after mid-op reset", {31'h0, clk_en}, 32'h1);

        // =====================================================
        // TEST 27: WRITE AFTER RESET
        // =====================================================
        test_num++;
        $display("\n[TEST %0d] Write & Read After Reset", test_num);
        ahb_write_word(32'h000000F0, 32'h9057F570);
        ahb_read(32'h000000F0, 3'b010, rdata);
        check("Write/Read works after reset", rdata, 32'h9057F570);

        // =====================================================
        // FINAL REPORT
        // =====================================================
        repeat(4) @(posedge hclk);
        $display("");
        $display("================================================================");
        $display("  SIMULATION COMPLETE");
        $display("  Total Tests : %0d", pass_count + fail_count);
        $display("  PASS        : %0d", pass_count);
        $display("  FAIL        : %0d", fail_count);
        if (fail_count == 0)
            $display("  STATUS      : *** ALL TESTS PASSED ***");
        else
            $display("  STATUS      : *** %0d TEST(S) FAILED ***", fail_count);
        $display("================================================================");
        $display("");
        $finish;
    end

    // =========================================================
    // Timeout Watchdog
    // =========================================================
    initial begin
        #100_000_000;
        $display("[WATCHDOG] Timeout after 100ms! Terminating.");
        $finish;
    end

    // =========================================================
    // VCD Waveform Dump
    // =========================================================
    initial begin
        $dumpfile("sram_bist_tb.vcd");
        $dumpvars(0, tb_sram_top);
    end

endmodule
