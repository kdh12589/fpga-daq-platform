`timescale 1ns / 1ps

module tb_event_packetizer;


    // ============================================================
    // CONSTANTS
    // ============================================================

    localparam int HEADER_BYTES  = 16;
    localparam int SAMPLE_COUNT  = 2048;
    localparam int BYTES_SAMPLE  = 9;

    localparam int PAYLOAD_BYTES =
        SAMPLE_COUNT * BYTES_SAMPLE;

    localparam int DATA_BYTES =
        HEADER_BYTES + PAYLOAD_BYTES;

    localparam int TOTAL_BYTES =
        DATA_BYTES + 2;


    localparam logic [10:0] TEST_START_PTR =
        11'd1900;


    // ============================================================
    // CLOCK / RESET
    // ============================================================

    logic clk;
    logic rst;


    initial clk = 1'b0;

    always #5 clk = ~clk;


    // ============================================================
    // DUT SIGNALS
    // ============================================================

    logic        start;
    logic [10:0] start_ptr;

    logic        busy;
    logic        done;

    logic [10:0] mem_addr;
    logic [71:0] mem_data;

    logic [7:0]  out_byte;
    logic        out_valid;
    logic        out_ready;


    // ============================================================
    // DUT
    // ============================================================

    event_packetizer dut (

        .clk       (clk),
        .rst       (rst),

        .start     (start),
        .start_ptr (start_ptr),

        .busy      (busy),
        .done      (done),

        .mem_addr  (mem_addr),
        .mem_data  (mem_data),

        .out_byte  (out_byte),
        .out_valid (out_valid),
        .out_ready (out_ready)

    );


    // ============================================================
    // FAKE EVENT MEMORY
    //
    // 실제 event_capture와 동일한 synchronous read 형태.
    // ============================================================

    logic [71:0] event_mem [0:2047];


    integer i;


    initial begin

        for (i = 0; i < 2048; i = i + 1) begin

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
    // REFERENCE HEADER
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
                    expected_header_byte = 8'h00;

            endcase

        end

    endfunction


    // ============================================================
    // REFERENCE PAYLOAD
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

            // circular buffer wrap
            addr =
                (1900 + sample_no)
                % 2048;


            idx =
                32'h1000_0000 + addr;

            flags =
                (addr & 8'hFF)
                ^ 8'hA5;

            raw_v =
                16'h2000 + addr;

            filtered_v =
                16'h6000 + addr;


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
    // INDEPENDENT CRC REFERENCE
    // ============================================================

    function automatic logic [15:0]
        crc16_ref(
            input logic [15:0] crc_in,
            input logic [7:0]  byte_in
        );

        logic [15:0] crc;
        integer j;

        begin

            crc = crc_in;


            for (j = 0; j < 8; j = j + 1) begin

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


            crc16_ref = crc;

        end

    endfunction


    // ============================================================
    // RANDOM BACKPRESSURE
    //
    // deterministic LFSR
    // ============================================================

    logic [15:0] lfsr;

    integer stall_seen;


    always @(negedge clk) begin

        if (rst) begin

            lfsr <=
                16'hACE1;

            out_ready <=
                1'b0;

        end
        else begin

            lfsr <= {
                lfsr[14:0],
                lfsr[15] ^
                lfsr[13] ^
                lfsr[12] ^
                lfsr[10]
            };


            // 약 75% 정도 ready
            out_ready <=
                lfsr[0] |
                lfsr[3];

        end

    end


    // ============================================================
    // SCOREBOARD
    // ============================================================

    integer byte_count;
    integer error_count;

    integer payload_position;
    integer sample_no;
    integer byte_no;

    logic [15:0] golden_crc;


    always @(posedge clk) begin

        if (!rst) begin


            if (
                out_valid &&
                !out_ready
            ) begin

                stall_seen =
                    1;

            end


            // ----------------------------------------------------
            // REAL TRANSFER
            // ----------------------------------------------------

            if (
                out_valid &&
                out_ready
            ) begin


                // =================================================
                // HEADER
                // =================================================

                if (
                    byte_count <
                    HEADER_BYTES
                ) begin

                    if (
                        out_byte !==
                        expected_header_byte(
                            byte_count
                        )
                    ) begin

                        if (error_count < 20) begin

                            $error(
                                "HEADER ERROR byte=%0d actual=%02h expected=%02h",
                                byte_count,
                                out_byte,
                                expected_header_byte(byte_count)
                            );

                        end

                        error_count =
                            error_count + 1;

                    end


                    golden_crc =
                        crc16_ref(
                            golden_crc,
                            out_byte
                        );

                end


                // =================================================
                // PAYLOAD
                // =================================================

                else if (
                    byte_count <
                    DATA_BYTES
                ) begin

                    payload_position =
                        byte_count -
                        HEADER_BYTES;

                    sample_no =
                        payload_position /
                        BYTES_SAMPLE;

                    byte_no =
                        payload_position %
                        BYTES_SAMPLE;


                    if (
                        out_byte !==
                        expected_payload_byte(
                            sample_no,
                            byte_no
                        )
                    ) begin

                        if (error_count < 20) begin

                            $error(
                                "PAYLOAD ERROR global_byte=%0d sample=%0d byte_in_sample=%0d actual=%02h expected=%02h",
                                byte_count,
                                sample_no,
                                byte_no,
                                out_byte,
                                expected_payload_byte(
                                    sample_no,
                                    byte_no
                                )
                            );

                        end


                        error_count =
                            error_count + 1;

                    end


                    golden_crc =
                        crc16_ref(
                            golden_crc,
                            out_byte
                        );

                end


                // =================================================
                // CRC HIGH
                // =================================================

                else if (
                    byte_count ==
                    DATA_BYTES
                ) begin

                    if (
                        out_byte !==
                        golden_crc[15:8]
                    ) begin

                        $error(
                            "CRC HIGH ERROR actual=%02h expected=%02h",
                            out_byte,
                            golden_crc[15:8]
                        );

                        error_count =
                            error_count + 1;

                    end

                end


                // =================================================
                // CRC LOW
                // =================================================

                else if (
                    byte_count ==
                    DATA_BYTES + 1
                ) begin

                    if (
                        out_byte !==
                        golden_crc[7:0]
                    ) begin

                        $error(
                            "CRC LOW ERROR actual=%02h expected=%02h",
                            out_byte,
                            golden_crc[7:0]
                        );

                        error_count =
                            error_count + 1;

                    end

                end


                // =================================================
                // TOO MANY BYTES
                // =================================================

                else begin

                    $error(
                        "EXTRA OUTPUT BYTE byte_count=%0d value=%02h",
                        byte_count,
                        out_byte
                    );

                    error_count =
                        error_count + 1;

                end


                byte_count =
                    byte_count + 1;

            end

        end

    end


    // ============================================================
    // MAIN TEST
    // ============================================================

    integer timeout_count;


    initial begin

        rst =
            1'b1;

        start =
            1'b0;

        start_ptr =
            TEST_START_PTR;

        out_ready =
            1'b0;

        lfsr =
            16'hACE1;


        byte_count =
            0;

        error_count =
            0;

        stall_seen =
            0;

        golden_crc =
            16'hFFFF;

        timeout_count =
            0;


        // ========================================================
        // RESET
        // ========================================================

        repeat (5)
            @(posedge clk);

        @(negedge clk);

        rst =
            1'b0;


        // ========================================================
        // START PACKET
        // ========================================================

        repeat (2)
            @(posedge clk);

        @(negedge clk);

        start =
            1'b1;


        @(posedge clk);

        @(negedge clk);

        start =
            1'b0;


        // ========================================================
        // WAIT FOR DONE
        // ========================================================

        while (
            (done !== 1'b1) &&
            (timeout_count < 100000)
        ) begin

            @(posedge clk);

            timeout_count =
                timeout_count + 1;

        end


        // ========================================================
        // TIMEOUT CHECK
        // ========================================================

        if (
            done !==
            1'b1
        ) begin

            $error(
                "PACKETIZER TIMEOUT"
            );

            error_count =
                error_count + 1;

        end


        // ========================================================
        // BYTE COUNT
        // ========================================================

        if (
            byte_count !=
            TOTAL_BYTES
        ) begin

            $error(
                "BYTE COUNT ERROR actual=%0d expected=%0d",
                byte_count,
                TOTAL_BYTES
            );

            error_count =
                error_count + 1;

        end


        // ========================================================
        // KNOWN CRC
        //
        // 이 TB의 memory pattern + header에서
        //
        // expected = 0x0ACE
        // ========================================================

        if (
            golden_crc !==
            16'h0ACE
        ) begin

            $error(
                "REFERENCE CRC ERROR actual=%04h expected=0ACE",
                golden_crc
            );

            error_count =
                error_count + 1;

        end


        // ========================================================
        // BACKPRESSURE ACTUALLY OCCURRED
        // ========================================================

        if (
            stall_seen == 0
        ) begin

            $error(
                "BACKPRESSURE WAS NEVER EXERCISED"
            );

            error_count =
                error_count + 1;

        end


        // ========================================================
        // RESULT
        // ========================================================

        $display("");
        $display(
            "PACKET_BYTES       = %0d",
            byte_count
        );

        $display(
            "EXPECTED_BYTES     = %0d",
            TOTAL_BYTES
        );

        $display(
            "REFERENCE_CRC      = %04h",
            golden_crc
        );

        $display(
            "BACKPRESSURE_SEEN  = %0d",
            stall_seen
        );

        $display(
            "ERROR_COUNT        = %0d",
            error_count
        );


        if (
            error_count == 0
        ) begin

            $display("");
            $display(
                "========================================"
            );

            $display(
                "EVENT_PACKETIZER_TEST_PASS"
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
                "EVENT_PACKETIZER_TEST_FAIL"
            );

            $display(
                "========================================"
            );

        end


        $finish;

    end


endmodule