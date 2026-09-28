
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/22 12:11:33
// Design Name: 
// Module Name: tb_daq_dsp_top
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

module tb_daq_dsp_top;

    localparam int DATA_WIDTH = 16;
    localparam int ADDR_WIDTH = 4;
    localparam int TAPS       = 8;
    localparam int FRAC_BITS  = 15;

    logic acq_clk;
    logic proc_clk;

    logic acq_rst;
    logic proc_rst;

    logic signed [DATA_WIDTH-1:0] out_data;
    logic                         out_valid;
    logic                         out_ready;

    longint signed hist [0:TAPS-2];
    longint signed expected_q[$];

    integer input_seq;
    integer output_count;
    integer error_count;

    logic fifo_full_seen;
    logic backpressure_seen;

    integer i;


    // ============================================================
    // DUT
    // ============================================================

    daq_dsp_top dut (
        .acq_clk   (acq_clk),
        .acq_rst   (acq_rst),

        .proc_clk  (proc_clk),
        .proc_rst  (proc_rst),

        .out_data  (out_data),
        .out_valid (out_valid),
        .out_ready (out_ready)
    );


    // ~83.33 MHz acquisition clock
    initial begin
        acq_clk = 1'b0;
        forever #6 acq_clk = ~acq_clk;
    end

    // 100 MHz processing clock
    initial begin
        proc_clk = 1'b0;
        forever #5 proc_clk = ~proc_clk;
    end


    // ============================================================
    // Coefficients
    // ============================================================

    function automatic longint signed coef(input integer index);

        begin
            case (index)
                0: coef = -236;
                1: coef = 0;
                2: coef = 4426;
                3: coef = 12194;
                4: coef = 12194;
                5: coef = 4426;
                6: coef = 0;
                7: coef = -236;
                default: coef = 0;
            endcase
        end

    endfunction


    // ============================================================
    // Golden FIR model
    // ============================================================

    function automatic longint signed golden_fir(
        input longint signed current_sample
    );

        longint signed acc;
        longint signed scaled;

        integer k;

        begin

            acc = current_sample * coef(0);

            for (k = 1; k < TAPS; k = k + 1)
                acc = acc + hist[k-1] * coef(k);


            // symmetric rounding
            if (acc >= 0)
                scaled =
                    (acc + (64'sd1 <<< (FRAC_BITS-1)))
                    >>> FRAC_BITS;

            else
                scaled =
                    -((
                        (-acc) +
                        (64'sd1 <<< (FRAC_BITS-1))
                      )
                      >>> FRAC_BITS);


            // saturation
            if (scaled > 32767)
                golden_fir = 32767;

            else if (scaled < -32768)
                golden_fir = -32768;

            else
                golden_fir = scaled;

        end

    endfunction


    // ============================================================
    // Main stimulus
    // ============================================================

    initial begin

        acq_rst  = 1'b1;
        proc_rst = 1'b1;

        out_ready = 1'b0;

        input_seq          = 0;
        output_count       = 0;
        error_count        = 0;
        fifo_full_seen     = 1'b0;
        backpressure_seen  = 1'b0;

        for (i = 0; i < TAPS-1; i = i + 1)
            hist[i] = 0;


        // Reset release
        repeat (5) @(posedge acq_clk);

        @(negedge acq_clk);
        acq_rst = 1'b0;


        repeat (5) @(posedge proc_clk);

        @(negedge proc_clk);
        proc_rst = 1'b0;


        // --------------------------------------------------------
        // Phase 1 : Block FIR output
        //
        // backpressure가 전체 시스템을 거슬러 올라가서
        // FIFO FULL까지 가는지 확인
        // --------------------------------------------------------

        repeat (50) begin

            @(negedge proc_clk);
            out_ready = 1'b0;
            backpressure_seen = 1'b1;

        end


        // --------------------------------------------------------
        // Phase 2 : Normal flow
        // --------------------------------------------------------

        repeat (100) begin

            @(negedge proc_clk);
            out_ready = 1'b1;

        end


        // --------------------------------------------------------
        // Phase 3 : Random backpressure
        // --------------------------------------------------------

        repeat (500) begin

            @(negedge proc_clk);

            out_ready = $urandom_range(0,1);

            if (!out_ready)
                backpressure_seen = 1'b1;

        end


        // --------------------------------------------------------
        // Phase 4 : Continuous drain
        // --------------------------------------------------------

        out_ready = 1'b1;

        wait (output_count >= 300);

        repeat (20) @(posedge proc_clk);
        
        $display("PENDING_EXPECTED = %0d", expected_q.size());


        // --------------------------------------------------------
        // Final checks
        // --------------------------------------------------------

        if (error_count == 0 &&
            fifo_full_seen &&
            backpressure_seen) begin

            $display("");
            $display("========================================");
            $display("DAQ_DSP_INTEGRATION_TEST_PASS");
            $display("FIR_INPUT_SAMPLES  = %0d", input_seq);
            $display("FIR_OUTPUT_SAMPLES = %0d", output_count);
            $display("FIFO_FULL_SEEN     = %0d", fifo_full_seen);
            $display("ERROR_COUNT        = %0d", error_count);
            $display("========================================");

        end
        else begin

            $display("");
            $display("========================================");
            $display("DAQ_DSP_INTEGRATION_TEST_FAIL");
            $display("ERROR_COUNT = %0d", error_count);
            $display("FIFO_FULL   = %0d", fifo_full_seen);
            $display("========================================");

        end

        $finish;

    end


    // ============================================================
    // Monitor FIFO -> FIR transfers
    //
    // 여기서 CDC 출력 자체가
    // 0,1,2,3... 순서인지 동시에 확인한다.
    // ============================================================

    always @(posedge proc_clk) begin

        longint signed expected;

        if (!proc_rst) begin

            if (dut.fifo_valid && dut.fifo_ready) begin

                // -----------------------------------------------
                // Async FIFO data-order verification
                // -----------------------------------------------

                if ($signed(dut.fifo_data) !==
                    $signed(input_seq[DATA_WIDTH-1:0])) begin

                    $error(
                        "CDC DATA ERROR expected=%0d actual=%0d",
                        input_seq,
                        $signed(dut.fifo_data)
                    );

                    error_count = error_count + 1;

                end


                // -----------------------------------------------
                // FIR Golden Model
                // -----------------------------------------------

                expected =
                    golden_fir($signed(dut.fifo_data));

                expected_q.push_back(expected);


                // history shift
                for (i = TAPS-2; i > 0; i = i - 1)
                    hist[i] = hist[i-1];

                hist[0] = $signed(dut.fifo_data);


                input_seq = input_seq + 1;

            end


            // -----------------------------------------------
            // FIR output comparison
            // -----------------------------------------------

            if (out_valid && out_ready) begin

                if (expected_q.size() == 0) begin

                    $error("Unexpected FIR output");
                    error_count = error_count + 1;

                end
                else begin

                    expected = expected_q.pop_front();

                    if ($signed(out_data) !==
                        $signed(expected[DATA_WIDTH-1:0])) begin

                        $error(
                            "FIR ERROR expected=%0d actual=%0d",
                            expected,
                            $signed(out_data)
                        );

                        error_count = error_count + 1;

                    end

                end

                output_count = output_count + 1;

            end

        end

    end


    // ============================================================
    // FIFO FULL observation
    // ============================================================

    always @(posedge acq_clk) begin

        if (!acq_rst &&
            dut.u_async_fifo.fifo_full)

            fifo_full_seen <= 1'b1;

    end

endmodule
