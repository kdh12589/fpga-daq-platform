`timescale 1ns / 1ps

module tb_uart_tx;

    localparam int CLK_HZ = 100_000_000;
    localparam int BAUD   = 921_600;

    localparam int CLKS_PER_BIT =
        (CLK_HZ + (BAUD / 2)) / BAUD;

    localparam int CLK_PERIOD_NS = 10;

    localparam int BIT_TIME_NS =
        CLKS_PER_BIT * CLK_PERIOD_NS;


    logic clk;
    logic rst;

    logic [7:0] in_data;
    logic       in_valid;
    logic       in_ready;

    logic tx;
    logic busy;
    logic byte_done;

    integer error_count;


    uart_tx #(
        .CLK_HZ (CLK_HZ),
        .BAUD   (BAUD)
    ) dut (
        .clk       (clk),
        .rst       (rst),

        .in_data   (in_data),
        .in_valid  (in_valid),
        .in_ready  (in_ready),

        .tx        (tx),
        .busy      (busy),
        .byte_done (byte_done)
    );


    initial clk = 1'b0;

    always #5 clk = ~clk;


    // ============================================================
    // SERIAL RECEIVE
    //
    // 실제 tx pin에서 start edge를 잡고
    // 각 bit의 중앙에서 sampling한다.
    // ============================================================

    task automatic receive_uart_byte(
        output logic [7:0] rx_byte
    );

        integer b;

        begin

            rx_byte = 8'h00;


            // UART start = falling edge
            @(negedge tx);


            // start bit center
            #(BIT_TIME_NS / 2);


            if (tx !== 1'b0) begin

                $error(
                    "START BIT ERROR"
                );

                error_count =
                    error_count + 1;

            end


            // Data bits, LSB first
            for (b = 0; b < 8; b = b + 1) begin

                #(BIT_TIME_NS);

                rx_byte[b] =
                    tx;

            end


            // Stop bit center
            #(BIT_TIME_NS);


            if (tx !== 1'b1) begin

                $error(
                    "STOP BIT ERROR"
                );

                error_count =
                    error_count + 1;

            end

        end

    endtask


    // ============================================================
    // SEND + RECEIVE ONE BYTE
    // ============================================================

    task automatic test_byte(
        input logic [7:0] value
    );

        logic [7:0] rx_byte;

        begin

            fork


                // ------------------------------------------------
                // UART transmitter input
                // ------------------------------------------------

                begin

                    // wait for ready
                    while (!in_ready)
                        @(posedge clk);


                    @(negedge clk);

                    in_data  = value;
                    in_valid = 1'b1;


                    @(posedge clk);


                    @(negedge clk);

                    in_valid = 1'b0;

                end


                // ------------------------------------------------
                // Decode actual tx pin
                // ------------------------------------------------

                begin

                    receive_uart_byte(
                        rx_byte
                    );

                end


            join


            if (rx_byte !== value) begin

                $error(
                    "UART BYTE ERROR actual=%02h expected=%02h",
                    rx_byte,
                    value
                );

                error_count =
                    error_count + 1;

            end


            // byte_done까지 기다림
            while (!byte_done)
                @(posedge clk);


            // idle로 돌아왔는지 확인
            @(posedge clk);
            #1;


            if (tx !== 1'b1) begin

                $error(
                    "UART DID NOT RETURN TO IDLE HIGH"
                );

                error_count =
                    error_count + 1;

            end

        end

    endtask


    // ============================================================
    // MAIN
    // ============================================================

    initial begin

        rst =
            1'b1;

        in_data =
            8'h00;

        in_valid =
            1'b0;

        error_count =
            0;


        repeat (5)
            @(posedge clk);


        @(negedge clk);

        rst =
            1'b0;


        // Idle must be HIGH
        @(posedge clk);
        #1;

        if (tx !== 1'b1) begin

            $error(
                "TX IDLE LEVEL ERROR"
            );

            error_count =
                error_count + 1;

        end


        // ========================================================
        // TEST PATTERNS
        // ========================================================

        test_byte(8'hA5);

        test_byte(8'h00);

        test_byte(8'hFF);

        test_byte(8'h55);


        // ========================================================
        // RESULT
        // ========================================================

        $display("");

        $display(
            "CLKS_PER_BIT = %0d",
            CLKS_PER_BIT
        );

        $display(
            "BIT_TIME_NS  = %0d",
            BIT_TIME_NS
        );

        $display(
            "ERROR_COUNT  = %0d",
            error_count
        );


        if (error_count == 0) begin

            $display("");
            $display(
                "========================================"
            );

            $display(
                "UART_TX_TEST_PASS"
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
                "UART_TX_TEST_FAIL"
            );

            $display(
                "========================================"
            );

        end


        $finish;

    end


endmodule