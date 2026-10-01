`timescale 1ns / 1ps

module event_capture #(
    parameter int DEPTH        = 2048,
    parameter int ADDR_WIDTH   = 11,
    parameter int PRE_SAMPLES  = 1024,
    parameter int POST_SAMPLES = 1023
)(
    input  logic clk,
    input  logic rst,

    // 실제 accepted sample
    input  logic sample_fire,

    // 72-bit aligned sample bundle
    input  logic [31:0] sample_index,
    input  logic [7:0]  fault_flags,
    input  logic signed [15:0] raw_sample,
    input  logic signed [15:0] filtered_sample,

    // Trigger Detector output
    input  logic trigger_pulse,

    // Capture status
    output logic trigger_enable,
    output logic event_done,

    // Event location
    output logic [ADDR_WIDTH-1:0] trigger_ptr,
    output logic [ADDR_WIDTH-1:0] start_ptr,

    // Packetizer read port
    input  logic [ADDR_WIDTH-1:0] read_addr,
    output logic [71:0] read_data,

    // Packet transmission finished
    input  logic readout_done
);


    // ============================================================
    // EVENT MEMORY
    // ============================================================

    logic [71:0] event_mem [0:DEPTH-1];


    // ============================================================
    // WRITE POINTER
    //
    // DEPTH=2048
    // ADDR_WIDTH=11
    //
    // 2047 + 1 → 0
    // ============================================================

    logic [ADDR_WIDTH-1:0] write_ptr;


    // ============================================================
    // COUNTERS
    // ============================================================

    localparam int PRE_COUNT_WIDTH =
        $clog2(PRE_SAMPLES + 1);

    localparam int POST_COUNT_WIDTH =
        $clog2(POST_SAMPLES + 1);


    logic [PRE_COUNT_WIDTH-1:0] pre_count;
    logic [POST_COUNT_WIDTH-1:0] post_count;


    // start_ptr = trigger_ptr - 1024 mod 2048
    localparam logic [ADDR_WIDTH-1:0] PRE_OFFSET =
        PRE_SAMPLES;


    // ============================================================
    // FSM
    // ============================================================

    typedef enum logic [1:0] {

        CIRCULAR_RECORD,
        POST_CAPTURE,
        EVENT_FROZEN

    } state_t;


    state_t state;


    // ============================================================
    // CAPTURE FSM
    // ============================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            state          <= CIRCULAR_RECORD;

            write_ptr      <= '0;

            pre_count      <= '0;
            post_count     <= '0;

            trigger_enable <= 1'b0;
            event_done     <= 1'b0;

            trigger_ptr    <= '0;
            start_ptr      <= '0;

        end
        else begin

            case (state)


                // =================================================
                // 1. 평상시 Circular Buffer
                // =================================================
                CIRCULAR_RECORD: begin

                    event_done <= 1'b0;


                    if (sample_fire) begin

                        // 현재 sample 저장
                        event_mem[write_ptr] <= {
                            sample_index,
                            fault_flags,
                            raw_sample,
                            filtered_sample
                        };


                        // -------------------------------------------------
                        // Trigger 발생
                        // -------------------------------------------------

                        if (trigger_enable &&
                            trigger_pulse) begin


                            // 현재 write address가
                            // trigger sample address
                            trigger_ptr <= write_ptr;


                            // trigger보다 1024 samples 이전
                            start_ptr <=
                                write_ptr - PRE_OFFSET;


                            // trigger sample 저장 후
                            // 다음 주소부터 POST
                            write_ptr <=
                                write_ptr + 1'b1;


                            post_count <= '0;


                            trigger_enable <= 1'b0;

                            state <= POST_CAPTURE;

                        end


                        // -------------------------------------------------
                        // 아직 trigger 없음
                        // -------------------------------------------------

                        else begin

                            write_ptr <=
                                write_ptr + 1'b1;


                            // PRE history 확보
                            if (pre_count < PRE_SAMPLES) begin


                                if (
                                    pre_count ==
                                    PRE_SAMPLES - 1
                                ) begin

                                    pre_count <=
                                        PRE_SAMPLES;

                                    trigger_enable <=
                                        1'b1;

                                end
                                else begin

                                    pre_count <=
                                        pre_count + 1'b1;

                                end

                            end

                        end

                    end

                end


                // =================================================
                // 2. Trigger 이후 1023 samples 저장
                // =================================================
                POST_CAPTURE: begin

                    trigger_enable <= 1'b0;
                    event_done     <= 1'b0;


                    if (sample_fire) begin

                        event_mem[write_ptr] <= {
                            sample_index,
                            fault_flags,
                            raw_sample,
                            filtered_sample
                        };


                        write_ptr <=
                            write_ptr + 1'b1;


                        // 지금 들어온 sample이
                        // 1023번째 POST sample
                        if (
                            post_count ==
                            POST_SAMPLES - 1
                        ) begin

                            post_count <=
                                POST_SAMPLES;

                            event_done <=
                                1'b1;

                            state <=
                                EVENT_FROZEN;

                        end

                        else begin

                            post_count <=
                                post_count + 1'b1;

                        end

                    end

                end


                // =================================================
                // 3. Event Buffer Freeze
                // =================================================
                EVENT_FROZEN: begin

                    trigger_enable <= 1'b0;
                    event_done     <= 1'b1;


                    // sample_fire가 들어와도
                    // event_mem은 더 이상 쓰지 않음


                    if (readout_done) begin

                        state <=
                            CIRCULAR_RECORD;


                        // 새로운 event는
                        // fresh history부터 시작
                        write_ptr  <= '0;

                        pre_count  <= '0;
                        post_count <= '0;


                        trigger_enable <=
                            1'b0;

                        event_done <=
                            1'b0;


                        trigger_ptr <= '0;
                        start_ptr   <= '0;

                    end

                end


                default: begin

                    state <= CIRCULAR_RECORD;

                    write_ptr <= '0;

                    pre_count  <= '0;
                    post_count <= '0;

                    trigger_enable <= 1'b0;
                    event_done     <= 1'b0;

                    trigger_ptr <= '0;
                    start_ptr   <= '0;

                end

            endcase

        end

    end


    // ============================================================
    // SYNCHRONOUS READ PORT
    //
    // 나중에 Packetizer가 사용
    // ============================================================

    always_ff @(posedge clk) begin

        read_data <=
            event_mem[read_addr];

    end


endmodule