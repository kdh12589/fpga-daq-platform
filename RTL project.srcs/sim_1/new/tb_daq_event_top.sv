`timescale 1ns / 1ps

module tb_daq_event_top;

    // ============================================================
    // CLOCK / RESET
    // ============================================================

    logic acq_clk;
    logic acq_rst;

    logic proc_clk;
    logic proc_rst;


    // ============================================================
    // DUT OUTPUTS
    // ============================================================

    logic event_done;
    logic trigger_enable;

    logic [10:0] trigger_ptr;
    logic [10:0] start_ptr;

    logic [10:0] read_addr;
    logic [71:0] read_data;

    logic readout_done;

    logic signed [15:0] aligned_raw;
    logic signed [15:0] aligned_filtered;
    logic [31:0]        aligned_index;
    logic               aligned_valid;

    logic trigger_pulse;


    // ============================================================
    // TEST COUNTERS
    // ============================================================

    integer alignment_errors;
    integer capture_errors;

    integer aligned_samples;
    integer timeout_count;

    integer i;


    // ============================================================
    // DUT
    // ============================================================

    daq_event_top #(
        .DATA_WIDTH      (16),
        .FIFO_ADDR_WIDTH (4),

        .TRIG_LOW        (16'sd1400),
        .TRIG_HIGH       (16'sd1500)
    ) dut (
        .acq_clk          (acq_clk),
        .acq_rst          (acq_rst),

        .proc_clk         (proc_clk),
        .proc_rst         (proc_rst),

        .event_done       (event_done),
        .trigger_enable   (trigger_enable),

        .trigger_ptr      (trigger_ptr),
        .start_ptr        (start_ptr),

        .read_addr        (read_addr),
        .read_data        (read_data),

        .readout_done     (readout_done),

        .aligned_raw      (aligned_raw),
        .aligned_filtered (aligned_filtered),
        .aligned_index    (aligned_index),
        .aligned_valid    (aligned_valid),

        .trigger_pulse    (trigger_pulse)
    );


    // ============================================================
    // CLOCKS
    //
    // Acquisition ≈ 83.3 MHz
    // Processing  = 100 MHz
    // ============================================================

    initial acq_clk = 1'b0;
    always #6 acq_clk = ~acq_clk;

    initial proc_clk = 1'b0;
    always #5 proc_clk = ~proc_clk;


    // ============================================================
    // Expected FIR result for ramp input
    //
    // Coefficients sum = 1
    // effective group delay = 3.5 samples
    //
    // Current rounding implementation:
    //
    // y[n] = n - 3
    //
    // after FIR is fully filled.
    // ============================================================

    function automatic logic signed [15:0]
        expected_filter(
            input logic [31:0] idx
        );

        begin

            expected_filter =
                $signed(idx[15:0]) -
                16'sd3;

        end

    endfunction


    // ============================================================
    // Expected 72-bit event entry
    //
    // { index, flags, raw, filtered }
    // ============================================================

    function automatic logic [71:0]
        expected_entry(
            input logic [31:0] idx
        );

        logic signed [15:0] raw_v;
        logic signed [15:0] filt_v;

        begin

            raw_v =
                $signed(idx[15:0]);

            filt_v =
                expected_filter(idx);

            expected_entry = {
                idx,
                8'h00,
                raw_v,
                filt_v
            };

        end

    endfunction


    // ============================================================
    // Event Memory Read
    //
    // Event Capture memory uses synchronous read.
    // ============================================================

    task automatic read_event(
        input integer offset,
        output logic [71:0] data
    );

        logic [10:0] addr;

        begin

            // 11-bit truncation automatically gives modulo 2048
            addr =
                start_ptr + offset;

            @(negedge proc_clk);

            read_addr = addr;

            @(posedge proc_clk);
            #1;

            data = read_data;

        end

    endtask


    // ============================================================
    // Read and compare one event entry
    // ============================================================

    task automatic check_event_entry(
        input integer offset,
        input logic [31:0] expected_idx
    );

        logic [71:0] actual;
        logic [71:0] expected;

        begin

            read_event(
                offset,
                actual
            );

            expected =
                expected_entry(
                    expected_idx
                );

            if (actual !== expected) begin

                $error(
                    "EVENT DATA ERROR offset=%0d expected_index=%0d",
                    offset,
                    expected_idx
                );

                $display(
                    "ACTUAL   = %h",
                    actual
                );

                $display(
                    "EXPECTED = %h",
                    expected
                );

                capture_errors =
                    capture_errors + 1;

            end

        end

    endtask


    // ============================================================
    // CONTINUOUS ALIGNMENT CHECK
    //
    // FIR output과 sideband가 같은 logical sample인지 검사
    // ============================================================

    always @(posedge proc_clk) begin

        #1;

        if ((!proc_rst) &&
            aligned_valid) begin

            aligned_samples =
                aligned_samples + 1;


            // ----------------------------------------------------
            // RAW / INDEX alignment
            // ----------------------------------------------------

            if (
                aligned_raw !==
                $signed(aligned_index[15:0])
            ) begin

                $error(
                    "RAW ALIGNMENT ERROR index=%0d raw=%0d",
                    aligned_index,
                    aligned_raw
                );

                alignment_errors =
                    alignment_errors + 1;

            end


            // ----------------------------------------------------
            // FIR has full 8-sample history after index 7
            // ----------------------------------------------------

            if (aligned_index >= 32'd7) begin

                if (
                    aligned_filtered !==
                    expected_filter(aligned_index)
                ) begin

                    $error(
                        "FILTER ALIGNMENT ERROR index=%0d filtered=%0d expected=%0d",
                        aligned_index,
                        aligned_filtered,
                        expected_filter(aligned_index)
                    );

                    alignment_errors =
                        alignment_errors + 1;

                end

            end

        end

    end


    // ============================================================
    // MAIN TEST
    // ============================================================

    initial begin

        alignment_errors = 0;
        capture_errors   = 0;

        aligned_samples  = 0;
        timeout_count    = 0;

        acq_rst  = 1'b1;
        proc_rst = 1'b1;

        read_addr    = '0;
        readout_done = 1'b0;


        // ========================================================
        // RESET
        // ========================================================

        repeat (5)
            @(posedge proc_clk);

        @(negedge acq_clk);
        acq_rst = 1'b0;

        @(negedge proc_clk);
        proc_rst = 1'b0;


        // ========================================================
        // WAIT FOR COMPLETE EVENT
        //
        // Expected:
        //
        // trigger index = 1503
        // event start   = 479
        // event end     = 2526
        //
        // 479 + 1024 = 1503
        // 1503 + 1023 = 2526
        // ========================================================

        while (
            (event_done !== 1'b1) &&
            (timeout_count < 10000)
        ) begin

            @(posedge proc_clk);
            #1;

            timeout_count =
                timeout_count + 1;

        end


        if (event_done !== 1'b1) begin

            $error(
                "TIMEOUT: EVENT_DONE never asserted"
            );

            capture_errors =
                capture_errors + 1;

        end

        else begin

            $display("");
            $display(
                "EVENT_DONE observed after %0d proc cycles",
                timeout_count
            );

            $display(
                "trigger_ptr = %0d",
                trigger_ptr
            );

            $display(
                "start_ptr   = %0d",
                start_ptr
            );

        end


        // ========================================================
        // POINTER CHECK
        //
        // sample index n is written to address n mod 2048
        //
        // expected trigger_ptr = 1503
        //
        // expected start_ptr
        // = 1503 - 1024
        // = 479
        // ========================================================

        if (trigger_ptr !== 11'd1503) begin

            $error(
                "TRIGGER_PTR ERROR actual=%0d expected=1503",
                trigger_ptr
            );

            capture_errors =
                capture_errors + 1;

        end


        if (start_ptr !== 11'd479) begin

            $error(
                "START_PTR ERROR actual=%0d expected=479",
                start_ptr
            );

            capture_errors =
                capture_errors + 1;

        end


        // ========================================================
        // TRIGGER SAMPLE CHECK
        //
        // event offset 1024 must be logical sample 1503
        // ========================================================

        begin

            logic [71:0] trigger_entry;
            logic [31:0] trigger_index;

            read_event(
                1024,
                trigger_entry
            );

            trigger_index =
                trigger_entry[71:40];


            $display(
                "Captured trigger logical index = %0d",
                trigger_index
            );


            if (
                trigger_index !==
                32'd1503
            ) begin

                $error(
                    "TRIGGER SAMPLE MISALIGNED actual=%0d expected=1503",
                    trigger_index
                );

                capture_errors =
                    capture_errors + 1;

            end

        end


        // ========================================================
        // REPRESENTATIVE EVENT LOCATIONS
        // ========================================================

        check_event_entry(
            0,
            32'd479
        );

        check_event_entry(
            1024,
            32'd1503
        );

        check_event_entry(
            2047,
            32'd2526
        );


        // ========================================================
        // FULL 2048-SAMPLE EVENT CHECK
        //
        // only do exhaustive check if pointer alignment is correct,
        // otherwise avoid printing thousands of redundant errors.
        // ========================================================

        if (
            (trigger_ptr == 11'd1503) &&
            (start_ptr   == 11'd479)
        ) begin

            for (
                i = 0;
                i < 2048;
                i = i + 1
            ) begin

                check_event_entry(
                    i,
                    32'd479 + i
                );

            end

        end


        // ========================================================
        // EVENT_FROZEN must NOT stop upstream processing
        // ========================================================

        begin

            logic [31:0] index_before;
            logic [31:0] index_after;

            index_before =
                aligned_index;


            repeat (50)
                @(posedge proc_clk);

            #1;

            index_after =
                aligned_index;


            if (
                index_after <=
                index_before
            ) begin

                $error(
                    "UPSTREAM PIPELINE STOPPED DURING EVENT_FROZEN"
                );

                capture_errors =
                    capture_errors + 1;

            end


            if (
                event_done !== 1'b1
            ) begin

                $error(
                    "EVENT_DONE unexpectedly cleared"
                );

                capture_errors =
                    capture_errors + 1;

            end

        end


        // Event memory must still contain trigger
        check_event_entry(
            1024,
            32'd1503
        );


        // ========================================================
        // READOUT COMPLETE
        // ========================================================

        @(negedge proc_clk);

        readout_done =
            1'b1;

        @(posedge proc_clk);
        #1;

        @(negedge proc_clk);

        readout_done =
            1'b0;


        if (
            event_done !== 1'b0
        ) begin

            $error(
                "READOUT_DONE FAILED TO CLEAR EVENT_DONE"
            );

            capture_errors =
                capture_errors + 1;

        end


        if (
            trigger_enable !== 1'b0
        ) begin

            $error(
                "FRESH PRE HISTORY WAS NOT REQUIRED"
            );

            capture_errors =
                capture_errors + 1;

        end


        // ========================================================
        // RESULT
        // ========================================================

        $display("");
        $display(
            "ALIGNED_SAMPLES = %0d",
            aligned_samples
        );

        $display(
            "ALIGNMENT_ERRORS = %0d",
            alignment_errors
        );

        $display(
            "CAPTURE_ERRORS = %0d",
            capture_errors
        );


        if (
            (alignment_errors == 0) &&
            (capture_errors == 0)
        ) begin

            $display("");
            $display(
                "========================================"
            );

            $display(
                "DAQ_EVENT_INTEGRATION_TEST_PASS"
            );

            $display(
                "========================================"
            );

        end

        else begin

            $display("");
            $display(
                "========================================"
            );

            $display(
                "DAQ_EVENT_INTEGRATION_TEST_FAIL"
            );

            $display(
                "========================================"
            );

        end


        $finish;

    end

endmodule