`timescale 1ns / 1ps

module tb_event_capture;

    localparam int DEPTH = 2048;
    localparam int ADDR_WIDTH = 11;
    localparam int PRE_SAMPLES = 1024;
    localparam int POST_SAMPLES = 1023;

    logic clk;
    logic rst;

    logic sample_fire;
    logic [31:0] sample_index;
    logic [7:0] fault_flags;
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

    int error_count;
    int i;

    event_capture #(
        .DEPTH(DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .PRE_SAMPLES(PRE_SAMPLES),
        .POST_SAMPLES(POST_SAMPLES)
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
    always #5 clk = ~clk; // 100 MHz

    function automatic logic [71:0] make_entry(input logic [31:0] idx);
        logic signed [15:0] raw_v;
        logic signed [15:0] filt_v;
        begin
            raw_v  = $signed(idx[15:0]);
            filt_v = $signed(idx[15:0]) + 16'sd100;
            make_entry = {idx, idx[7:0], raw_v, filt_v};
        end
    endfunction

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
            sample_fire     = 1'b1;
            trigger_pulse   = trig;

            @(posedge clk);
            #1;

            @(negedge clk);
            sample_fire   = 1'b0;
            trigger_pulse = 1'b0;
        end
    endtask

    task automatic idle_cycle(input logic trig);
        begin
            @(negedge clk);
            sample_fire   = 1'b0;
            trigger_pulse = trig;

            @(posedge clk);
            #1;

            @(negedge clk);
            trigger_pulse = 1'b0;
        end
    endtask

    task automatic check_bit(
        input logic actual,
        input logic expected,
        input string message
    );
        begin
            if (actual !== expected) begin
                $error("%s | actual=%0b expected=%0b", message, actual, expected);
                error_count++;
            end
        end
    endtask

    task automatic check_ptr(
        input logic [ADDR_WIDTH-1:0] actual,
        input logic [ADDR_WIDTH-1:0] expected,
        input string message
    );
        begin
            if (actual !== expected) begin
                $error("%s | actual=%0d expected=%0d", message, actual, expected);
                error_count++;
            end
        end
    endtask

    task automatic read_and_check(
        input int offset,
        input logic [31:0] expected_idx
    );
        logic [ADDR_WIDTH-1:0] addr;
        logic [71:0] expected_entry;
        begin
            addr = (start_ptr + offset) & 11'h7FF;
            expected_entry = make_entry(expected_idx);

            @(negedge clk);
            read_addr = addr;

            // BRAM-friendly synchronous read: data appears after next posedge.
            @(posedge clk);
            #1;

            if (read_data !== expected_entry) begin
                $error(
                    "READ MISMATCH offset=%0d addr=%0d expected_idx=%0d read_data=%h expected=%h",
                    offset,
                    addr,
                    expected_idx,
                    read_data,
                    expected_entry
                );
                error_count++;
            end
        end
    endtask

    initial begin
        error_count     = 0;
        rst             = 1'b1;
        sample_fire     = 1'b0;
        sample_index    = '0;
        fault_flags     = '0;
        raw_sample      = '0;
        filtered_sample = '0;
        trigger_pulse   = 1'b0;
        read_addr       = '0;
        readout_done    = 1'b0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        @(posedge clk);
        #1;

        check_bit(event_done, 1'b0, "RESET EVENT_DONE");
        check_bit(trigger_enable, 1'b0, "RESET TRIGGER_ENABLE");

        // A. Build history. A trigger before 1024 accepted samples is ignored.
        for (i = 0; i < 2300; i++) begin
            send_sample(i, (i == 500));

            if (event_done !== 1'b0) begin
                $error("EVENT_DONE asserted during pre-trigger history at sample %0d", i);
                error_count++;
            end

            if (i < 1023 && trigger_enable !== 1'b0) begin
                $error("TRIGGER_ENABLE asserted too early at sample %0d", i);
                error_count++;
            end
        end

        check_bit(trigger_enable, 1'b1, "TRIGGER ENABLE AFTER HISTORY");
        check_bit(event_done, 1'b0, "NO EVENT BEFORE REAL TRIGGER");

        // B. Trigger: 2300 mod 2048 = 252; start = 252-1024 mod 2048 = 1276.
        send_sample(32'd2300, 1'b1);

        check_ptr(trigger_ptr, 11'd252, "TRIGGER PTR");
        check_ptr(start_ptr, 11'd1276, "START PTR");
        check_bit(trigger_enable, 1'b0, "TRIGGER DISABLED DURING POST");
        check_bit(event_done, 1'b0, "EVENT NOT DONE ON TRIGGER SAMPLE");

        // C. Store 1022 post samples, with idle clocks that must not count.
        for (i = 2301; i <= 2800; i++) begin
            send_sample(i, 1'b0);
        end

        repeat (7) begin
            idle_cycle(1'b1);
            check_bit(event_done, 1'b0, "IDLE CLOCK MUST NOT ADVANCE POST COUNT");
        end

        for (i = 2801; i <= 3322; i++) begin
            send_sample(i, 1'b0);
        end

        check_bit(event_done, 1'b0, "NOT DONE AFTER 1022 POST SAMPLES");

        // 1023rd post sample.
        send_sample(32'd3323, 1'b0);
        check_bit(event_done, 1'b1, "DONE AFTER EXACTLY 1023 POST SAMPLES");
        check_bit(trigger_enable, 1'b0, "TRIGGER DISABLED WHEN EVENT FROZEN");

        // D. Event readout. Expected chronological indexes: 1276..3323.
        for (i = 0; i < DEPTH; i++) begin
            read_and_check(i, 32'd1276 + i);
        end

        // Trigger must sit at event offset 1024.
        read_and_check(1024, 32'd2300);

        // E. Frozen buffer must not change while upstream samples keep arriving.
        for (i = 4000; i < 4010; i++) begin
            send_sample(i, 1'b1);
            check_bit(event_done, 1'b1, "EVENT_DONE MUST STAY HIGH WHILE FROZEN");
        end

        read_and_check(0, 32'd1276);
        read_and_check(1024, 32'd2300);
        read_and_check(2047, 32'd3323);

        // F. Readout completion rearms capture but requires fresh PRE history.
        @(negedge clk);
        readout_done = 1'b1;
        @(posedge clk);
        #1;
        @(negedge clk);
        readout_done = 1'b0;

        check_bit(event_done, 1'b0, "READOUT_DONE CLEARS EVENT_DONE");
        check_bit(trigger_enable, 1'b0, "REARM REQUIRES FRESH PRE HISTORY");

        if (error_count == 0) begin
            $display("");
            $display("========================================");
            $display("EVENT_CAPTURE_TEST_PASS");
            $display("ERROR_COUNT = %0d", error_count);
            $display("========================================");
            $display("");
        end
        else begin
            $display("");
            $display("========================================");
            $display("EVENT_CAPTURE_TEST_FAIL");
            $display("ERROR_COUNT = %0d", error_count);
            $display("========================================");
            $display("");
        end

        $finish;
    end

endmodule
