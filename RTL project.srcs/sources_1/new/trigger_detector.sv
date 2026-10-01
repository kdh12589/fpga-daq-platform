`timescale 1ns / 1ps

module trigger_detector #(
    parameter int DATA_WIDTH = 16,
    parameter logic signed [DATA_WIDTH-1:0] LOW_THRESHOLD  = 16'sd900,
    parameter logic signed [DATA_WIDTH-1:0] HIGH_THRESHOLD = 16'sd1000
)(
    input  logic clk,
    input  logic rst,

    input  logic sample_fire,
    input  logic trigger_enable,
    input  logic signed [DATA_WIDTH-1:0] sample_data,

    output logic trigger_pulse,
    output logic armed
);

    always_ff @(posedge clk) begin
        if (rst) begin
            trigger_pulse <= 1'b0;
            armed         <= 1'b0;
        end
        else begin
            // 기본적으로 pulse는 0
            trigger_pulse <= 1'b0;

            // 실제 sample이 들어왔을 때만 상태 변화
            if (sample_fire) begin

                // LOW 이하로 내려오면 다음 crossing 준비
                if (sample_data <= LOW_THRESHOLD) begin
                    armed <= 1'b1;
                end

                // armed 상태에서 HIGH crossing
                else if (armed &&
                         (sample_data >= HIGH_THRESHOLD)) begin

                    // crossing은 소비
                    armed <= 1'b0;

                    // capture가 허용된 경우에만 trigger 발생
                    if (trigger_enable)
                        trigger_pulse <= 1'b1;
                end
            end
        end
    end

endmodule