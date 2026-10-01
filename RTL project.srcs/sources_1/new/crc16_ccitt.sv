`timescale 1ns / 1ps

module crc16_ccitt (
    input  logic        clk,
    input  logic        rst,

    input  logic        clear,

    input  logic        data_valid,
    input  logic [7:0]  data_byte,

    output logic [15:0] crc_out
);


    // ============================================================
    // CRC-16 / CCITT-FALSE
    //
    // Polynomial : 0x1021
    // Initial    : 0xFFFF
    // RefIn      : false
    // RefOut     : false
    // XorOut     : 0x0000
    //
    // Standard check:
    // "123456789" -> 0x29B1
    // ============================================================


    function automatic logic [15:0] crc16_next_byte (
        input logic [15:0] crc_in,
        input logic [7:0]  data_in
    );

        logic [15:0] crc;
        integer i;

        begin

            crc = crc_in;

            // MSB-first processing
            for (i = 0; i < 8; i = i + 1) begin

                if (crc[15] ^ data_in[7-i]) begin

                    crc =
                        {crc[14:0], 1'b0}
                        ^ 16'h1021;

                end
                else begin

                    crc =
                        {crc[14:0], 1'b0};

                end

            end

            crc16_next_byte = crc;

        end

    endfunction


    // ============================================================
    // CRC REGISTER
    // ============================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            crc_out <= 16'hFFFF;

        end
        else if (clear) begin

            crc_out <= 16'hFFFF;

        end
        else if (data_valid) begin

            crc_out <=
                crc16_next_byte(
                    crc_out,
                    data_byte
                );

        end

    end


endmodule