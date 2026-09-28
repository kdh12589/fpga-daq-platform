`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/22 11:39:59
// Design Name: 
// Module Name: fir8_fixed
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
module fir8_fixed #(
    parameter int DATA_WIDTH = 16,
    parameter int COEF_WIDTH = 16,
    parameter int FRAC_BITS  = 15
)(
    input  logic                         clk,
    input  logic                         rst,

    // Input Ready/Valid stream
    input  logic signed [DATA_WIDTH-1:0] in_data,
    input  logic                         in_valid,
    output logic                         in_ready,

    // Output Ready/Valid stream
    output logic signed [DATA_WIDTH-1:0] out_data,
    output logic                         out_valid,
    input  logic                         out_ready
);

    localparam int TAPS       = 8;
    localparam int PROD_WIDTH = DATA_WIDTH + COEF_WIDTH;

    // 8개의 product를 일반적으로 더할 수 있도록
    // log2(8)=3 guard bits 확보
    localparam int ACC_WIDTH  = PROD_WIDTH + $clog2(TAPS);


    // ============================================================
    // Previous 7 input samples
    //
    // delay_line[0] = x[n-1]
    // delay_line[1] = x[n-2]
    // ...
    // delay_line[6] = x[n-7]
    // ============================================================

    logic signed [DATA_WIDTH-1:0] delay_line [0:TAPS-2];


    // ============================================================
    // FIR coefficients
    //
    // Q1.15
    //
    // Real coefficient = stored integer / 32768
    // ============================================================

    function automatic logic signed [COEF_WIDTH-1:0]
        coeff(input integer index);

        begin
            case (index)

                0: coeff = -16'sd236;
                1: coeff =  16'sd0;
                2: coeff =  16'sd4426;
                3: coeff =  16'sd12194;
                4: coeff =  16'sd12194;
                5: coeff =  16'sd4426;
                6: coeff =  16'sd0;
                7: coeff = -16'sd236;

                default:
                    coeff = '0;

            endcase
        end

    endfunction


    // ============================================================
    // Internal signals
    // ============================================================

    logic signed [PROD_WIDTH-1:0] product [0:TAPS-1];

    logic signed [ACC_WIDTH-1:0] acc_comb;
    logic signed [ACC_WIDTH-1:0] rounded_scaled_comb;

    logic signed [DATA_WIDTH-1:0] filtered_comb;

    logic in_fire;

    integer i;


    // ============================================================
    // Ready/Valid control
    //
    // 새 입력을 받을 수 있는 조건:
    //
    // 1. output register가 비어 있거나
    // 2. 현재 output이 이번 cycle에 소비될 예정
    // ============================================================

    assign in_ready = (!out_valid) || out_ready;

    assign in_fire = in_valid && in_ready;


    // ============================================================
    // FIR multiply + accumulate
    //
    // y[n] =
    //
    // h0*x[n]
    // + h1*x[n-1]
    // + ...
    // + h7*x[n-7]
    // ============================================================

    always_comb begin

        // Current sample
        product[0] =
            $signed(in_data) *
            $signed(coeff(0));

        // Previous samples
        for (i = 1; i < TAPS; i = i + 1) begin

            product[i] =
                $signed(delay_line[i-1]) *
                $signed(coeff(i));

        end


        // Accumulator
        acc_comb = '0;

        for (i = 0; i < TAPS; i = i + 1) begin

            // Sign extension before accumulation
            acc_comb =
                acc_comb +
                {
                    {(ACC_WIDTH-PROD_WIDTH)
                        {product[i][PROD_WIDTH-1]}},
                    product[i]
                };

        end


        // ========================================================
        // Q1.15 scale restoration + symmetric rounding
        //
        // coefficient를 2^15배해서 계산했으므로
        // 마지막에 다시 2^15로 나눈다.
        //
        // 단순 truncation 대신 nearest rounding.
        // ========================================================

        if (acc_comb >= 0) begin

            rounded_scaled_comb =
                (acc_comb +
                 ({{(ACC_WIDTH-1){1'b0}}, 1'b1}
                    <<< (FRAC_BITS-1)))
                >>> FRAC_BITS;

        end
        else begin

            rounded_scaled_comb =
                -((
                    (-acc_comb) +
                    ({{(ACC_WIDTH-1){1'b0}}, 1'b1}
                        <<< (FRAC_BITS-1))
                  )
                  >>> FRAC_BITS);

        end


        // ========================================================
        // Saturation
        //
        // signed 16-bit:
        //
        // MAX = +32767
        // MIN = -32768
        // ========================================================

        if (
            rounded_scaled_comb >
            $signed(32767)
        ) begin

            filtered_comb = 16'sh7FFF;

        end
        else if (
            rounded_scaled_comb <
            $signed(-32768)
        ) begin

            filtered_comb = -16'sd32768;

        end
        else begin

            filtered_comb =
                rounded_scaled_comb[DATA_WIDTH-1:0];

        end

    end


    // ============================================================
    // Sequential state
    // ============================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            out_data  <= '0;
            out_valid <= 1'b0;

            for (i = 0; i < TAPS-1; i = i + 1) begin
                delay_line[i] <= '0;
            end

        end
        else begin

            // output이 막혀 있으면
            // in_ready=0이므로 모든 FIR 상태가 그대로 유지된다.
            if (in_ready) begin

                if (in_valid) begin

                    // ------------------------------------------------
                    // Shift previous samples
                    // ------------------------------------------------

                    for (i = TAPS-2; i > 0; i = i - 1) begin

                        delay_line[i] <=
                            delay_line[i-1];

                    end

                    delay_line[0] <= in_data;


                    // ------------------------------------------------
                    // Register filtered output
                    // ------------------------------------------------

                    out_data  <= filtered_comb;
                    out_valid <= 1'b1;

                end
                else begin

                    // 현재 output이 소비되었는데
                    // 새로운 input이 없으면 output register becomes empty
                    out_valid <= 1'b0;

                end

            end

        end

    end

endmodule