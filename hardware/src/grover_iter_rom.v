//=====================================================================
// grover_iter_rom.v -- BBHT 의 m 수열 30항 (소유자 D)
//
// 계약 4절 표 20번. 조합 ROM 입니다.
//   m_0 = 1,  m_{k+1} = max(m_k + 1, floor(1.2 * m_k)),  상한 floor(sqrt(N))
//
// !! 잠정 구현입니다 !!
// 해설서 16.9절 4번 "m <- min(1.2m, sqrt(N)) 의 하드웨어 산술" 이 미정입니다.
// 여기서는 곱셈기를 쓰지 않으려고 수열을 미리 펼쳐 넣고 상한만 n 에 따라
// 골랐습니다. 반올림 규칙(floor 인가 round 인가)이 확정되면 이 표와
// software/golden/bbht.py 의 m_rom() 을 같이 고칩니다.
//
// m 이 1 에서 느리게 자라기 때문에 초반 샷은 거의 실패합니다. 그 실패한
// 샷들이 남긴 진폭을 버리지 않는 것이 재개 캐시입니다.
//=====================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_iter_rom (
    input  wire [4:0]  idx,        // 0 .. 29. 넘으면 마지막 항에서 멈춥니다
    input  wire [4:0]  n_qubits,
    output wire [15:0] m,
    output wire        last        // 1 이면 더 키울 항이 없음
);
    reg [15:0] m_raw;
    always @* begin
        case (idx)
            5'd0 : m_raw = 16'd1;    5'd1 : m_raw = 16'd2;
            5'd2 : m_raw = 16'd3;    5'd3 : m_raw = 16'd4;
            5'd4 : m_raw = 16'd5;    5'd5 : m_raw = 16'd6;
            5'd6 : m_raw = 16'd7;    5'd7 : m_raw = 16'd8;
            5'd8 : m_raw = 16'd9;    5'd9 : m_raw = 16'd10;
            5'd10: m_raw = 16'd12;   5'd11: m_raw = 16'd14;
            5'd12: m_raw = 16'd16;   5'd13: m_raw = 16'd19;
            5'd14: m_raw = 16'd22;   5'd15: m_raw = 16'd26;
            5'd16: m_raw = 16'd31;   5'd17: m_raw = 16'd37;
            5'd18: m_raw = 16'd44;   5'd19: m_raw = 16'd52;
            5'd20: m_raw = 16'd62;   5'd21: m_raw = 16'd74;
            5'd22: m_raw = 16'd88;   5'd23: m_raw = 16'd105;
            5'd24: m_raw = 16'd126;  5'd25: m_raw = 16'd151;
            5'd26: m_raw = 16'd181;  5'd27: m_raw = 16'd217;
            5'd28: m_raw = 16'd260;  default: m_raw = 16'd312;
        endcase
    end

    // 상한 floor(sqrt(2^n)) = floor(2^(n/2)). 곱셈 없이 표로 고릅니다.
    reg [15:0] cap;
    always @* begin
        case (n_qubits)
            5'd8 : cap = 16'd16;    5'd9 : cap = 16'd22;
            5'd10: cap = 16'd32;    5'd11: cap = 16'd45;
            5'd12: cap = 16'd64;    5'd13: cap = 16'd90;
            5'd14: cap = 16'd128;   5'd15: cap = 16'd181;
            default: cap = (n_qubits < 5'd8) ? (16'd1 << (n_qubits >> 1)) : 16'd181;
        endcase
    end

    assign m    = (m_raw > cap) ? cap : m_raw;
    assign last = (idx >= 5'd29) || (m_raw >= cap);
endmodule
