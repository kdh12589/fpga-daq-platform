`timescale 1ns / 1ps

module daq_event_top #(
    parameter int DATA_WIDTH      = 16,
    parameter int FIFO_ADDR_WIDTH = 4,

    parameter logic signed [15:0] TRIG_LOW  = 16'sd1400,
    parameter logic signed [15:0] TRIG_HIGH = 16'sd1500
)(
    input logic acq_clk,
    input logic acq_rst,

    input logic proc_clk,
    input logic proc_rst,

    // Event status
    output logic event_done,
    output logic trigger_enable,

    output logic [10:0] trigger_ptr,
    output logic [10:0] start_ptr,

    // Event memory read port
    input  logic [10:0] read_addr,
    output logic [71:0] read_data,

    input logic readout_done,

    // Debug / observation
    output logic signed [15:0] aligned_raw,
    output logic signed [15:0] aligned_filtered,
    output logic [31:0]        aligned_index,
    output logic               aligned_valid,
    output logic               trigger_pulse
);


    // ============================================================
    // 1. SENSOR
    // ============================================================

    logic [DATA_WIDTH-1:0] sensor_data;
    logic                  sensor_valid;
    logic                  sensor_ready;


    sensor_emulator #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_sensor (
        .clk          (acq_clk),
        .rst          (acq_rst),

        .sample_ready (sensor_ready),

        .sample_data  (sensor_data),
        .sample_valid (sensor_valid)
    );


    // ============================================================
    // 2. ASYNC FIFO
    // ============================================================

    logic [DATA_WIDTH-1:0] fifo_data;
    logic                  fifo_valid;
    logic                  fifo_ready;


    async_fifo_gray #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(FIFO_ADDR_WIDTH)
    ) u_fifo (
        .wr_clk  (acq_clk),
        .wr_rst  (acq_rst),

        .s_data  (sensor_data),
        .s_valid (sensor_valid),
        .s_ready (sensor_ready),

        .rd_clk  (proc_clk),
        .rd_rst  (proc_rst),

        .m_data  (fifo_data),
        .m_valid (fifo_valid),
        .m_ready (fifo_ready)
    );


    // ============================================================
    // 3. FIR
    // ============================================================

    logic signed [15:0] fir_data;
    logic               fir_valid;

    // Event path는 upstream을 막지 않는다.
    logic fir_ready;

    assign fir_ready = 1'b1;


    fir8_fixed #(
        .DATA_WIDTH(DATA_WIDTH),
        .COEF_WIDTH(16),
        .FRAC_BITS(15)
    ) u_fir (
        .clk       (proc_clk),
        .rst       (proc_rst),

        .in_data   ($signed(fifo_data)),
        .in_valid  (fifo_valid),
        .in_ready  (fifo_ready),

        .out_data  (fir_data),
        .out_valid (fir_valid),
        .out_ready (fir_ready)
    );


    // ============================================================
    // 4. SIDEBAND ALIGNMENT
    //
    // FIR이 x[n]을 accept한 같은 edge에서
    // raw[n], index[n], flags[n]도 저장한다.
    //
    // 다음 cycle FIR output filtered[n]과
    // 같은 logical sample이 된다.
    // ============================================================

    logic [31:0] sample_counter;

    logic signed [15:0] raw_pipe;
    logic [31:0]        index_pipe;
    logic [7:0]         flags_pipe;

    logic fir_input_fire;

    assign fir_input_fire =
        fifo_valid && fifo_ready;


    always_ff @(posedge proc_clk) begin

        if (proc_rst) begin

            sample_counter <= '0;

            raw_pipe   <= '0;
            index_pipe <= '0;
            flags_pipe <= '0;

        end
        else begin

            if (fir_input_fire) begin

                raw_pipe <=
                    $signed(fifo_data);

                index_pipe <=
                    sample_counter;

                // 아직 실제 fault detector가 없으므로
                // MVP에서는 0
                flags_pipe <=
                    8'h00;

                sample_counter <=
                    sample_counter + 1'b1;

            end

        end

    end


    // ============================================================
    // 5. ALIGNED STREAM
    // ============================================================

    assign aligned_raw      = raw_pipe;
    assign aligned_filtered = fir_data;
    assign aligned_index    = index_pipe;
    assign aligned_valid    = fir_valid;

    // ============================================================
// 5-A. EVENT-CAPTURE ALIGNMENT STAGE
//
// trigger_detector의 trigger_pulse는 registered output이다.
//
// 즉 aligned sample n을 본 뒤,
// trigger_pulse는 다음 cycle에 유효해진다.
//
// 따라서 Event Capture로 들어가는 sample bundle도
// 1 cycle delay시켜 trigger_pulse와 맞춘다.
// ============================================================

logic signed [15:0] capture_raw;
logic signed [15:0] capture_filtered;

logic [31:0] capture_index;
logic [7:0]  capture_flags;

logic capture_valid;


always_ff @(posedge proc_clk) begin

    if (proc_rst) begin

        capture_raw      <= '0;
        capture_filtered <= '0;

        capture_index    <= '0;
        capture_flags    <= '0;

        capture_valid    <= 1'b0;

    end
    else begin

        // Event path에는 backpressure가 없으므로
        // FIR output valid를 그대로 1-cycle delay
        capture_valid <= aligned_valid;


        if (aligned_valid) begin

            capture_raw <=
                aligned_raw;

            capture_filtered <=
                aligned_filtered;

            capture_index <=
                aligned_index;

            capture_flags <=
                flags_pipe;

        end

    end

end

    // ============================================================
    // 6. TRIGGER DETECTOR
    //
    // filtered signal을 관찰한다.
    // ============================================================

    trigger_detector #(
        .DATA_WIDTH(16),
        .LOW_THRESHOLD(TRIG_LOW),
        .HIGH_THRESHOLD(TRIG_HIGH)
    ) u_trigger (
        .clk            (proc_clk),
        .rst            (proc_rst),

        .sample_fire    (aligned_valid),

        .trigger_enable (trigger_enable),

        .sample_data    (aligned_filtered),

        .trigger_pulse  (trigger_pulse),

        .armed          ()
    );


    // ============================================================
    // 7. EVENT CAPTURE
    // ============================================================

    event_capture #(
        .DEPTH        (2048),
        .ADDR_WIDTH   (11),
        .PRE_SAMPLES  (1024),
        .POST_SAMPLES (1023)
    ) u_event_capture (
        .clk             (proc_clk),
        .rst             (proc_rst),

        .sample_fire     (capture_valid),

        .sample_index    (capture_index),
        .fault_flags     (capture_flags),

        .raw_sample      (capture_raw),
        .filtered_sample (capture_filtered),

        .trigger_pulse   (trigger_pulse),

        .trigger_enable  (trigger_enable),
        .event_done      (event_done),

        .trigger_ptr     (trigger_ptr),
        .start_ptr       (start_ptr),

        .read_addr       (read_addr),
        .read_data       (read_data),

        .readout_done    (readout_done)
    );


endmodule