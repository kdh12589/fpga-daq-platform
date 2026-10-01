`timescale 1ns / 1ps

module tb_crc16_ccitt;

    logic clk;
    logic rst;

    logic clear;
    logic data_valid;
    logic [7:0] data_byte;

    logic [15:0] crc_out;

    integer error_count;


    crc16_ccitt dut (
        .clk        (clk),
        .rst        (rst),

        .clear      (clear),

        .data_valid (data_valid),
        .data_byte  (data_byte),

        .crc_out    (crc_out)
    );


    // 100 MHz
    initial clk = 1'b0;
    always #5 clk = ~clk;


    // ------------------------------------------------------------
    // byte 하나를 CRC에 넣음
    // ------------------------------------------------------------
    task automatic send_byte(
        input logic [7:0] value
    );
    begin

        @(negedge clk);

        data_byte  = value;
        data_valid = 1'b1;

        @(posedge clk);
        #1;

        @(negedge clk);

        data_valid = 1'b0;

    end
    endtask


    initial begin

        error_count = 0;

        rst        = 1'b1;
        clear      = 1'b0;
        data_valid = 1'b0;
        data_byte  = 8'h00;


        // ========================================================
        // RESET
        // ========================================================

        repeat (3)
            @(posedge clk);

        @(negedge clk);
        rst = 1'b0;

        @(posedge clk);
        #1;


        // reset CRC는 CCITT-FALSE init = FFFF
        if (crc_out !== 16'hFFFF) begin

            $error(
                "RESET CRC ERROR actual=%h expected=FFFF",
                crc_out
            );

            error_count = error_count + 1;

        end


        // ========================================================
        // STANDARD CHECK VECTOR
        //
        // ASCII "123456789"
        //
        // expected CRC = 0x29B1
        // ========================================================

        send_byte(8'h31); // 1
        send_byte(8'h32); // 2
        send_byte(8'h33); // 3
        send_byte(8'h34); // 4
        send_byte(8'h35); // 5
        send_byte(8'h36); // 6
        send_byte(8'h37); // 7
        send_byte(8'h38); // 8
        send_byte(8'h39); // 9


        if (crc_out !== 16'h29B1) begin

            $error(
                "CRC ERROR actual=%h expected=29B1",
                crc_out
            );

            error_count = error_count + 1;

        end


        // ========================================================
        // CLEAR TEST
        // ========================================================

        @(negedge clk);
        clear = 1'b1;

        @(posedge clk);
        #1;

        @(negedge clk);
        clear = 1'b0;


        if (crc_out !== 16'hFFFF) begin

            $error(
                "CRC CLEAR ERROR actual=%h expected=FFFF",
                crc_out
            );

            error_count = error_count + 1;

        end


        // ========================================================
        // data_valid = 0이면 CRC 변화 없어야 함
        // ========================================================

        begin

            logic [15:0] saved_crc;

            saved_crc = crc_out;

            @(negedge clk);

            data_byte  = 8'hAA;
            data_valid = 1'b0;

            repeat (5)
                @(posedge clk);

            #1;

            if (crc_out !== saved_crc) begin

                $error(
                    "CRC CHANGED WITHOUT data_valid"
                );

                error_count = error_count + 1;

            end

        end


        // ========================================================
        // RESULT
        // ========================================================

        if (error_count == 0) begin

            $display("");
            $display(
                "========================================"
            );

            $display(
                "CRC16_CCITT_TEST_PASS"
            );

            $display(
                "CRC = %h",
                crc_out
            );

            $display(
                "ERROR_COUNT = %0d",
                error_count
            );

            $display(
                "========================================"
            );
            $display("");

        end
        else begin

            $display("");
            $display(
                "========================================"
            );

            $display(
                "CRC16_CCITT_TEST_FAIL"
            );

            $display(
                "ERROR_COUNT = %0d",
                error_count
            );

            $display(
                "========================================"
            );
            $display("");

        end


        $finish;

    end

endmodule