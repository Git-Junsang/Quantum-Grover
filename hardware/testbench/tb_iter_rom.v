//=====================================================================
// tb_iter_rom.v -- BBHT 의 m 수열 (소유자 D)
//
// 확인하는 것 셋입니다. 수열이 단조 증가하는가, m_{k+1} 이 1.2배 규칙과
// 맞는가, sqrt(N) 상한에서 멈추는가. 규칙 자체가 아직 잠정이므로(16.9절
// 4번) 이 테스트도 확정되면 같이 고쳐야 합니다.
//=====================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module tb_iter_rom;
    reg  [4:0]  idx;
    reg  [4:0]  n_qubits;
    wire [15:0] m;
    wire        last;

    integer errors = 0;
    integer k;
    reg [15:0] prev, expect_raw;
    reg [15:0] cap;

    grover_iter_rom dut (.idx(idx), .n_qubits(n_qubits), .m(m), .last(last));

    initial begin
        // 상한이 걸리지 않는 큰 n 에서 수열 규칙을 확인합니다
        n_qubits = 5'd15;
        idx = 0; #1; prev = m;
        if (prev !== 16'd1) begin
            errors = errors + 1; $display("FAIL m_0=%0d (1 이어야 함)", prev);
        end
        for (k = 1; k < 30; k = k + 1) begin
            idx = k[4:0]; #1;
            cap = 16'd181;                      // floor(sqrt(2^15))
            expect_raw = (prev + 1 > (prev*6)/5) ? prev + 1 : (prev*6)/5;
            if (expect_raw > cap) expect_raw = cap;
            if (m !== expect_raw) begin
                errors = errors + 1;
                $display("FAIL idx=%0d m=%0d expect=%0d", k, m, expect_raw);
            end
            if (m < prev) begin
                errors = errors + 1;
                $display("FAIL 단조성 idx=%0d m=%0d prev=%0d", k, m, prev);
            end
            prev = (m > cap) ? cap : m;
        end

        // 상한이 n 에 따라 제대로 걸리는가
        for (n_qubits = 5'd8; n_qubits <= 5'd15; n_qubits = n_qubits + 1) begin
            idx = 5'd29; #1;
            case (n_qubits)
                5'd8 : cap = 16'd16;   5'd9 : cap = 16'd22;
                5'd10: cap = 16'd32;   5'd11: cap = 16'd45;
                5'd12: cap = 16'd64;   5'd13: cap = 16'd90;
                5'd14: cap = 16'd128;  default: cap = 16'd181;
            endcase
            if (m !== cap) begin
                errors = errors + 1;
                $display("FAIL 상한 n=%0d m=%0d cap=%0d", n_qubits, m, cap);
            end
        end

        if (errors == 0) $display("tb_iter_rom: PASS");
        else begin $display("tb_iter_rom: FAIL (%0d errors)", errors); $fatal; end
        $finish;
    end
endmodule
