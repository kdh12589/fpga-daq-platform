
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/29 23:15:15
// Design Name: 
// Module Name: tb_trigger_detector
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

`timescale 1ns / 1ps

module tb_trigger_detector;

    localparam int DATA_WIDTH = 16;
    localparam logic signed [DATA_WIDTH-1:0] LOW_THRESHOLD  = 16'sd900;
    localparam logic signed [DATA_WIDTH-1:0] HIGH_THRESHOLD = 16'sd1000;

    logic clk;
    logic rst;

    logic sample_fire;
    logic trigger_enable;
    logic signed [DATA_WIDTH-1:0] sample_data;

    logic trigger_pulse;
    logic armed;

    int error_count;

    trigger_detector #(
        .DATA_WIDTH(DATA_WIDTH),
        .LOW_THRESHOLD(LOW_THRESHOLD),
        .HIGH_THRESHOLD(HIGH_THRESHOLD)
    ) dut (
        .clk            (clk),
        .rst            (rst),
        .sample_fire    (sample_fire),
        .trigger_enable (trigger_enable),
        .sample_data    (sample_data),
        .trigger_pulse  (trigger_pulse),
        .armed          (armed)
    );

    // 100 MHz
    initial clk = 1'b0;
    always #5 clk = ~clk;


    task automatic send_sample(
        input logic signed [DATA_WIDTH-1:0] value,
        input logic fire,
        input logic enable
    );
    begin
        @(negedge clk);

        sample_data    = value;
        sample_fire    = fire;
        trigger_enable = enable;

        @(posedge clk);
        #1;
    end
    endtask


    task automatic check_state(
        input logic expected_armed,
        input logic expected_trigger,
        input string message
    );
    begin
        if ((armed !== expected_armed) ||
            (trigger_pulse !== expected_trigger)) begin

            $error(
                "%s | armed=%0b expected=%0b trigger=%0b expected=%0b",
                message,
                armed,
                expected_armed,
                trigger_pulse,
                expected_trigger
            );

            error_count++;
        end
    end
    endtask


    initial begin

        error_count    = 0;
        rst            = 1'b1;
        sample_fire    = 1'b0;
        trigger_enable = 1'b0;
        sample_data    = '0;

        // ------------------------------------------------------------
        // RESET
        // ------------------------------------------------------------
        repeat (3) @(posedge clk);

        @(negedge clk);
        rst = 1'b0;

        @(posedge clk);
        #1;

        check_state(
            1'b0,
            1'b0,
            "RESET"
        );


        // ------------------------------------------------------------
        // 1. HIGH 상태로 시작하면 arm되지 않아야 함
        // ------------------------------------------------------------
        send_sample(16'sd1100, 1'b1, 1'b1);

        check_state(
            1'b0,
            1'b0,
            "HIGH WITHOUT LOW"
        );


        // ------------------------------------------------------------
        // 2. LOW 이하로 내려가면 armed
        // ------------------------------------------------------------
        send_sample(16'sd850, 1'b1, 1'b1);

        check_state(
            1'b1,
            1'b0,
            "LOW -> ARM"
        );


        // ------------------------------------------------------------
        // 3. LOW~HIGH 사이에서는 armed 유지
        // ------------------------------------------------------------
        send_sample(16'sd950, 1'b1, 1'b1);

        check_state(
            1'b1,
            1'b0,
            "BETWEEN THRESHOLDS"
        );


        // ------------------------------------------------------------
        // 4. armed 상태에서 HIGH 이상 -> trigger 1 pulse
        // ------------------------------------------------------------
        send_sample(16'sd1050, 1'b1, 1'b1);

        check_state(
            1'b0,
            1'b1,
            "HIGH CROSSING"
        );


        // ------------------------------------------------------------
        // 5. HIGH 근처 chatter -> 재trigger 금지
        // ------------------------------------------------------------
        send_sample(16'sd998, 1'b1, 1'b1);
        check_state(1'b0, 1'b0, "CHATTER 998");

        send_sample(16'sd1003, 1'b1, 1'b1);
        check_state(1'b0, 1'b0, "CHATTER 1003");

        send_sample(16'sd997, 1'b1, 1'b1);
        check_state(1'b0, 1'b0, "CHATTER 997");

        send_sample(16'sd1001, 1'b1, 1'b1);
        check_state(1'b0, 1'b0, "CHATTER 1001");


        // ------------------------------------------------------------
        // 6. LOW 이하로 내려가야 다시 arm
        // ------------------------------------------------------------
        send_sample(16'sd890, 1'b1, 1'b1);

        check_state(
            1'b1,
            1'b0,
            "REARM"
        );


        // ------------------------------------------------------------
        // 7. sample_fire=0이면 상태 변화 없어야 함
        // ------------------------------------------------------------
        send_sample(16'sd1100, 1'b0, 1'b1);

        check_state(
            1'b1,
            1'b0,
            "NO SAMPLE FIRE"
        );


        // 실제 sample이 들어온 순간 trigger
        send_sample(16'sd1100, 1'b1, 1'b1);

        check_state(
            1'b0,
            1'b1,
            "VALID HIGH AFTER STALL"
        );


        // ------------------------------------------------------------
        // 8. trigger_enable=0 테스트
        //
        // LOW -> arm
        // HIGH crossing은 소비하지만 trigger pulse는 억제
        // 이후 enable=1이 되어도 이미 HIGH에 있으므로
        // 갑자기 trigger되면 안 됨
        // ------------------------------------------------------------
        send_sample(16'sd850, 1'b1, 1'b0);

        check_state(
            1'b1,
            1'b0,
            "DISABLED LOW -> ARM"
        );

        send_sample(16'sd1050, 1'b1, 1'b0);

        check_state(
            1'b0,
            1'b0,
            "DISABLED HIGH CONSUMES CROSSING"
        );


        // HIGH 상태에서 enable만 켜져도 trigger 금지
        send_sample(16'sd1050, 1'b1, 1'b1);

        check_state(
            1'b0,
            1'b0,
            "ENABLE WHILE ALREADY HIGH"
        );


        // 다시 LOW -> rearm
        send_sample(16'sd850, 1'b1, 1'b1);

        check_state(
            1'b1,
            1'b0,
            "REARM AFTER DISABLED CROSSING"
        );


        // 정상 trigger
        send_sample(16'sd1050, 1'b1, 1'b1);

        check_state(
            1'b0,
            1'b1,
            "NORMAL TRIGGER AFTER REARM"
        );


        // trigger_pulse는 정확히 1 sample cycle
        send_sample(16'sd1050, 1'b1, 1'b1);

        check_state(
            1'b0,
            1'b0,
            "TRIGGER PULSE RETURNS LOW"
        );


        // ------------------------------------------------------------
        // RESULT
        // ------------------------------------------------------------
        if (error_count == 0) begin
            $display("");
            $display("========================================");
            $display("TRIGGER_DETECTOR_TEST_PASS");
            $display("ERROR_COUNT = %0d", error_count);
            $display("========================================");
            $display("");
        end
        else begin
            $display("");
            $display("========================================");
            $display("TRIGGER_DETECTOR_TEST_FAIL");
            $display("ERROR_COUNT = %0d", error_count);
            $display("========================================");
            $display("");
        end

        $finish;
    end

endmodule