`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/21 14:18:59
// Design Name: 
// Module Name: tb_daq_cdc_top
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

module tb_daq_cdc_top;

    localparam int DATA_WIDTH = 16;
    localparam int ADDR_WIDTH = 4;

    logic acq_clk;
    logic proc_clk;

    logic acq_rst;
    logic proc_rst;

    logic                  out_ready;
    logic [DATA_WIDTH-1:0] out_data;
    logic                  out_valid;

    logic [DATA_WIDTH-1:0] expected_data;

    int recv_count;
    int error_count;

    logic full_seen;
    logic backpressure_seen;


    // ============================================================
    // DUT
    // ============================================================

    daq_cdc_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .acq_clk   (acq_clk),
        .acq_rst   (acq_rst),

        .proc_clk  (proc_clk),
        .proc_rst  (proc_rst),

        .out_ready (out_ready),
        .out_data  (out_data),
        .out_valid (out_valid)
    );


    // ============================================================
    // Acquisition clock
    // ~83.33 MHz
    // ============================================================

    initial begin
        acq_clk = 1'b0;
        forever #6 acq_clk = ~acq_clk;
    end


    // ============================================================
    // Processing clock
    // 100 MHz
    // ============================================================

    initial begin
        proc_clk = 1'b0;
        forever #5 proc_clk = ~proc_clk;
    end


    // ============================================================
    // Main stimulus
    // ============================================================

    initial begin

        acq_rst   = 1'b1;
        proc_rst  = 1'b1;
        out_ready = 1'b0;

        expected_data    = '0;
        recv_count       = 0;
        error_count      = 0;
        full_seen        = 1'b0;
        backpressure_seen = 1'b0;


        // --------------------------------------------------------
        // Reset
        // --------------------------------------------------------

        repeat (5) @(posedge acq_clk);
        @(negedge acq_clk);
        acq_rst = 1'b0;

        repeat (5) @(posedge proc_clk);
        @(negedge proc_clk);
        proc_rst = 1'b0;


        // --------------------------------------------------------
        // Phase 1
        //
        // Processing side를 막아서 FIFO를 일부러 FULL로 만든다.
        // --------------------------------------------------------

        repeat (40) begin
            @(negedge proc_clk);
            out_ready = 1'b0;
        end


        // --------------------------------------------------------
        // Phase 2
        //
        // 정상적으로 데이터 처리
        // --------------------------------------------------------

        repeat (100) begin
            @(negedge proc_clk);
            out_ready = 1'b1;
        end


        // --------------------------------------------------------
        // Phase 3
        //
        // Random backpressure
        // --------------------------------------------------------

        repeat (600) begin
            @(negedge proc_clk);

            out_ready = $urandom_range(0, 1);

            if (!out_ready)
                backpressure_seen = 1'b1;
        end


        // --------------------------------------------------------
        // Phase 4
        //
        // 마지막에는 계속 받아서 충분한 sample을 검증
        // --------------------------------------------------------

        out_ready = 1'b1;

        wait (recv_count >= 300);

        repeat (10) @(posedge proc_clk);


        // --------------------------------------------------------
        // Final checks
        // --------------------------------------------------------

        if (!full_seen) begin
            $error("FIFO FULL was never observed");
            error_count++;
        end

        if (!backpressure_seen) begin
            $error("Backpressure was never exercised");
            error_count++;
        end


        if (error_count == 0) begin
            $display("========================================");
            $display("DAQ_CDC_INTEGRATION_TEST_PASS");
            $display("RECEIVED_SAMPLES = %0d", recv_count);
            $display("FIFO_FULL_SEEN   = %0d", full_seen);
            $display("========================================");
        end
        else begin
            $display("========================================");
            $display("DAQ_CDC_INTEGRATION_TEST_FAIL");
            $display("ERROR_COUNT = %0d", error_count);
            $display("========================================");
        end

        $finish;
    end


    // ============================================================
    // Output scoreboard
    //
    // Sensor Emulator는
    //
    // 0, 1, 2, 3, 4 ...
    //
    // 순서로 데이터를 생성하므로 FIFO 출력도 반드시
    // 같은 순서여야 한다.
    // ============================================================

    always @(posedge proc_clk) begin

        if (proc_rst) begin
            expected_data <= '0;
        end
        else begin

            if (out_valid && out_ready) begin

                if (out_data !== expected_data) begin

                    $error(
                        "DATA ERROR at sample %0d : expected=%0d actual=%0d",
                        recv_count,
                        expected_data,
                        out_data
                    );

                    error_count++;
                end

                expected_data <= expected_data + 1'b1;
                recv_count++;

            end
        end

    end


    // ============================================================
    // Observe FIFO full
    // ============================================================

    always @(posedge acq_clk) begin

        if (!acq_rst) begin

            if (dut.u_async_fifo.fifo_full)
                full_seen <= 1'b1;

        end

    end


    // ============================================================
    // Assertion 1
    //
    // FIFO가 Sensor를 막고 있는 동안
    // Sensor data는 변경되면 안 된다.
    // ============================================================

    property p_sensor_stable_when_stalled;

        @(posedge acq_clk)
        disable iff (acq_rst)

        dut.u_sensor_emulator.sample_valid &&
        !dut.u_sensor_emulator.sample_ready

        |=> $stable(dut.u_sensor_emulator.sample_data);

    endproperty


    assert property (p_sensor_stable_when_stalled)
    else begin

        $error("Sensor data changed during backpressure");
        error_count++;

    end


    // ============================================================
    // Assertion 2
    //
    // Output valid인데 downstream ready가 0이면
    // output data도 유지되어야 한다.
    // ============================================================

    property p_output_stable_when_stalled;

        @(posedge proc_clk)
        disable iff (proc_rst)

        out_valid && !out_ready

        |=> $stable(out_data);

    endproperty


    assert property (p_output_stable_when_stalled)
    else begin

        $error("Output data changed during backpressure");
        error_count++;

    end


endmodule