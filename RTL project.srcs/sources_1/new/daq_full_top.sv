`timescale 1ns / 1ps

module daq_full_top #(
    parameter int DATA_WIDTH      = 16,

    // Final baseline: 64-entry async FIFO
    parameter int FIFO_ADDR_WIDTH = 6,

    parameter int PROC_CLK_HZ     = 125_000_000,
    parameter int UART_BAUD       = 921_600,

    parameter logic signed [15:0] TRIG_LOW  = 16'sd1400,
    parameter logic signed [15:0] TRIG_HIGH = 16'sd1500
)(
    input logic acq_clk,
    input logic acq_rst,

    input logic proc_clk,
    input logic proc_rst,

    // Physical UART
    output logic tx,

    // ------------------------------------------------------------
    // Status
    // ------------------------------------------------------------
    output logic event_done,
    output logic trigger_enable,

    output logic packetizer_busy,
    output logic packetizer_done,

    output logic uart_busy,
    output logic tx_complete,

    output logic [10:0] trigger_ptr,
    output logic [10:0] start_ptr,

    // ------------------------------------------------------------
    // Debug
    // ------------------------------------------------------------
    output logic signed [15:0] aligned_raw,
    output logic signed [15:0] aligned_filtered,
    output logic [31:0]        aligned_index,
    output logic               aligned_valid,
    output logic               trigger_pulse,

    output logic               packet_start_dbg
);


    // ============================================================
    // EVENT MEMORY CONNECTION
    // ============================================================

    logic [10:0] event_read_addr;
    logic [71:0] event_read_data;

    logic readout_done;


    // ============================================================
    // 1. ACQUISITION + DSP + TRIGGER + EVENT CAPTURE
    // ============================================================

    daq_event_top #(
        .DATA_WIDTH      (DATA_WIDTH),
        .FIFO_ADDR_WIDTH (FIFO_ADDR_WIDTH),

        .TRIG_LOW        (TRIG_LOW),
        .TRIG_HIGH       (TRIG_HIGH)
    ) u_daq_event (

        .acq_clk          (acq_clk),
        .acq_rst          (acq_rst),

        .proc_clk         (proc_clk),
        .proc_rst         (proc_rst),

        .event_done       (event_done),
        .trigger_enable   (trigger_enable),

        .trigger_ptr      (trigger_ptr),
        .start_ptr        (start_ptr),

        .read_addr        (event_read_addr),
        .read_data        (event_read_data),

        .readout_done     (readout_done),

        .aligned_raw      (aligned_raw),
        .aligned_filtered (aligned_filtered),
        .aligned_index    (aligned_index),
        .aligned_valid    (aligned_valid),

        .trigger_pulse    (trigger_pulse)
    );


    // ============================================================
    // 2. EVENT_DONE RISING EDGE → PACKET START
    //
    // event_done은 UART 전송이 끝날 때까지 HIGH로 유지된다.
    // 따라서 level을 그대로 start에 넣으면 packet이 반복 실행됨.
    //
    // 반드시 1-cycle pulse로 변환.
    // ============================================================

    logic event_done_d;
    logic packet_start;


    always_ff @(posedge proc_clk) begin

        if (proc_rst) begin

            event_done_d <= 1'b0;
            packet_start <= 1'b0;

        end
        else begin

            packet_start <= 1'b0;

            event_done_d <=
                event_done;


            if (
                event_done &&
                !event_done_d
            ) begin

                packet_start <=
                    1'b1;

            end

        end

    end


    assign packet_start_dbg =
        packet_start;


    // ============================================================
    // 3. PACKETIZER + CRC + UART
    // ============================================================

    packet_uart_top #(
        .CLK_HZ (PROC_CLK_HZ),
        .BAUD   (UART_BAUD)
    ) u_packet_uart (

        .clk             (proc_clk),
        .rst             (proc_rst),

        .packet_start    (packet_start),
        .start_ptr       (start_ptr),

        .mem_addr        (event_read_addr),
        .mem_data        (event_read_data),

        .packetizer_busy (packetizer_busy),
        .packetizer_done (packetizer_done),

        .uart_busy       (uart_busy),

        .tx_complete     (tx_complete),

        .tx              (tx)
    );


    // ============================================================
    // 4. AUTOMATIC EVENT RELEASE
    //
    // 여기서는 의미를 가장 명확하게 하기 위해:
    //
    // 실제 마지막 UART stop bit까지 끝난 뒤
    // Event Capture를 release한다.
    //
    // tx_complete = 1 cycle pulse
    // ============================================================

    assign readout_done =
        tx_complete;


endmodule