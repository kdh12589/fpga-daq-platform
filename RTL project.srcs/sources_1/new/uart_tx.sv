`timescale 1ns / 1ps

module uart_tx #(
    parameter int CLK_HZ = 100_000_000,
    parameter int BAUD   = 921_600
)(
    input  logic       clk,
    input  logic       rst,

    input  logic [7:0] in_data,
    input  logic       in_valid,
    output logic       in_ready,

    output logic       tx,
    output logic       busy,

    // byte 하나의 stop bit까지 끝났을 때 1-cycle pulse
    output logic       byte_done
);

    // ============================================================
    // 100 MHz / 921600 baud
    //
    // round(100e6 / 921600) = 109 clocks/bit
    //
    // 실제 baud:
    // 100e6 / 109 ≈ 917431 baud
    // ============================================================

    localparam int CLKS_PER_BIT =
        (CLK_HZ + (BAUD / 2)) / BAUD;

    localparam int BAUD_CNT_WIDTH =
        (CLKS_PER_BIT <= 1)
        ? 1
        : $clog2(CLKS_PER_BIT);


    logic [BAUD_CNT_WIDTH-1:0] baud_count;

    // 0 = start
    // 1~8 = data[0]~data[7]
    // 9 = stop
    logic [3:0] bit_index;

    logic [7:0] data_reg;


    // ============================================================
    // READY
    // ============================================================

    assign in_ready =
        !busy;


    // ============================================================
    // TX OUTPUT
    // ============================================================

    always_comb begin

        if (!busy) begin

            // UART idle = HIGH
            tx = 1'b1;

        end
        else begin

            case (bit_index)

                // Start bit
                4'd0:
                    tx = 1'b0;

                // LSB first
                4'd1:
                    tx = data_reg[0];

                4'd2:
                    tx = data_reg[1];

                4'd3:
                    tx = data_reg[2];

                4'd4:
                    tx = data_reg[3];

                4'd5:
                    tx = data_reg[4];

                4'd6:
                    tx = data_reg[5];

                4'd7:
                    tx = data_reg[6];

                4'd8:
                    tx = data_reg[7];

                // Stop bit
                4'd9:
                    tx = 1'b1;

                default:
                    tx = 1'b1;

            endcase

        end

    end


    // ============================================================
    // UART STATE / TIMING
    // ============================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            busy       <= 1'b0;
            byte_done  <= 1'b0;

            baud_count <= '0;
            bit_index  <= '0;

            data_reg   <= '0;

        end
        else begin

            // pulse default
            byte_done <= 1'b0;


            // ====================================================
            // IDLE
            // ====================================================

            if (!busy) begin

                baud_count <= '0;
                bit_index  <= '0;


                // ready/valid handshake
                if (in_valid && in_ready) begin

                    // 이 순간 byte를 내부에 복사.
                    // 이후 Packetizer 값이 변해도 영향 없음.
                    data_reg <= in_data;

                    busy <= 1'b1;

                end

            end


            // ====================================================
            // TRANSMITTING
            // ====================================================

            else begin

                if (
                    baud_count ==
                    CLKS_PER_BIT - 1
                ) begin

                    baud_count <= '0;


                    // --------------------------------------------
                    // stop bit 완료
                    // --------------------------------------------

                    if (bit_index == 4'd9) begin

                        busy <= 1'b0;

                        bit_index <= '0;

                        byte_done <= 1'b1;

                    end


                    // --------------------------------------------
                    // next UART bit
                    // --------------------------------------------

                    else begin

                        bit_index <=
                            bit_index + 1'b1;

                    end

                end
                else begin

                    baud_count <=
                        baud_count + 1'b1;

                end

            end

        end

    end


endmodule