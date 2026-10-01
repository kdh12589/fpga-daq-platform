`timescale 1ns / 1ps

module packet_uart_top #(
    parameter int CLK_HZ = 100_000_000,
    parameter int BAUD   = 921_600
)(
    input logic clk,
    input logic rst,


    // ============================================================
    // Packet start
    // ============================================================

    input logic        packet_start,
    input logic [10:0] start_ptr,


    // ============================================================
    // Event memory
    // ============================================================

    output logic [10:0] mem_addr,
    input  logic [71:0] mem_data,


    // ============================================================
    // Status
    // ============================================================

    output logic packetizer_busy,

    // 마지막 packet byte가 UART 내부에 인수됨
    output logic packetizer_done,

    output logic uart_busy,

    // 마지막 packet byte의 stop bit까지 실제 출력 완료
    output logic tx_complete,


    // ============================================================
    // Physical UART output
    // ============================================================

    output logic tx
);


    // ============================================================
    // PACKETIZER BYTE STREAM
    // ============================================================

    logic [7:0] packet_byte;

    logic packet_valid;
    logic packet_ready;


    event_packetizer u_packetizer (

        .clk       (clk),
        .rst       (rst),

        .start     (packet_start),
        .start_ptr (start_ptr),

        .busy      (packetizer_busy),
        .done      (packetizer_done),

        .mem_addr  (mem_addr),
        .mem_data  (mem_data),

        .out_byte  (packet_byte),
        .out_valid (packet_valid),
        .out_ready (packet_ready)

    );


    // ============================================================
    // UART
    // ============================================================

    logic uart_byte_done;


    uart_tx #(
        .CLK_HZ (CLK_HZ),
        .BAUD   (BAUD)
    ) u_uart_tx (

        .clk       (clk),
        .rst       (rst),

        .in_data   (packet_byte),
        .in_valid  (packet_valid),
        .in_ready  (packet_ready),

        .tx        (tx),

        .busy      (uart_busy),

        .byte_done (uart_byte_done)

    );


    // ============================================================
    // FINAL PACKET TRANSMISSION COMPLETE
    //
    // packetizer_done:
    //   마지막 CRC byte를 UART가 받은 시점
    //
    // tx_complete:
    //   그 마지막 byte의 stop bit까지 실제 pin으로 나간 시점
    // ============================================================

    logic final_byte_in_flight;


    always_ff @(posedge clk) begin

        if (rst) begin

            final_byte_in_flight <=
                1'b0;

            tx_complete <=
                1'b0;

        end
        else begin

            tx_complete <=
                1'b0;


            // 마지막 packet byte가 UART로 전달됨
            if (packetizer_done) begin

                final_byte_in_flight <=
                    1'b1;

            end


            // 마지막 UART frame까지 끝남
            if (
                final_byte_in_flight &&
                uart_byte_done
            ) begin

                final_byte_in_flight <=
                    1'b0;

                tx_complete <=
                    1'b1;

            end

        end

    end


endmodule