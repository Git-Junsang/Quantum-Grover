//=====================================================================
// tb_two_mean_calc.v -- 배럴 시프터 + round-half-to-even (소유자 C)
//
// 구현식을 그대로 베껴 비교하면 아무것도 검증하지 못하므로, 반올림의
// 정의 자체를 확인합니다.
//   q = two_mean 이라 할 때  |total - q*2^K| <= 2^(K-1) 이고,
//   등호가 성립하는 정확한 절반의 경우 q 는 짝수여야 합니다.
// 이 두 줄이 round-half-to-even 의 정의이고 구현과 독립입니다.
//
// tie 케이스를 1000개 이상 넣습니다 -- 반올림이 갈라지는 자리는 여기
// 한 곳뿐이라 여기서 어긋나면 골든 모델과 영원히 맞지 않습니다.
//=====================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module tb_two_mean_calc;
    localparam ACCW = `GP_ACCW;

    reg  signed [ACCW-1:0] total;
    reg  [4:0]             n_qubits;
    wire signed [`GP_TMW-1:0] two_mean;

    integer errors = 0;
    integer i, ties;

    grover_two_mean_calc dut (
        .total(total), .n_qubits(n_qubits), .two_mean(two_mean)
    );

    task check;
        reg signed [63:0] t, q, prod, diff, half;
        reg [5:0] K;
        begin
            #1;
            K    = n_qubits - 1;
            t    = total;
            q    = two_mean;
            prod = q <<< K;
            diff = t - prod;
            if (diff < 0) diff = -diff;
            half = (K == 0) ? 0 : (64'sd1 <<< (K - 1));

            if (diff > half) begin
                errors = errors + 1;
                $display("FAIL(range) total=%0d n=%0d two_mean=%0d diff=%0d half=%0d",
                         t, n_qubits, q, diff, half);
            end else if ((K != 0) && (diff == half) && (q[0] !== 1'b0)) begin
                errors = errors + 1;
                ties   = ties + 1;
                $display("FAIL(tie->odd) total=%0d n=%0d two_mean=%0d", t, n_qubits, q);
            end
        end
    endtask

    integer m;
    reg signed [ACCW-1:0] tie_val;
    reg signed [63:0] rv, lim;

    initial begin
        ties = 0;

        // 작은 값과 부호 경계
        for (n_qubits = 5'd8; n_qubits <= 5'd15; n_qubits = n_qubits + 1) begin
            for (i = -40; i <= 40; i = i + 1) begin
                total = i;
                check;
            end
        end

        // tie 케이스 -- total = (2m+1) * 2^(K-1) 이면 정확히 절반입니다
        for (n_qubits = 5'd8; n_qubits <= 5'd15; n_qubits = n_qubits + 1) begin
            for (m = -70; m <= 70; m = m + 1) begin
                tie_val = ((2*m + 1) <<< (n_qubits - 2));
                total   = tie_val;
                check;
            end
        end

        // 실제로 나올 법한 크기 -- n=15 에서 진폭 362 x 32768 근방
        n_qubits = 5'd15;
        for (i = 0; i < 4000; i = i + 1) begin
            rv    = {$random, $random};
            total = rv % 64'sd12000000;
            check;
        end

        // 무작위. 단 total 은 물리적으로 도달 가능한 범위 안에서만 뽑습니다.
        // 진폭의 절대값이 AMP_MAX=131071 을 넘지 못하므로 |total| < 131071*2^n
        // 이고, 그래야 2*mean 이 TMW=20비트 안에 듭니다. 이 범위를 넘겨서
        // 넣으면 검증되는 것은 반올림이 아니라 잘림입니다.
        for (i = 0; i < 20000; i = i + 1) begin
            n_qubits = 5'd8 + ($random & 5'd7);
            lim      = 64'sd262142 <<< (n_qubits - 5'd1);
            rv       = {$random, $random};
            total    = rv % lim;
            check;
        end

        if (errors == 0) $display("tb_two_mean_calc: PASS (tie 케이스 %0d 개 포함)", 8*141);
        else begin $display("tb_two_mean_calc: FAIL (%0d errors)", errors); $fatal; end
        $finish;
    end
endmodule
