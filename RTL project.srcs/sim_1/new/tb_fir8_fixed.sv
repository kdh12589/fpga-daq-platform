`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/22 11:50:13
// Design Name: 
// Module Name: tb_fir8_fixed
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1ns/1ps

module tb_fir8_fixed;

    localparam int DATA_WIDTH = 16;
    localparam int FRAC_BITS  = 15;
    localparam int TAPS       = 8;

    logic clk;
    logic rst;

    logic signed [DATA_WIDTH-1:0] in_data;
    logic                         in_valid;
    logic                         in_ready;

    logic signed [DATA_WIDTH-1:0] out_data;
    logic                         out_valid;
    logic                         out_ready;

    // ------------------------------------------------------------
    // Golden model state
    // ------------------------------------------------------------

    longint signed model_hist [0:TAPS-2];
    longint signed expected_q[$];

    integer error_count;
    integer input_count;
    integer output_count;

    logic stall_seen;
    logic pos_sat_seen;
    logic neg_sat_seen;
    logic random_bp_en;

    integer i;


    // ============================================================
    // DUT
    // ============================================================

    fir8_fixed dut (
        .clk       (clk),
        .rst       (rst),

        .in_data   (in_data),
        .in_valid  (in_valid),
        .in_ready  (in_ready),

        .out_data  (out_data),
        .out_valid (out_valid),
        .out_ready (out_ready)
    );


    // ============================================================
    // 100 MHz clock
    // ============================================================

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end


    // ============================================================
    // Golden coefficients
    //
    // Q1.15 integer representation
    // ============================================================

    function automatic longint signed coef_model(input integer index);

        begin
            case (index)

                0: coef_model = -236;
                1: coef_model = 0;
                2: coef_model = 4426;
                3: coef_model = 12194;
                4: coef_model = 12194;
                5: coef_model = 4426;
                6: coef_model = 0;
                7: coef_model = -236;

                default:
                    coef_model = 0;

            endcase
        end

    endfunction


    // ============================================================
    // Independent 64-bit Golden FIR model
    //
    // RTL처럼 35-bit accumulator를 그대로 흉내내는 것이 아니라
    // 넉넉한 64-bit integer math로 expected value를 계산한다.
    // ============================================================

    function automatic longint signed golden_filter(
        input longint signed current_sample
    );

        longint signed acc;
        longint signed scaled;
        integer k;

        begin

            // h0 * x[n]
            acc = current_sample * coef_model(0);

            // h1*x[n-1] ... h7*x[n-7]
            for (k = 1; k < TAPS; k = k + 1) begin

                acc = acc +
                      model_hist[k-1] * coef_model(k);

            end


            // ----------------------------------------------------
            // Symmetric rounding + Q1.15 scale restoration
            // ----------------------------------------------------

            if (acc >= 0) begin

                scaled =
                    (acc + (64'sd1 <<< (FRAC_BITS-1)))
                    >>> FRAC_BITS;

            end
            else begin

                scaled =
                    -((
                        (-acc) +
                        (64'sd1 <<< (FRAC_BITS-1))
                      )
                      >>> FRAC_BITS);

            end


            // ----------------------------------------------------
            // Signed 16-bit saturation
            // ----------------------------------------------------

            if (scaled > 32767)
                golden_filter = 32767;

            else if (scaled < -32768)
                golden_filter = -32768;

            else
                golden_filter = scaled;

        end

    endfunction


    // ============================================================
    // Send one sample
    //
    // Backpressure가 걸리면 같은 data/valid를 계속 유지한다.
    // 따라서 실제 Ready/Valid source처럼 동작한다.
    // ============================================================

    task automatic send_sample(
        input logic signed [DATA_WIDTH-1:0] value
    );

        begin

            in_data  = value;
            in_valid = 1'b1;

            // 실제 handshake가 일어날 때까지 기다린다.
            do begin
                @(posedge clk);
            end
            while (!in_ready);

            // 다음 sample은 negedge에서 바꾼다.
            // → DUT sampling edge와 race 방지
            @(negedge clk);

        end

    endtask


    // ============================================================
    // Reset helper
    // ============================================================

    task automatic apply_reset;

        begin

            @(negedge clk);

            rst           = 1'b1;
            in_valid      = 1'b0;
            in_data       = '0;
            out_ready     = 1'b0;
            random_bp_en  = 1'b0;

            repeat (4) @(posedge clk);

            @(negedge clk);

            rst       = 1'b0;
            out_ready = 1'b1;

            repeat (2) @(posedge clk);

            @(negedge clk);

        end

    endtask


    // ============================================================
    // Stop source and drain pending FIR output
    // ============================================================

    task automatic stop_and_drain;

        begin

            @(negedge clk);

            random_bp_en = 1'b0;
            in_valid     = 1'b0;
            out_ready    = 1'b1;

            while ((expected_q.size() != 0) || out_valid) begin
                @(posedge clk);
            end

            @(negedge clk);

        end

    endtask


    // ============================================================
    // Random downstream backpressure
    // ============================================================

    always @(negedge clk) begin

        if (random_bp_en) begin

            out_ready = $urandom_range(0, 1);

            if (!out_ready)
                stall_seen = 1'b1;

        end

    end


    // ============================================================
    // Golden model + Scoreboard
    // ============================================================

    always @(posedge clk) begin

        longint signed expected_value;

        if (rst) begin

            expected_q.delete();

            for (i = 0; i < TAPS-1; i = i + 1)
                model_hist[i] = 0;

        end
        else begin

            // ----------------------------------------------------
            // First: check previously generated output
            // ----------------------------------------------------

            if (out_valid && out_ready) begin

                if (expected_q.size() == 0) begin

                    $error(
                        "Unexpected FIR output: %0d",
                        $signed(out_data)
                    );

                    error_count = error_count + 1;

                end
                else begin

                    expected_value = expected_q.pop_front();

                    if ($signed(out_data) !==
                        $signed(expected_value[DATA_WIDTH-1:0])) begin

                        $error(
                            "FIR MISMATCH output=%0d expected=%0d sample=%0d",
                            $signed(out_data),
                            expected_value,
                            output_count
                        );

                        error_count = error_count + 1;

                    end

                    if (expected_value == 32767)
                        pos_sat_seen = 1'b1;

                    if (expected_value == -32768)
                        neg_sat_seen = 1'b1;

                end

                output_count = output_count + 1;

            end


            // ----------------------------------------------------
            // Then: process newly accepted input
            // ----------------------------------------------------

            if (in_valid && in_ready) begin

                expected_value =
                    golden_filter($signed(in_data));

                expected_q.push_back(expected_value);


                // Shift Golden Model history
                for (i = TAPS-2; i > 0; i = i - 1) begin
                    model_hist[i] = model_hist[i-1];
                end

                model_hist[0] = $signed(in_data);

                input_count = input_count + 1;

            end

        end

    end


    // ============================================================
    // Ready/Valid assertion
    //
    // Output이 유효한데 consumer가 못 받으면
    // data + valid 모두 그대로 유지해야 한다.
    // ============================================================

    property p_output_hold_on_stall;

        @(posedge clk)
        disable iff (rst)

        out_valid && !out_ready

        |=> out_valid && $stable(out_data);

    endproperty


    assert property (p_output_hold_on_stall)
    else begin

        $error("FIR output changed during backpressure");
        error_count = error_count + 1;

    end


    // ============================================================
    // Main Test
    // ============================================================

    initial begin

        rst           = 1'b0;
        in_data       = '0;
        in_valid      = 1'b0;
        out_ready     = 1'b0;
        random_bp_en  = 1'b0;

        error_count   = 0;
        input_count   = 0;
        output_count  = 0;

        stall_seen    = 1'b0;
        pos_sat_seen  = 1'b0;
        neg_sat_seen  = 1'b0;


        // ========================================================
        // TEST 1 : IMPULSE RESPONSE
        //
        // [32767, 0, 0, ...]
        //
        // 출력은 FIR coefficient 모양이 되어야 한다.
        // ========================================================

        apply_reset();

        $display("TEST 1 : IMPULSE RESPONSE");

        send_sample(16'sd32767);

        repeat (10)
            send_sample(16'sd0);

        stop_and_drain();


        // ========================================================
        // TEST 2 : STEP RESPONSE
        //
        // constant 10000을 넣으면 transient 이후
        // coefficient sum=1이므로 약 10000으로 수렴해야 한다.
        // ========================================================

        apply_reset();

        $display("TEST 2 : STEP RESPONSE");

        repeat (20)
            send_sample(16'sd10000);

        stop_and_drain();


        // ========================================================
        // TEST 3 : POSITIVE SATURATION
        //
        // 음수 coefficient에는 -32768,
        // 양수 coefficient에는 +32767이 걸리도록 배치.
        //
        // 이상적인 결과 ≈ +33711
        // → +32767 saturation 되어야 한다.
        // ========================================================

        apply_reset();

        $display("TEST 3 : POSITIVE SATURATION");

        send_sample(-16'sd32768);
        send_sample( 16'sd0);
        send_sample( 16'sd32767);
        send_sample( 16'sd32767);
        send_sample( 16'sd32767);
        send_sample( 16'sd32767);
        send_sample( 16'sd0);
        send_sample(-16'sd32768);

        repeat (4)
            send_sample(16'sd0);

        stop_and_drain();


        // ========================================================
        // TEST 4 : NEGATIVE SATURATION
        // ========================================================

        apply_reset();

        $display("TEST 4 : NEGATIVE SATURATION");

        send_sample( 16'sd32767);
        send_sample( 16'sd0);
        send_sample(-16'sd32768);
        send_sample(-16'sd32768);
        send_sample(-16'sd32768);
        send_sample(-16'sd32768);
        send_sample( 16'sd0);
        send_sample( 16'sd32767);

        repeat (4)
            send_sample(16'sd0);

        stop_and_drain();


        // ========================================================
        // TEST 5 : RANDOM DATA + RANDOM BACKPRESSURE
        // ========================================================

        apply_reset();

        $display("TEST 5 : RANDOM BACKPRESSURE");

        random_bp_en = 1'b1;

        repeat (300) begin

            // lower 16 bits를 그대로 signed sample로 사용
            send_sample($urandom);

        end

        stop_and_drain();


        // ========================================================
        // Final checks
        // ========================================================

        if (expected_q.size() != 0) begin

            $error(
                "Expected queue not empty: %0d",
                expected_q.size()
            );

            error_count = error_count + 1;

        end


        if (input_count != output_count) begin

            $error(
                "COUNT MISMATCH input=%0d output=%0d",
                input_count,
                output_count
            );

            error_count = error_count + 1;

        end


        if (!stall_seen) begin

            $error("Random backpressure was never observed");
            error_count = error_count + 1;

        end


        if (!pos_sat_seen) begin

            $error("Positive saturation was never observed");
            error_count = error_count + 1;

        end


        if (!neg_sat_seen) begin

            $error("Negative saturation was never observed");
            error_count = error_count + 1;

        end


        if (error_count == 0) begin

            $display("");
            $display("========================================");
            $display("FIR8_FIXED_TEST_PASS");
            $display("INPUT_SAMPLES  = %0d", input_count);
            $display("OUTPUT_SAMPLES = %0d", output_count);
            $display("STALL_SEEN     = %0d", stall_seen);
            $display("POS_SAT_SEEN   = %0d", pos_sat_seen);
            $display("NEG_SAT_SEEN   = %0d", neg_sat_seen);
            $display("========================================");

        end
        else begin

            $display("");
            $display("========================================");
            $display("FIR8_FIXED_TEST_FAIL");
            $display("ERROR_COUNT = %0d", error_count);
            $display("========================================");

        end

        $finish;

    end

endmodule
