//=====================================================================
// grover_predicate.v -- 술어 4종 판정 (소유자 B)
//
// 계약 4.1. 순수 조합논리이고 레지스터가 없습니다. 레인마다 한 벌씩,
// 그리고 grover_verify 안에 한 벌 더 인스턴스화됩니다 -- 오라클과 검증이
// 완전히 같은 식을 쓰되 적용 범위만 N칸 대 1칸으로 다릅니다.
//
// 비교기 IP 를 인스턴스화하지 않습니다. 17비트로 부호확장한 감산기 하나의
// 최상위 비트가 곧 답입니다. 부호확장을 빠뜨리면 value=-32768, thr_a=1 같은
// 자리에서 자릿수가 넘쳐 조용히 반대 답이 나옵니다.
//
// 감산기는 레인당 2개입니다.
//   sub1 : LT 는 (value - thr_a), GT 와 RANGE 하한은 피연산자를 바꿔 (thr_a - value)
//   sub2 : RANGE 상한 (value - thr_b)
//=====================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_predicate (
    input  wire [1:0]                  mode,      // 계약 5절 인코딩
    input  wire signed [`GP_W-1:0]     value,     // data_mem 한 칸
    input  wire signed [`GP_W-1:0]     thr_a,
    input  wire signed [`GP_W-1:0]     thr_b,
    input  wire                        found,     // 1 = 이미 찾아 둔 칸 (열거 모드)
    output wire                        hit
);
    localparam W = `GP_W;

    // 17비트 부호확장. 16비트 두 값의 차는 17비트로 언제나 정확히 표현됩니다.
    wire [W:0] v_ext  = {value[W-1], value};
    wire [W:0] ta_ext = {thr_a[W-1], thr_a};
    wire [W:0] tb_ext = {thr_b[W-1], thr_b};

    // GT 와 RANGE 하한은 둘 다 "thr_a < value" 를 묻는 것이라 피연산자만 뒤집습니다.
    wire       swap = (mode == `GP_MODE_GT) || (mode == `GP_MODE_RANGE);
    wire [W:0] op0  = swap ? ta_ext : v_ext;
    wire [W:0] op1  = swap ? v_ext  : ta_ext;

    wire [W:0] sub1 = op0 - op1;      // MSB=1 이면 op0 < op1
    wire [W:0] sub2 = v_ext - tb_ext; // MSB=1 이면 value < thr_b

    wire lt1 = sub1[W];               // LT: value<thr_a / GT,RANGE: thr_a<value
    wire lt2 = sub2[W];
    wire eq  = ~|(value ^ thr_a);

    reg  pred;
    always @* begin
        case (mode)
            `GP_MODE_LT   : pred = lt1;
            `GP_MODE_GT   : pred = lt1;
            `GP_MODE_EQ   : pred = eq;
            default       : pred = lt1 & lt2;   // GP_MODE_RANGE
        endcase
    end

    assign hit = pred & ~found;
endmodule
