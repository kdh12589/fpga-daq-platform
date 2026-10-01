`timescale 1ns / 1ps

module tb_packet_uart_top;


    // ============================================================
    // CONSTANTS
    // ============================================================

    localparam int CLK_HZ = 100_000_000;
    localparam int BAUD   = 921_600;

    localparam int CLKS_PER_BIT =
        (CLK_HZ + (BAUD / 2)) / BAUD;

    localparam int CLK_PERIOD_NS =
        10;

    localparam int BIT_TIME_NS =
        CLKS_PER_BIT *
        CLK_PERIOD_NS;


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


    localparam logic [10:0] TEST_START_PTR =
        11'd1900;


    // ============================================================
    // CLOCK / RESET
    // ============================================================

    logic clk;
    logic rst;


    initial clk =
        1'b0;

    always #5 clk =
        ~clk;


    // ============================================================
    // DUT
    // ============================================================

    logic packet_start;

    logic [10:0] start_ptr;

    logic [10:0] mem_addr;
    logic [71:0] mem_data;

    logic packetizer_busy;
    logic packetizer_done;

    logic uart_busy;

    logic tx_complete;

    logic tx;


    packet_uart_top #(
        .CLK_HZ (CLK_HZ),
        .BAUD   (BAUD)
    ) dut (

        .clk             (clk),
        .rst             (rst),

        .packet_start    (packet_start),
        .start_ptr       (start_ptr),

        .mem_addr        (mem_addr),
        .mem_data        (mem_data),

        .packetizer_busy (packetizer_busy),
        .packetizer_done (packetizer_done),

        .uart_busy       (uart_busy),

        .tx_complete     (tx_complete),

        .tx              (tx)

    );


    // ============================================================
    // FAKE EVENT MEMORY
    //
    // 이전 Packetizer TB와 완전히 같은 pattern
    // ============================================================

    logic [71:0] event_mem [0:2047];

    integer i;


    initial begin

        for (
            i = 0;
            i < 2048;
            i = i + 1
        ) begin

            event_mem[i][71:40] =
                32'h1000_0000 + i;

            event_mem[i][39:32] =
                (i & 8'hFF) ^ 8'hA5;

            event_mem[i][31:16] =
                16'h2000 + i;

            event_mem[i][15:0] =
                16'h6000 + i;

        end

    end


    // Event Capture와 같은 synchronous read
    always_ff @(posedge clk) begin

        if (rst) begin

            mem_data <=
                '0;

        end
        else begin

            mem_data <=
                event_mem[mem_addr];

        end

    end


    // ============================================================
    // EXPECTED HEADER
    // ============================================================

    function automatic logic [7:0]
        expected_header_byte(
            input integer index
        );

        begin

            case (index)

                0:  expected_header_byte = 8'h44;
                1:  expected_header_byte = 8'h41;
                2:  expected_header_byte = 8'h51;
                3:  expected_header_byte = 8'h31;

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
    // EXPECTED PAYLOAD
    // ============================================================

    function automatic logic [7:0]
        expected_payload_byte(
            input integer sample_no,
            input integer byte_no
        );

        integer addr;

        logic [31:0] idx;
        logic [7:0]  flags;
        logic [15:0] raw_v;
        logic [15:0] filtered_v;

        begin

            addr =
                (1900 + sample_no)
                % 2048;


            idx =
                32'h1000_0000 +
                addr;

            flags =
                (addr & 8'hFF)
                ^ 8'hA5;

            raw_v =
                16'h2000 +
                addr;

            filtered_v =
                16'h6000 +
                addr;


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

                4:
                    expected_payload_byte =
                        flags;

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
    // CRC REFERENCE
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
    // ACTUAL UART RECEIVER
    //
    // DUT의 tx pin만 본다.
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


            // Start edge
            @(negedge tx);


            // Start bit center
            #(BIT_TIME_NS / 2);


            if (tx !== 1'b0) begin

                frame_error =
                    1'b1;

            end


            // Data bits
            for (
                b = 0;
                b < 8;
                b = b + 1
            ) begin

                #(BIT_TIME_NS);

                rx_byte[b] =
                    tx;

            end


            // Stop bit center
            #(BIT_TIME_NS);


            if (tx !== 1'b1) begin

                frame_error =
                    1'b1;

            end

        end

    endtask


    // ============================================================
    // TEST STATE
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
    logic       frame_error;

    logic [7:0] expected_byte;

    integer packetizer_done_seen;


    // ============================================================
    // WATCH PACKETIZER DONE
    // ============================================================

    always @(posedge clk) begin

        if (rst) begin

            packetizer_done_seen <=
                0;

        end
        else begin

            if (packetizer_done) begin

                packetizer_done_seen <=
                    1;

            end

        end

    end


    // ============================================================
    // MAIN
    // ============================================================

    initial begin

        rst =
            1'b1;

        packet_start =
            1'b0;

        start_ptr =
            TEST_START_PTR;


        error_count =
            0;

        rx_count =
            0;

        golden_crc =
            16'hFFFF;

        packetizer_done_seen =
            0;


        // ========================================================
        // Build independent expected CRC
        // ========================================================

        for (
            i = 0;
            i < HEADER_BYTES;
            i = i + 1
        ) begin

            golden_crc =
                crc16_ref(
                    golden_crc,
                    expected_header_byte(i)
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


        if (golden_crc !== 16'h0ACE) begin

            $error(
                "REFERENCE CRC ERROR actual=%04h expected=0ACE",
                golden_crc
            );

            error_count =
                error_count + 1;

        end


        // ========================================================
        // RESET
        // ========================================================

        repeat (5)
            @(posedge clk);


        @(negedge clk);

        rst =
            1'b0;


        // UART line idle HIGH
        @(posedge clk);
        #1;


        if (tx !== 1'b1) begin

            $error(
                "TX NOT IDLE HIGH"
            );

            error_count =
                error_count + 1;

        end


        // ========================================================
        // START PACKET
        // ========================================================

        repeat (2)
            @(posedge clk);


        @(negedge clk);

        packet_start =
            1'b1;


        @(posedge clk);


        @(negedge clk);

        packet_start =
            1'b0;


        // ========================================================
        // RECEIVE ALL 18,450 BYTES FROM ACTUAL TX PIN
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


            // ====================================================
            // Header
            // ====================================================

            if (
                rx_count <
                HEADER_BYTES
            ) begin

                expected_byte =
                    expected_header_byte(
                        rx_count
                    );

            end


            // ====================================================
            // Payload
            // ====================================================

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


            // ====================================================
            // CRC HIGH
            // ====================================================

            else if (
                rx_count ==
                DATA_BYTES
            ) begin

                expected_byte =
                    golden_crc[15:8];

            end


            // ====================================================
            // CRC LOW
            // ====================================================

            else begin

                expected_byte =
                    golden_crc[7:0];

            end


            // ====================================================
            // Compare recovered physical UART byte
            // ====================================================

            if (
                rx_byte !==
                expected_byte
            ) begin

                if (error_count < 20) begin

                    $error(
                        "UART PACKET ERROR byte=%0d actual=%02h expected=%02h",
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
        // Last byte stop bit must finish
        // ========================================================

        wait (
            tx_complete ==
            1'b1
        );


        @(posedge clk);
        #1;


        // ========================================================
        // Packetizer must have completed earlier
        // ========================================================

        if (
            packetizer_done_seen == 0
        ) begin

            $error(
                "PACKETIZER_DONE WAS NEVER SEEN"
            );

            error_count =
                error_count + 1;

        end


        // ========================================================
        // UART must return to idle
        // ========================================================

        if (tx !== 1'b1) begin

            $error(
                "UART TX DID NOT RETURN TO IDLE"
            );

            error_count =
                error_count + 1;

        end


        if (uart_busy !== 1'b0) begin

            $error(
                "UART STILL BUSY AFTER TX_COMPLETE"
            );

            error_count =
                error_count + 1;

        end


        // ========================================================
        // Make sure no unexpected additional frame starts
        // ========================================================

        begin

            integer extra_start_seen;

            extra_start_seen =
                0;


            fork

                begin

                    @(negedge tx);

                    extra_start_seen =
                        1;

                end


                begin

                    #(BIT_TIME_NS * 20);

                end

            join_any

            disable fork;


            if (extra_start_seen != 0) begin

                $error(
                    "EXTRA UART FRAME DETECTED"
                );

                error_count =
                    error_count + 1;

            end

        end


        // ========================================================
        // RESULT
        // ========================================================

        $display("");

        $display(
            "UART_RX_BYTES       = %0d",
            rx_count
        );

        $display(
            "EXPECTED_BYTES      = %0d",
            TOTAL_BYTES
        );

        $display(
            "REFERENCE_CRC       = %04h",
            golden_crc
        );

        $display(
            "PACKETIZER_DONE_SEEN= %0d",
            packetizer_done_seen
        );

        $display(
            "ERROR_COUNT         = %0d",
            error_count
        );


        if (error_count == 0) begin

            $display("");
            $display(
                "=============================================="
            );

            $display(
                "PACKET_UART_PHYSICAL_LINK_TEST_PASS"
            );

            $display(
                "=============================================="
            );

        end
        else begin

            $display("");
            $display(
                "=============================================="
            );

            $display(
                "PACKET_UART_PHYSICAL_LINK_TEST_FAIL"
            );

            $display(
                "=============================================="
            );

        end


        $finish;

    end


endmodule