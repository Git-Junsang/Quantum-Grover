//=====================================================================
// tb_predicate.v -- 술어 4종 경계값 진리표 (소유자 B)
//
// 계약 5절이 네 술어를 전부 강부등호로 고정했으므로 경계에서 정확히
// 한 칸씩 어긋나는지 확인하는 것이 이 테스트의 전부입니다. 부호확장을
// 빠뜨리면 value=-32768, thr_a=1 에서 조용히 반대 답이 나오므로 그 자리를
// 따로 넣었습니다.
//=====================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module tb_predicate;
    reg  [1:0]         mode;
    reg  signed [15:0] value, thr_a, thr_b;
    reg                found;
    wire               hit;

    integer errors = 0;
    integer i;

    grover_predicate dut (
        .mode(mode), .value(value), .thr_a(thr_a), .thr_b(thr_b),
        .found(found), .hit(hit)
    );

    task check;
        reg exp;
        begin
            #1;
            case (mode)
                2'b00 : exp = (value <  thr_a);
                2'b01 : exp = (value >  thr_a);
                2'b10 : exp = (value == thr_a);
                default: exp = (thr_a < value) && (value < thr_b);
            endcase
            exp = exp & ~found;
            if (hit !== exp) begin
                errors = errors + 1;
                $display("FAIL mode=%0d value=%0d thr_a=%0d thr_b=%0d found=%0b : hit=%0b exp=%0b",
                         mode, value, thr_a, thr_b, found, hit, exp);
            end
        end
    endtask

    // 경계 근방을 훑습니다
    task sweep_around(input signed [15:0] a, input signed [15:0] b);
        integer d;
        begin
            thr_a = a; thr_b = b;
            for (d = -2; d <= 2; d = d + 1) begin
                value = a + d[15:0];
                for (mode = 0; mode < 3; mode = mode + 1) begin found = 0; check; found = 1; check; end
                mode = 2'b11; found = 0; check; found = 1; check;
                value = b + d[15:0];
                for (mode = 0; mode < 3; mode = mode + 1) begin found = 0; check; found = 1; check; end
                mode = 2'b11; found = 0; check; found = 1; check;
            end
        end
    endtask

    initial begin
        found = 0;

        // 경계값: 0 근방, 양수 · 음수, 그리고 표현 범위의 양 끝
        sweep_around(16'sd0,      16'sd10);
        sweep_around(16'sd1234,   16'sd4321);
        sweep_around(-16'sd1234, -16'sd12);
        sweep_around(16'sh7FFF,   16'sh7FFF);   // MAX
        sweep_around(16'sh8000,   16'sh8000);   // MIN
        sweep_around(-16'sd1,     16'sd1);

        // 부호확장을 빠뜨리면 여기서 무너집니다
        mode = 2'b00; value = 16'sh8000; thr_a = 16'sd1; thr_b = 16'sd0; found = 0; check;
        mode = 2'b01; value = 16'sh7FFF; thr_a = -16'sd1; check;
        mode = 2'b11; value = 16'sd0; thr_a = 16'sh8000; thr_b = 16'sh7FFF; check;

        // RANGE 에서 thr_a >= thr_b 는 오류가 아니라 정상적인 M=0 입니다
        mode = 2'b11; thr_a = 16'sd100; thr_b = 16'sd100;
        for (i = 90; i <= 110; i = i + 1) begin value = i[15:0]; check; end

        // 무작위
        for (i = 0; i < 20000; i = i + 1) begin
            value = $random; thr_a = $random; thr_b = $random;
            mode  = $random; found = $random;
            check;
        end

        if (errors == 0) $display("tb_predicate: PASS");
        else begin $display("tb_predicate: FAIL (%0d errors)", errors); $fatal; end
        $finish;
    end
endmodule
