`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/21 11:23:40
// Design Name: 
// Module Name: tb_sensor_emulator
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


`timescale 1ns/1ps

module tb_sensor_emulator;

    localparam int DATA_WIDTH = 16;

    logic clk;
    logic rst;

    logic sample_ready;
    logic [DATA_WIDTH-1:0] sample_data;
    logic sample_valid;

    logic [DATA_WIDTH-1:0] expected_data;

    sensor_emulator #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk          (clk),
        .rst          (rst),
        .sample_ready (sample_ready),
        .sample_data  (sample_data),
        .sample_valid (sample_valid)
    );

    // 100 MHz clock
    initial begin
        clk = 1'b0;

        forever #5 clk = ~clk;
    end

    initial begin
        rst          = 1'b1;
        sample_ready = 1'b0;
        expected_data = '0;

        repeat (5) @(posedge clk);

        rst = 1'b0;

        // 정상적으로 계속 받기
        repeat (10) begin
            @(negedge clk);
            sample_ready = 1'b1;
        end

        // Backpressure
        repeat (5) begin
            @(negedge clk);
            sample_ready = 1'b0;
        end

        // 다시 수신
        repeat (10) begin
            @(negedge clk);
            sample_ready = 1'b1;
        end

        @(negedge clk);
        sample_ready = 1'b0;

        repeat (3) @(posedge clk);

        $display("SENSOR_EMULATOR_TEST_PASS");
        $finish;
    end

    always @(posedge clk) begin
        if (rst) begin
            expected_data <= '0;
        end
        else begin
            if (sample_valid && sample_ready) begin

                if (sample_data !== expected_data) begin
                    $error(
                        "DATA ERROR: expected=%0d actual=%0d",
                        expected_data,
                        sample_data
                    );

                    $fatal;
                end

                expected_data <= expected_data + 1'b1;
            end
        end
    end

endmodule
