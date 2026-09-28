`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/21 10:39:17
// Design Name: 
// Module Name: sensor_emulator
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


module sensor_emulator #(
    parameter int DATA_WIDTH = 16
)(
    input  logic                  clk,
    input  logic                  rst,

    input  logic                  sample_ready,

    output logic [DATA_WIDTH-1:0] sample_data,
    output logic                  sample_valid
);

    always_ff @(posedge clk) begin
        if (rst) begin
            sample_data  <= '0;
            sample_valid <= 1'b0;
        end
        else begin
            sample_valid <= 1'b1;

            if (sample_valid && sample_ready) begin
                sample_data <= sample_data + 1'b1;
            end
        end
    end

endmodule
