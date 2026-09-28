`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/21 12:28:26
// Design Name: 
// Module Name: async_fifo_gray
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


module async_fifo_gray #(
    parameter int DATA_WIDTH = 16,
    parameter int ADDR_WIDTH = 4
)(
    // Write / Acquisition domain
    input  logic                  wr_clk,
    input  logic                  wr_rst,

    input  logic [DATA_WIDTH-1:0] s_data,
    input  logic                  s_valid,
    output logic                  s_ready,

    // Read / Processing domain
    input  logic                  rd_clk,
    input  logic                  rd_rst,

    output logic [DATA_WIDTH-1:0] m_data,
    output logic                  m_valid,
    input  logic                  m_ready
);

    localparam int DEPTH     = (1 << ADDR_WIDTH);
    localparam int PTR_WIDTH = ADDR_WIDTH + 1;


    // ============================================================
    // Memory
    // ============================================================

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];


    // ============================================================
    // Write-domain pointers
    // ============================================================

    logic [PTR_WIDTH-1:0] wr_bin;
    logic [PTR_WIDTH-1:0] wr_bin_next;

    logic [PTR_WIDTH-1:0] wr_gray;
    logic [PTR_WIDTH-1:0] wr_gray_next;


    // ============================================================
    // Read-domain pointers
    // ============================================================

    logic [PTR_WIDTH-1:0] rd_bin;
    logic [PTR_WIDTH-1:0] rd_bin_next;

    logic [PTR_WIDTH-1:0] rd_gray;
    logic [PTR_WIDTH-1:0] rd_gray_next;


    // ============================================================
    // Cross-domain synchronized Gray pointers
    // ============================================================

    (* ASYNC_REG = "TRUE" *)
    logic [PTR_WIDTH-1:0] rd_gray_sync1;
    (* ASYNC_REG = "TRUE" *)
    logic [PTR_WIDTH-1:0] rd_gray_sync2;

    (* ASYNC_REG = "TRUE" *)
    logic [PTR_WIDTH-1:0] wr_gray_sync1;
    (* ASYNC_REG = "TRUE" *)
    logic [PTR_WIDTH-1:0] wr_gray_sync2;


    // ============================================================
    // Status
    // ============================================================

    logic fifo_full;
    logic fifo_full_next;

    logic fifo_empty;
    logic fifo_empty_next;

    logic wr_fire;
    logic rd_fire;


    // Actual Ready / Valid transfers
    assign wr_fire = s_valid && s_ready;
    assign rd_fire = m_valid && m_ready;

    assign s_ready = !fifo_full;
    assign m_valid = !fifo_empty;


    // ============================================================
    // Write pointer next-state
    // ============================================================

    always_comb begin
        wr_bin_next  = wr_bin + wr_fire;
        wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;
    end


    // ============================================================
    // Read pointer next-state
    // ============================================================

    always_comb begin
        rd_bin_next  = rd_bin + rd_fire;
        rd_gray_next = (rd_bin_next >> 1) ^ rd_bin_next;
    end


    // ============================================================
    // FULL detection
    //
    // For a power-of-two async FIFO, FULL occurs when the next
    // write pointer reaches the read pointer one entire FIFO
    // revolution ahead.
    //
    // In Gray code this is detected by inverting the top 2 bits.
    // ============================================================

    always_comb begin
        fifo_full_next =
            (wr_gray_next ==
             {
                 ~rd_gray_sync2[PTR_WIDTH-1:PTR_WIDTH-2],
                  rd_gray_sync2[PTR_WIDTH-3:0]
             });
    end


    // ============================================================
    // EMPTY detection
    // ============================================================

    always_comb begin
        fifo_empty_next = (rd_gray_next == wr_gray_sync2);
    end


    // ============================================================
    // Write-domain state / RAM write
    // ============================================================

    always_ff @(posedge wr_clk) begin
        if (wr_rst) begin
            wr_bin    <= '0;
            wr_gray   <= '0;
            fifo_full <= 1'b0;
        end
        else begin
            wr_bin    <= wr_bin_next;
            wr_gray   <= wr_gray_next;
            fifo_full <= fifo_full_next;

            if (wr_fire) begin
                mem[wr_bin[ADDR_WIDTH-1:0]] <= s_data;
            end
        end
    end


    // ============================================================
    // Read-domain state
    // ============================================================

    always_ff @(posedge rd_clk) begin
        if (rd_rst) begin
            rd_bin     <= '0;
            rd_gray    <= '0;
            fifo_empty <= 1'b1;
        end
        else begin
            rd_bin     <= rd_bin_next;
            rd_gray    <= rd_gray_next;
            fifo_empty <= fifo_empty_next;
        end
    end


    // First-word fall-through read
    assign m_data = mem[rd_bin[ADDR_WIDTH-1:0]];


    // ============================================================
    // Read pointer -> Write domain synchronizer
    // ============================================================

    always_ff @(posedge wr_clk) begin
        if (wr_rst) begin
            rd_gray_sync1 <= '0;
            rd_gray_sync2 <= '0;
        end
        else begin
            rd_gray_sync1 <= rd_gray;
            rd_gray_sync2 <= rd_gray_sync1;
        end
    end


    // ============================================================
    // Write pointer -> Read domain synchronizer
    // ============================================================

    always_ff @(posedge rd_clk) begin
        if (rd_rst) begin
            wr_gray_sync1 <= '0;
            wr_gray_sync2 <= '0;
        end
        else begin
            wr_gray_sync1 <= wr_gray;
            wr_gray_sync2 <= wr_gray_sync1;
        end
    end

endmodule