`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/21 14:15:27
// Design Name: 
// Module Name: daq_cdc_top
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

module daq_cdc_top #(
    parameter int DATA_WIDTH = 16,
    parameter int ADDR_WIDTH = 4
)(
    input  logic                  acq_clk,
    input  logic                  acq_rst,

    input  logic                  proc_clk,
    input  logic                  proc_rst,

    input  logic                  out_ready,

    output logic [DATA_WIDTH-1:0] out_data,
    output logic                  out_valid
);

    logic [DATA_WIDTH-1:0] sample_data;
    logic                  sample_valid;
    logic                  sample_ready;


    // ============================================================
    // Sensor / ADC Emulator
    // ============================================================

    sensor_emulator #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_sensor_emulator (
        .clk          (acq_clk),
        .rst          (acq_rst),

        .sample_ready (sample_ready),

        .sample_data  (sample_data),
        .sample_valid (sample_valid)
    );


    // ============================================================
    // Acquisition -> Processing CDC
    // ============================================================

    async_fifo_gray #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_async_fifo (
        .wr_clk  (acq_clk),
        .wr_rst  (acq_rst),

        .s_data  (sample_data),
        .s_valid (sample_valid),
        .s_ready (sample_ready),

        .rd_clk  (proc_clk),
        .rd_rst  (proc_rst),

        .m_data  (out_data),
        .m_valid (out_valid),
        .m_ready (out_ready)
    );

endmodule
