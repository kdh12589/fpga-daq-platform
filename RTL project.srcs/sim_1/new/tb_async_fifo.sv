`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/21 12:29:19
// Design Name: 
// Module Name: tb_async_fifo
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

module tb_async_fifo;

    localparam int DATA_WIDTH = 16;
    localparam int ADDR_WIDTH = 4;

    logic wr_clk;
    logic rd_clk;

    logic wr_rst;
    logic rd_rst;

    logic [DATA_WIDTH-1:0] s_data;
    logic                  s_valid;
    logic                  s_ready;

    logic [DATA_WIDTH-1:0] m_data;
    logic                  m_valid;
    logic                  m_ready;

    logic [DATA_WIDTH-1:0] expected_queue[$];

    int sent_count;
    int recv_count;
    int error_count;

    async_fifo_gray #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .wr_clk   (wr_clk),
        .wr_rst   (wr_rst),

        .s_data   (s_data),
        .s_valid  (s_valid),
        .s_ready  (s_ready),

        .rd_clk   (rd_clk),
        .rd_rst   (rd_rst),

        .m_data   (m_data),
        .m_valid  (m_valid),
        .m_ready  (m_ready)
    );

    // Write clock: ~83.3 MHz
    initial begin
        wr_clk = 1'b0;
        forever #6 wr_clk = ~wr_clk;
    end

    // Read clock: 100 MHz
    initial begin
        rd_clk = 1'b0;
        forever #5 rd_clk = ~rd_clk;
    end

    initial begin
        wr_rst = 1'b1;
        rd_rst = 1'b1;

        s_data  = '0;
        s_valid = 1'b0;
        m_ready = 1'b0;

        sent_count  = 0;
        recv_count  = 0;
        error_count = 0;

        repeat (5) @(posedge wr_clk);
        wr_rst = 1'b0;

        repeat (5) @(posedge rd_clk);
        rd_rst = 1'b0;

        // Start producer
        @(negedge wr_clk);
        s_valid = 1'b1;

        // Initially block reader to fill FIFO
        repeat (25) begin
            @(negedge rd_clk);
            m_ready = 1'b0;
        end

        // Allow reader
        repeat (50) begin
            @(negedge rd_clk);
            m_ready = 1'b1;
        end

        // Random backpressure
        repeat (200) begin
            @(negedge rd_clk);
            m_ready = $urandom_range(0, 1);
        end

        // Stop producer
        @(negedge wr_clk);
        s_valid = 1'b0;

        // Drain FIFO
        repeat (100) begin
            @(negedge rd_clk);
            m_ready = 1'b1;
        end

        repeat (10) @(posedge rd_clk);

        if (expected_queue.size() != 0) begin
            $error("QUEUE NOT EMPTY. Remaining=%0d",
                   expected_queue.size());
            error_count++;
        end

        if (sent_count != recv_count) begin
            $error(
                "COUNT MISMATCH sent=%0d recv=%0d",
                sent_count,
                recv_count
            );
            error_count++;
        end

        if (error_count == 0) begin
            $display("ASYNC_FIFO_TEST_PASS");
        end
        else begin
            $display("ASYNC_FIFO_TEST_FAIL errors=%0d",
                     error_count);
        end

        $finish;
    end

    // Producer
    always @(posedge wr_clk) begin
        if (wr_rst) begin
            s_data <= '0;
        end
        else begin
            if (s_valid && s_ready) begin
                expected_queue.push_back(s_data);

                s_data <= s_data + 1'b1;
                sent_count++;
            end
        end
    end

    // Consumer / Scoreboard
    always @(posedge rd_clk) begin
        logic [DATA_WIDTH-1:0] expected;

        if (!rd_rst) begin
            if (m_valid && m_ready) begin

                if (expected_queue.size() == 0) begin
                    $error("Unexpected output data=%0d", m_data);
                    error_count++;
                end
                else begin
                    expected = expected_queue.pop_front();

                    if (m_data !== expected) begin
                        $error(
                            "DATA MISMATCH expected=%0d actual=%0d",
                            expected,
                            m_data
                        );

                        error_count++;
                    end
                end

                recv_count++;
            end
        end
    end

endmodule