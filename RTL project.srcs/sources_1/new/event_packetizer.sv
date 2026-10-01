`timescale 1ns / 1ps

module event_packetizer (

    input  logic        clk,
    input  logic        rst,

    // ------------------------------------------------------------
    // Control
    // ------------------------------------------------------------

    input  logic        start,
    input  logic [10:0] start_ptr,

    output logic        busy,
    output logic        done,


    // ------------------------------------------------------------
    // Event memory read interface
    //
    // External memory:
    //
    // always_ff @(posedge clk)
    //     mem_data <= event_mem[mem_addr];
    //
    // synchronous read를 가정한다.
    // ------------------------------------------------------------

    output logic [10:0] mem_addr,
    input  logic [71:0] mem_data,


    // ------------------------------------------------------------
    // Output byte stream
    //
    // transfer only when:
    //
    // out_valid && out_ready
    // ------------------------------------------------------------

    output logic [7:0]  out_byte,
    output logic        out_valid,
    input  logic        out_ready

);


    // ============================================================
    // PACKET FORMAT
    //
    // Header  :    16 bytes
    // Payload : 18432 bytes = 2048 * 9
    // CRC     :     2 bytes
    //
    // Total   : 18450 bytes
    // ============================================================


    // ============================================================
    // STATE MACHINE
    // ============================================================

    typedef enum logic [3:0] {

        ST_IDLE,

        ST_HEADER,

        ST_MEM_REQ,
        ST_MEM_WAIT,
        ST_MEM_CAPTURE,

        ST_PAYLOAD,

        ST_CRC_HI,
        ST_CRC_LO,

        ST_DONE

    } state_t;


    state_t state;


    // ============================================================
    // INTERNAL REGISTERS
    // ============================================================

    logic [4:0] header_index;

    logic [10:0] sample_index;
    logic [3:0]  payload_byte_index;

    logic [10:0] start_ptr_reg;

    logic [10:0] mem_addr_reg;

    logic [71:0] sample_buffer;


    assign mem_addr = mem_addr_reg;


    // ============================================================
    // READY / VALID FIRE
    // ============================================================

    logic out_fire;

    assign out_fire =
        out_valid &&
        out_ready;


    // ============================================================
    // HEADER BYTE GENERATOR
    //
    // 0~3    : "DAQ1"
    // 4      : Version = 1
    // 5      : Flags
    // 6~9    : Payload length = 18432 = 0x00004800
    // 10~11  : Sample count = 2048 = 0x0800
    // 12~13  : Trigger offset = 1024 = 0x0400
    // 14     : Bytes/sample = 9
    // 15     : Reserved
    // ============================================================

    function automatic logic [7:0] get_header_byte (
        input logic [4:0] index
    );

        begin

            case (index)

                5'd0:  get_header_byte = 8'h44; // D
                5'd1:  get_header_byte = 8'h41; // A
                5'd2:  get_header_byte = 8'h51; // Q
                5'd3:  get_header_byte = 8'h31; // 1

                5'd4:  get_header_byte = 8'h01; // version
                5'd5:  get_header_byte = 8'h00; // flags

                // Payload length = 0x00004800
                5'd6:  get_header_byte = 8'h00;
                5'd7:  get_header_byte = 8'h00;
                5'd8:  get_header_byte = 8'h48;
                5'd9:  get_header_byte = 8'h00;

                // Sample count = 0x0800
                5'd10: get_header_byte = 8'h08;
                5'd11: get_header_byte = 8'h00;

                // Trigger offset = 0x0400
                5'd12: get_header_byte = 8'h04;
                5'd13: get_header_byte = 8'h00;

                5'd14: get_header_byte = 8'h09;
                5'd15: get_header_byte = 8'h00;

                default:
                    get_header_byte = 8'h00;

            endcase

        end

    endfunction


    // ============================================================
    // PAYLOAD BYTE GENERATOR
    //
    // event entry:
    //
    // [71:40] sample_index
    // [39:32] fault_flags
    // [31:16] raw_sample
    // [15:0]  filtered_sample
    //
    // MSB first
    // ============================================================

    function automatic logic [7:0] get_payload_byte (
        input logic [3:0] byte_index,
        input logic [71:0] data
    );

        begin

            case (byte_index)

                4'd0: get_payload_byte = data[71:64];
                4'd1: get_payload_byte = data[63:56];
                4'd2: get_payload_byte = data[55:48];
                4'd3: get_payload_byte = data[47:40];

                4'd4: get_payload_byte = data[39:32];

                4'd5: get_payload_byte = data[31:24];
                4'd6: get_payload_byte = data[23:16];

                4'd7: get_payload_byte = data[15:8];
                4'd8: get_payload_byte = data[7:0];

                default:
                    get_payload_byte = 8'h00;

            endcase

        end

    endfunction


    // ============================================================
    // CRC16
    // ============================================================

    logic        crc_clear;
    logic        crc_data_valid;
    logic [7:0]  crc_data_byte;

    logic [15:0] crc_value;


    assign crc_clear =
        (state == ST_IDLE) &&
        start;


    // CRC에는 Header + Payload만 넣는다.
    //
    // CRC byte 자체는 CRC 계산에 포함하지 않는다.

    assign crc_data_valid =
        out_fire &&
        (
            (state == ST_HEADER) ||
            (state == ST_PAYLOAD)
        );


    assign crc_data_byte =
        out_byte;


    crc16_ccitt u_crc16 (

        .clk        (clk),
        .rst        (rst),

        .clear      (crc_clear),

        .data_valid (crc_data_valid),
        .data_byte  (crc_data_byte),

        .crc_out    (crc_value)

    );


    // ============================================================
    // OUTPUT COMBINATIONAL LOGIC
    // ============================================================

    always_comb begin

        out_valid = 1'b0;
        out_byte  = 8'h00;


        case (state)


            // ----------------------------------------------------
            // HEADER
            // ----------------------------------------------------

            ST_HEADER: begin

                out_valid = 1'b1;

                out_byte =
                    get_header_byte(
                        header_index
                    );

            end


            // ----------------------------------------------------
            // PAYLOAD
            // ----------------------------------------------------

            ST_PAYLOAD: begin

                out_valid = 1'b1;

                out_byte =
                    get_payload_byte(
                        payload_byte_index,
                        sample_buffer
                    );

            end


            // ----------------------------------------------------
            // CRC
            // ----------------------------------------------------

            ST_CRC_HI: begin

                out_valid = 1'b1;

                out_byte =
                    crc_value[15:8];

            end


            ST_CRC_LO: begin

                out_valid = 1'b1;

                out_byte =
                    crc_value[7:0];

            end


            default: begin

                out_valid = 1'b0;
                out_byte  = 8'h00;

            end


        endcase

    end


    // ============================================================
    // STATUS
    // ============================================================

    assign busy =
        (state != ST_IDLE);

    assign done =
        (state == ST_DONE);


    // ============================================================
    // MAIN FSM
    // ============================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            state <=
                ST_IDLE;

            header_index <=
                '0;

            sample_index <=
                '0;

            payload_byte_index <=
                '0;

            start_ptr_reg <=
                '0;

            mem_addr_reg <=
                '0;

            sample_buffer <=
                '0;

        end
        else begin


            case (state)


                // =================================================
                // IDLE
                // =================================================

                ST_IDLE: begin

                    header_index <=
                        '0;

                    sample_index <=
                        '0;

                    payload_byte_index <=
                        '0;


                    if (start) begin

                        start_ptr_reg <=
                            start_ptr;

                        state <=
                            ST_HEADER;

                    end

                end


                // =================================================
                // HEADER
                // =================================================

                ST_HEADER: begin

                    if (out_fire) begin

                        if (header_index == 5'd15) begin

                            header_index <=
                                '0;

                            sample_index <=
                                '0;

                            state <=
                                ST_MEM_REQ;

                        end
                        else begin

                            header_index <=
                                header_index + 1'b1;

                        end

                    end

                end


                // =================================================
                // MEMORY REQUEST
                //
                // mem_addr register에 주소를 넣는다.
                // =================================================

                ST_MEM_REQ: begin

                    mem_addr_reg <=
                        start_ptr_reg +
                        sample_index;

                    state <=
                        ST_MEM_WAIT;

                end


                // =================================================
                // MEMORY WAIT
                //
                // synchronous memory가 mem_addr를 sampling하고
                // read_data를 갱신할 시간을 준다.
                // =================================================

                ST_MEM_WAIT: begin

                    state <=
                        ST_MEM_CAPTURE;

                end


                // =================================================
                // MEMORY CAPTURE
                //
                // 원하는 72-bit entry를 내부 register에 저장.
                // =================================================

                ST_MEM_CAPTURE: begin

                    sample_buffer <=
                        mem_data;

                    payload_byte_index <=
                        '0;

                    state <=
                        ST_PAYLOAD;

                end


                // =================================================
                // PAYLOAD
                // =================================================

                ST_PAYLOAD: begin

                    if (out_fire) begin

                        // 9번째 byte까지 보냈으면
                        if (payload_byte_index == 4'd8) begin

                            payload_byte_index <=
                                '0;


                            // --------------------------------------
                            // Last sample
                            // --------------------------------------

                            if (sample_index == 11'd2047) begin

                                state <=
                                    ST_CRC_HI;

                            end

                            // --------------------------------------
                            // Next sample
                            // --------------------------------------

                            else begin

                                sample_index <=
                                    sample_index + 1'b1;

                                state <=
                                    ST_MEM_REQ;

                            end

                        end
                        else begin

                            payload_byte_index <=
                                payload_byte_index + 1'b1;

                        end

                    end

                end


                // =================================================
                // CRC HIGH
                // =================================================

                ST_CRC_HI: begin

                    if (out_fire) begin

                        state <=
                            ST_CRC_LO;

                    end

                end


                // =================================================
                // CRC LOW
                // =================================================

                ST_CRC_LO: begin

                    if (out_fire) begin

                        state <=
                            ST_DONE;

                    end

                end


                // =================================================
                // DONE
                //
                // 정확히 한 cycle pulse
                // =================================================

                ST_DONE: begin

                    state <=
                        ST_IDLE;

                end


                default: begin

                    state <=
                        ST_IDLE;

                end


            endcase

        end

    end


endmodule