`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/22 12:07:31
// Design Name: 
// Module Name: daq_dsp_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module daq_dsp_top #(
    parameter int DATA_WIDTH = 16,
    parameter int ADDR_WIDTH = 4
)(
    input  logic                         acq_clk,
    input  logic                         acq_rst,

    input  logic                         proc_clk,
    input  logic                         proc_rst,

    // Final filtered stream
    output logic signed [DATA_WIDTH-1:0] out_data,
    output logic                         out_valid,
    input  logic                         out_ready
);

    // ============================================================
    // Sensor -> Async FIFO
    // ============================================================

    logic [DATA_WIDTH-1:0] sensor_data;
    logic                  sensor_valid;
    logic                  sensor_ready;


    // ============================================================
    // Async FIFO -> FIR
    // ============================================================

    logic [DATA_WIDTH-1:0] fifo_data;
    logic                  fifo_valid;
    logic                  fifo_ready;


    // ============================================================
    // Sensor Emulator
    // ============================================================

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
    // CDC Async FIFO
    // ============================================================

    async_fifo_gray #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_async_fifo (
        .wr_clk   (acq_clk),
        .wr_rst   (acq_rst),

        .s_data   (sensor_data),
        .s_valid  (sensor_valid),
        .s_ready  (sensor_ready),

        .rd_clk   (proc_clk),
        .rd_rst   (proc_rst),

        .m_data   (fifo_data),
        .m_valid  (fifo_valid),
        .m_ready  (fifo_ready)
    );


    // ============================================================
    // Fixed-point FIR
    // ============================================================

    fir8_fixed #(
        .DATA_WIDTH(DATA_WIDTH),
        .COEF_WIDTH(16),
        .FRAC_BITS (15)
    ) u_fir (
        .clk       (proc_clk),
        .rst       (proc_rst),

        .in_data   ($signed(fifo_data)),
        .in_valid  (fifo_valid),
        .in_ready  (fifo_ready),

        .out_data  (out_data),
        .out_valid (out_valid),
        .out_ready (out_ready)
    );

endmodule
