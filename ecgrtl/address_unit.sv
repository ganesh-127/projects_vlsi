module address_unit #(
    parameter N = 3000  // total samples
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic [3:0]  START,      // START[0..3] for levels 0..3
    output logic [11:0] ADDRESS,
    output logic [3:0]  START_OUT,  // next START signals
    output logic        SE1, SE2    // encoder outputs (mux select)
);
    // --- 4:2 Priority Encoder ---
    always_comb begin
        SE1 = 1'b0; SE2 = 1'b0;
        if      (START[0]) begin SE1 = 0; SE2 = 0; end
        else if (START[1]) begin SE1 = 0; SE2 = 1; end
        else if (START[2]) begin SE1 = 1; SE2 = 0; end
        else if (START[3]) begin SE1 = 1; SE2 = 1; end
    end

    // --- 4x1 MUX: selects LOAD value = N, N/2, N/3(approx), N/4 ---
    logic [11:0] load_val;
    always_comb begin
        case ({SE1, SE2})
            2'b00: load_val = N[11:0];
            2'b01: load_val = (N >> 1);
            2'b10: load_val = (N >> 2);   // level 3: N/4 approx
            2'b11: load_val = (N >> 2);   // level 4: N/4
            default: load_val = N[11:0];
        endcase
    end

    // --- 11-bit Loadable Counter ---
    logic [11:0] counter;
    logic        load;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter    <= 12'd0;
            START_OUT  <= 4'b0001;
            load       <= 1'b1;
        end else if (load) begin
            counter <= load_val;
            load    <= 1'b0;
        end else if (counter > 12'd0) begin
            counter <= counter - 1'b1;
        end else begin
            // Roll to next START level
            START_OUT <= {START_OUT[2:0], START_OUT[3]};
            load      <= 1'b1;
        end
    end

    assign ADDRESS = load_val - counter;
endmodule
