`timescale 1ns / 1ps

module tb_event_capture;

    localparam int DEPTH       = 2048;
    localparam int ADDR_WIDTH  = 11;
    localparam int PRE_SAMPLES = 1024;

    logic clk;
    logic rst;

    logic sample_fire;

    logic [31:0] sample_index;
    logic [7:0]  fault_flags;
    logic signed [15:0] raw_sample;
    logic signed [15:0] filtered_sample;

    logic trigger_pulse;

    logic trigger_enable;
    logic event_done;

    logic [ADDR_WIDTH-1:0] trigger_ptr;
    logic [ADDR_WIDTH-1:0] start_ptr;

    logic [ADDR_WIDTH-1:0] read_addr;
    logic [71:0] read_data;

    logic readout_done;

    integer error_count;
    integer i;


    event_capture #(
        .DEPTH(DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .PRE_SAMPLES(PRE_SAMPLES)
    ) dut (
        .clk             (clk),
        .rst             (rst),

        .sample_fire     (sample_fire),

        .sample_index    (sample_index),
        .fault_flags     (fault_flags),
        .raw_sample      (raw_sample),
        .filtered_sample (filtered_sample),

        .trigger_pulse   (trigger_pulse),

        .trigger_enable  (trigger_enable),
        .event_done      (event_done),

        .trigger_ptr     (trigger_ptr),
        .start_ptr       (start_ptr),

        .read_addr       (read_addr),
        .read_data       (read_data),

        .readout_done    (readout_done)
    );


    initial clk = 1'b0;
    always #5 clk = ~clk;


    // ============================================================
    // 한 개의 valid sample 입력
    // ============================================================
    task automatic send_sample(
        input logic [31:0] idx,
        input logic trig
    );
    begin

        @(negedge clk);

        sample_index    = idx;
        fault_flags     = idx[7:0];
        raw_sample      = $signed(idx[15:0]);
        filtered_sample = $signed(idx[15:0]) + 16'sd100;

        sample_fire   = 1'b1;
        trigger_pulse = trig;

        @(posedge clk);
        #1;

        @(negedge clk);

        sample_fire   = 1'b0;
        trigger_pulse = 1'b0;

    end
    endtask


    // ============================================================
    // sample_fire=0인 idle cycle
    // ============================================================
    task automatic idle_cycle;
    begin

        @(negedge clk);
        sample_fire = 1'b0;

        @(posedge clk);
        #1;

    end
    endtask


    // ============================================================
    // 기대하는 72-bit entry 생성
    // ============================================================
    function automatic logic [71:0] make_entry(
        input logic [31:0] idx
    );

        logic signed [15:0] raw_v;
        logic signed [15:0] filt_v;

        begin

            raw_v  = $signed(idx[15:0]);
            filt_v = $signed(idx[15:0]) + 16'sd100;

            make_entry = {
                idx,
                idx[7:0],
                raw_v,
                filt_v
            };

        end
    endfunction


    // ============================================================
    // Event Buffer read + compare
    // ============================================================
    task automatic read_and_check(
        input integer offset,
        input logic [31:0] expected_index
    );

        logic [ADDR_WIDTH-1:0] addr;
        logic [71:0] expected;

        begin

            // modulo 2048
            addr = start_ptr + offset;

            expected = make_entry(expected_index);

            @(negedge clk);
            read_addr = addr;

            // synchronous read
            @(posedge clk);
            #1;

            if (read_data !== expected) begin

                $error(
                    "READ ERROR offset=%0d addr=%0d expected_index=%0d",
                    offset,
                    addr,
                    expected_index
                );

                $display("READ     = %h", read_data);
                $display("EXPECTED = %h", expected);

                error_count = error_count + 1;

            end

        end
    endtask


    initial begin

        error_count = 0;

        rst             = 1'b1;
        sample_fire     = 1'b0;

        sample_index    = '0;
        fault_flags     = '0;
        raw_sample      = '0;
        filtered_sample = '0;

        trigger_pulse   = 1'b0;

        read_addr       = '0;
        readout_done    = 1'b0;


        // ========================================================
        // RESET
        // ========================================================

        repeat (3) @(posedge clk);

        @(negedge clk);
        rst = 1'b0;

        @(posedge clk);
        #1;


        // ========================================================
        // TEST 1
        // PRE history 확보
        //
        // sample 500에서 trigger를 일부러 줌
        // 아직 PRE가 없으므로 event가 생기면 안 됨
        // ========================================================

        for (i = 0; i < 1024; i = i + 1) begin

            send_sample(
                i,
                (i == 500)
            );

            if ((i < 1023) &&
                (trigger_enable !== 1'b0)) begin

                $error(
                    "trigger_enable too early at sample %0d",
                    i
                );

                error_count = error_count + 1;

            end

        end


        if (trigger_enable !== 1'b1) begin

            $error("PRE history did not enable trigger");
            error_count = error_count + 1;

        end


        if (event_done !== 1'b0) begin

            $error("Early trigger incorrectly created an event");
            error_count = error_count + 1;

        end


        // ========================================================
        // 계속 circular recording
        //
        // 총 2300 samples history 생성
        // ========================================================

        for (i = 1024; i < 2300; i = i + 1) begin
            send_sample(i, 1'b0);
        end


        // ========================================================
        // TEST 2
        // Trigger 발생
        //
        // 2300 mod 2048 = 252
        //
        // trigger_ptr = 252
        //
        // start_ptr =
        // 252 - 1024 mod 2048
        // = 1276
        // ========================================================

        send_sample(32'd2300, 1'b1);


        if (trigger_ptr !== 11'd252) begin

            $error(
                "TRIGGER_PTR ERROR actual=%0d expected=252",
                trigger_ptr
            );

            error_count = error_count + 1;

        end


        if (start_ptr !== 11'd1276) begin

            $error(
                "START_PTR ERROR actual=%0d expected=1276",
                start_ptr
            );

            error_count = error_count + 1;

        end


        if (event_done !== 1'b0) begin

            $error("event_done asserted on trigger sample");
            error_count = error_count + 1;

        end


        // ========================================================
        // TEST 3
        // POST = 정확히 1023 accepted samples
        //
        // 2301 ~ 3322 = 1022개
        // ========================================================

        for (i = 2301; i <= 2800; i = i + 1) begin
            send_sample(i, 1'b0);
        end


        // idle clocks는 POST count가 증가하면 안 됨
        repeat (7) begin
            idle_cycle();
        end


        for (i = 2801; i <= 3322; i = i + 1) begin
            send_sample(i, 1'b0);
        end


        if (event_done !== 1'b0) begin

            $error(
                "event_done asserted before 1023 post samples"
            );

            error_count = error_count + 1;

        end


        // 1023번째 POST sample
        send_sample(32'd3323, 1'b0);


        if (event_done !== 1'b1) begin

            $error(
                "event_done did not assert after 1023 post samples"
            );

            error_count = error_count + 1;

        end


        // ========================================================
        // TEST 4
        // 최종 2048 sample을 시간순으로 읽기
        //
        // 1276 ... 3323
        //
        // offset 1024 = trigger sample 2300
        // ========================================================

        for (i = 0; i < DEPTH; i = i + 1) begin

            read_and_check(
                i,
                32'd1276 + i
            );

        end


        // ========================================================
        // TEST 5
        // EVENT_DONE 상태에서는 memory freeze
        // ========================================================

        for (i = 4000; i < 4010; i = i + 1) begin

            send_sample(
                i,
                1'b1
            );

        end


        // 대표 위치 다시 확인
        read_and_check(0,    32'd1276);
        read_and_check(1024, 32'd2300);
        read_and_check(2047, 32'd3323);


        // ========================================================
        // TEST 6
        // readout 완료 → 다시 capture 준비
        // ========================================================

        @(negedge clk);
        readout_done = 1'b1;

        @(posedge clk);
        #1;

        @(negedge clk);
        readout_done = 1'b0;


        if (event_done !== 1'b0) begin

            $error(
                "readout_done did not clear event_done"
            );

            error_count = error_count + 1;

        end


        if (trigger_enable !== 1'b0) begin

            $error(
                "trigger enabled without fresh PRE history"
            );

            error_count = error_count + 1;

        end


        // ========================================================
        // RESULT
        // ========================================================

        if (error_count == 0) begin

            $display("");
            $display("======================================");
            $display("EVENT_CAPTURE_TEST_PASS");
            $display("ERROR_COUNT = %0d", error_count);
            $display("======================================");
            $display("");

        end
        else begin

            $display("");
            $display("======================================");
            $display("EVENT_CAPTURE_TEST_FAIL");
            $display("ERROR_COUNT = %0d", error_count);
            $display("======================================");
            $display("");

        end


        $finish;

    end

endmodule