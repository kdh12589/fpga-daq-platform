`timescale 1ns / 1ps

module tb_daq_full_top;


    // ============================================================
    // SYSTEM TARGET
    // ============================================================

    localparam int PROC_CLK_HZ =
        125_000_000;

    localparam int UART_BAUD =
        921_600;


    // 125 MHz = 8 ns period
    localparam realtime PROC_HALF_NS =
        4.000;

    // 약 65 MHz
    // period ≈ 15.384 ns
    localparam realtime ACQ_HALF_NS =
        7.692;


    localparam int CLKS_PER_BIT =
        (PROC_CLK_HZ + (UART_BAUD / 2))
        / UART_BAUD;

    // 136 clocks @ 125 MHz
    localparam realtime BIT_TIME_NS =
        CLKS_PER_BIT * 8.0;


    // ============================================================
    // PACKET
    // ============================================================

    localparam int HEADER_BYTES =
        16;

    localparam int SAMPLE_COUNT =
        2048;

    localparam int BYTES_SAMPLE =
        9;

    localparam int PAYLOAD_BYTES =
        SAMPLE_COUNT *
        BYTES_SAMPLE;

    localparam int DATA_BYTES =
        HEADER_BYTES +
        PAYLOAD_BYTES;

    localparam int TOTAL_BYTES =
        DATA_BYTES + 2;


    // Expected event
    localparam int FIRST_SAMPLE =
        479;

    localparam int TRIGGER_SAMPLE =
        1503;

    localparam int LAST_SAMPLE =
        2526;


    // ============================================================
    // CLOCKS
    // ============================================================

    logic acq_clk;
    logic proc_clk;

    logic acq_rst;
    logic proc_rst;


    initial acq_clk =
        1'b0;

    always #(ACQ_HALF_NS)
        acq_clk = ~acq_clk;


    initial proc_clk =
        1'b0;

    always #(PROC_HALF_NS)
        proc_clk = ~proc_clk;


    // ============================================================
    // DUT SIGNALS
    // ============================================================

    logic tx;

    logic event_done;
    logic trigger_enable;

    logic packetizer_busy;
    logic packetizer_done;

    logic uart_busy;
    logic tx_complete;

    logic [10:0] trigger_ptr;
    logic [10:0] start_ptr;

    logic signed [15:0] aligned_raw;
    logic signed [15:0] aligned_filtered;

    logic [31:0] aligned_index;

    logic aligned_valid;
    logic trigger_pulse;

    logic packet_start_dbg;


    daq_full_top #(
        .DATA_WIDTH      (16),
        .FIFO_ADDR_WIDTH (6),

        .PROC_CLK_HZ     (PROC_CLK_HZ),
        .UART_BAUD       (UART_BAUD),

        .TRIG_LOW        (16'sd1400),
        .TRIG_HIGH       (16'sd1500)
    ) dut (

        .acq_clk          (acq_clk),
        .acq_rst          (acq_rst),

        .proc_clk         (proc_clk),
        .proc_rst         (proc_rst),

        .tx               (tx),

        .event_done       (event_done),
        .trigger_enable   (trigger_enable),

        .packetizer_busy  (packetizer_busy),
        .packetizer_done  (packetizer_done),

        .uart_busy        (uart_busy),
        .tx_complete      (tx_complete),

        .trigger_ptr      (trigger_ptr),
        .start_ptr        (start_ptr),

        .aligned_raw      (aligned_raw),
        .aligned_filtered (aligned_filtered),

        .aligned_index    (aligned_index),
        .aligned_valid    (aligned_valid),

        .trigger_pulse    (trigger_pulse),

        .packet_start_dbg (packet_start_dbg)
    );


    // ============================================================
    // HEADER REFERENCE
    // ============================================================

    function automatic logic [7:0]
        expected_header_byte(
            input integer index
        );

        begin

            case (index)

                0:  expected_header_byte = 8'h44; // D
                1:  expected_header_byte = 8'h41; // A
                2:  expected_header_byte = 8'h51; // Q
                3:  expected_header_byte = 8'h31; // 1

                4:  expected_header_byte = 8'h01;
                5:  expected_header_byte = 8'h00;

                6:  expected_header_byte = 8'h00;
                7:  expected_header_byte = 8'h00;
                8:  expected_header_byte = 8'h48;
                9:  expected_header_byte = 8'h00;

                10: expected_header_byte = 8'h08;
                11: expected_header_byte = 8'h00;

                12: expected_header_byte = 8'h04;
                13: expected_header_byte = 8'h00;

                14: expected_header_byte = 8'h09;
                15: expected_header_byte = 8'h00;

                default:
                    expected_header_byte =
                        8'h00;

            endcase

        end

    endfunction


    // ============================================================
    // FULL-SYSTEM EXPECTED PAYLOAD
    //
    // Event samples:
    //
    // index = 479 ... 2526
    //
    // raw      = index
    // filtered = index - 3
    // flags    = 0
    // ============================================================

    function automatic logic [7:0]
        expected_payload_byte(
            input integer sample_no,
            input integer byte_no
        );

        logic [31:0] idx;

        logic [15:0] raw_v;
        logic [15:0] filtered_v;

        begin

            idx =
                FIRST_SAMPLE +
                sample_no;

            raw_v =
                idx[15:0];

            filtered_v =
                idx[15:0] -
                16'd3;


            case (byte_no)

                0:
                    expected_payload_byte =
                        idx[31:24];

                1:
                    expected_payload_byte =
                        idx[23:16];

                2:
                    expected_payload_byte =
                        idx[15:8];

                3:
                    expected_payload_byte =
                        idx[7:0];

                // fault flags
                4:
                    expected_payload_byte =
                        8'h00;

                5:
                    expected_payload_byte =
                        raw_v[15:8];

                6:
                    expected_payload_byte =
                        raw_v[7:0];

                7:
                    expected_payload_byte =
                        filtered_v[15:8];

                8:
                    expected_payload_byte =
                        filtered_v[7:0];

                default:
                    expected_payload_byte =
                        8'h00;

            endcase

        end

    endfunction


    // ============================================================
    // INDEPENDENT CRC MODEL
    // ============================================================

    function automatic logic [15:0]
        crc16_ref(
            input logic [15:0] crc_in,
            input logic [7:0]  byte_in
        );

        logic [15:0] crc;

        integer j;

        begin

            crc =
                crc_in;


            for (
                j = 0;
                j < 8;
                j = j + 1
            ) begin

                if (
                    crc[15] ^
                    byte_in[7-j]
                ) begin

                    crc =
                        {crc[14:0], 1'b0}
                        ^ 16'h1021;

                end
                else begin

                    crc =
                        {crc[14:0], 1'b0};

                end

            end


            crc16_ref =
                crc;

        end

    endfunction


    // ============================================================
    // UART RECEIVER
    //
    // Actual physical tx only.
    // ============================================================

    task automatic receive_uart_byte(
        output logic [7:0] rx_byte,
        output logic       frame_error
    );

        integer b;

        begin

            rx_byte =
                8'h00;

            frame_error =
                1'b0;


            // Start falling edge
            @(negedge tx);


            // Start bit center
            #(BIT_TIME_NS / 2.0);


            if (tx !== 1'b0) begin

                frame_error =
                    1'b1;

            end


            // Data bits, LSB first
            for (
                b = 0;
                b < 8;
                b = b + 1
            ) begin

                #(BIT_TIME_NS);

                rx_byte[b] =
                    tx;

            end


            // Stop center
            #(BIT_TIME_NS);


            if (tx !== 1'b1) begin

                frame_error =
                    1'b1;

            end

        end

    endtask


    // ============================================================
    // OBSERVATION
    // ============================================================

    integer event_seen;
    integer packet_start_count;

    logic [10:0] captured_trigger_ptr;
    logic [10:0] captured_start_ptr;


    always @(posedge proc_clk) begin

        if (proc_rst) begin

            event_seen <=
                0;

            packet_start_count <=
                0;

            captured_trigger_ptr <=
                '0;

            captured_start_ptr <=
                '0;

        end
        else begin

            if (
                event_done &&
                !event_seen
            ) begin

                event_seen <=
                    1;

                captured_trigger_ptr <=
                    trigger_ptr;

                captured_start_ptr <=
                    start_ptr;

            end


            if (packet_start_dbg) begin

                packet_start_count <=
                    packet_start_count + 1;

            end

        end

    end


    // ============================================================
    // MAIN
    // ============================================================

    integer error_count;

    integer rx_count;

    integer payload_position;
    integer sample_no;
    integer byte_no;

    integer s;
    integer b;

    logic [15:0] golden_crc;

    logic [7:0] rx_byte;
    logic [7:0] expected_byte;

    logic frame_error;


    initial begin

        acq_rst =
            1'b1;

        proc_rst =
            1'b1;

        error_count =
            0;

        golden_crc =
            16'hFFFF;


        // ========================================================
        // Build golden CRC
        // ========================================================

        for (
            s = 0;
            s < HEADER_BYTES;
            s = s + 1
        ) begin

            golden_crc =
                crc16_ref(
                    golden_crc,
                    expected_header_byte(s)
                );

        end


        for (
            s = 0;
            s < SAMPLE_COUNT;
            s = s + 1
        ) begin

            for (
                b = 0;
                b < BYTES_SAMPLE;
                b = b + 1
            ) begin

                golden_crc =
                    crc16_ref(
                        golden_crc,
                        expected_payload_byte(
                            s,
                            b
                        )
                    );

            end

        end


        // Independent known value for THIS full event
        if (golden_crc !== 16'h1857) begin

            $error(
                "FULL SYSTEM REFERENCE CRC ERROR actual=%04h expected=1857",
                golden_crc
            );

            error_count =
                error_count + 1;

        end


        // ========================================================
        // RESET
        // ========================================================

        repeat (8)
            @(posedge proc_clk);


        @(negedge acq_clk);
        acq_rst =
            1'b0;


        @(negedge proc_clk);
        proc_rst =
            1'b0;


        // ========================================================
        // WAIT FOR EVENT FREEZE
        // ========================================================

        wait (
            event_done ==
            1'b1
        );


        @(posedge proc_clk);
        #1;


        // ========================================================
        // Trigger / event pointer checks
        // ========================================================

        if (
            trigger_ptr !==
            11'd1503
        ) begin

            $error(
                "TRIGGER PTR ERROR actual=%0d expected=1503",
                trigger_ptr
            );

            error_count =
                error_count + 1;

        end


        if (
            start_ptr !==
            11'd479
        ) begin

            $error(
                "START PTR ERROR actual=%0d expected=479",
                start_ptr
            );

            error_count =
                error_count + 1;

        end


        // ========================================================
        // RECEIVE ENTIRE PACKET FROM PHYSICAL TX
        // ========================================================

        for (
            rx_count = 0;
            rx_count < TOTAL_BYTES;
            rx_count = rx_count + 1
        ) begin

            receive_uart_byte(
                rx_byte,
                frame_error
            );


            if (frame_error) begin

                if (error_count < 20) begin

                    $error(
                        "UART FRAME ERROR byte=%0d",
                        rx_count
                    );

                end

                error_count =
                    error_count + 1;

            end


            // Header
            if (
                rx_count <
                HEADER_BYTES
            ) begin

                expected_byte =
                    expected_header_byte(
                        rx_count
                    );

            end

            // Payload
            else if (
                rx_count <
                DATA_BYTES
            ) begin

                payload_position =
                    rx_count -
                    HEADER_BYTES;

                sample_no =
                    payload_position /
                    BYTES_SAMPLE;

                byte_no =
                    payload_position %
                    BYTES_SAMPLE;


                expected_byte =
                    expected_payload_byte(
                        sample_no,
                        byte_no
                    );

            end

            // CRC high
            else if (
                rx_count ==
                DATA_BYTES
            ) begin

                expected_byte =
                    golden_crc[15:8];

            end

            // CRC low
            else begin

                expected_byte =
                    golden_crc[7:0];

            end


            if (
                rx_byte !==
                expected_byte
            ) begin

                if (error_count < 20) begin

                    $error(
                        "FULL UART DATA ERROR byte=%0d actual=%02h expected=%02h",
                        rx_count,
                        rx_byte,
                        expected_byte
                    );

                end

                error_count =
                    error_count + 1;

            end

        end


        // ========================================================
        // ACTUAL PHYSICAL TX MUST COMPLETE
        // ========================================================

        wait (
            tx_complete ==
            1'b1
        );


        @(posedge proc_clk);
        #1;


        // ========================================================
        // Automatic readout_done must release Event Capture
        // ========================================================

        if (
            event_done !==
            1'b0
        ) begin

            $error(
                "EVENT_DONE DID NOT CLEAR AFTER TX_COMPLETE"
            );

            error_count =
                error_count + 1;

        end


        // Fresh PRE history required
        if (
            trigger_enable !==
            1'b0
        ) begin

            $error(
                "TRIGGER_ENABLE SHOULD BE 0 AFTER REARM"
            );

            error_count =
                error_count + 1;

        end


        // Packet must start exactly once
        if (
            packet_start_count !=
            1
        ) begin

            $error(
                "PACKET START COUNT ERROR actual=%0d expected=1",
                packet_start_count
            );

            error_count =
                error_count + 1;

        end


        if (
            captured_trigger_ptr !==
            11'd1503
        ) begin

            $error(
                "CAPTURED TRIGGER PTR ERROR actual=%0d",
                captured_trigger_ptr
            );

            error_count =
                error_count + 1;

        end


        if (
            captured_start_ptr !==
            11'd479
        ) begin

            $error(
                "CAPTURED START PTR ERROR actual=%0d",
                captured_start_ptr
            );

            error_count =
                error_count + 1;

        end


        // ========================================================
        // RESULTS
        // ========================================================

        $display("");
        $display(
            "ACQ_RATE_TARGET       = 65 MSPS"
        );

        $display(
            "PROC_CLOCK            = 125 MHz"
        );

        $display(
            "FIFO_DEPTH            = 64"
        );

        $display(
            "TRIGGER_SAMPLE        = %0d",
            captured_trigger_ptr
        );

        $display(
            "EVENT_START           = %0d",
            captured_start_ptr
        );

        $display(
            "UART_RX_BYTES         = %0d",
            rx_count
        );

        $display(
            "EXPECTED_BYTES        = %0d",
            TOTAL_BYTES
        );

        $display(
            "REFERENCE_CRC         = %04h",
            golden_crc
        );

        $display(
            "PACKET_START_COUNT    = %0d",
            packet_start_count
        );

        $display(
            "ERROR_COUNT           = %0d",
            error_count
        );


        if (
            error_count == 0
        ) begin

            $display("");
            $display(
                "=================================================="
            );

            $display(
                "DAQ_FULL_SYSTEM_TEST_PASS"
            );

            $display(
                "=================================================="
            );

        end
        else begin

            $display("");
            $display(
                "=================================================="
            );

            $display(
                "DAQ_FULL_SYSTEM_TEST_FAIL"
            );

            $display(
                "=================================================="
            );

        end


        $finish;

    end


endmodule