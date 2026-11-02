//=====================================================================
// dram_burst_model.v -- grover_dram_amp_store.v 의 추상 burst 포트에
// 물리는 동작 수준 DRAM 모델 (시뮬 전용)
//
// hardware_dram 갈래는 반복이 끝날 때마다 512행 x 736비트 진폭표를 통째로
// DRAM 슬롯 하나에 적고, 필요할 때 그 슬롯을 통째로 읽어 옵니다. 실제
// 물리 바인딩(Arty A7-100T 의 DDR3L + MIG native UI 든 AXI4 든)은 아직
// 정해지지 않았고 나중에 따로 붙입니다. 이 모델은 그 자리에 들어가 다음
// 두 가지를 대신합니다.
//
//   1. 저장소   슬롯 129개 x 512행 x 736비트를 그대로 들고 있습니다.
//                store 한 것이 restore 로 비트 하나 안 틀리고 돌아오는지가
//                결국 이 갈래 전체의 정합성 근거입니다.
//   2. 심판     프로토콜 위반과 "쓴 적 없는 슬롯을 읽는" 사고를 잡습니다.
//                후자가 특히 중요합니다. grover_dram_param.vh 가 슬롯 0 을
//                절대 안 쓴다고 정해 놓았기 때문에, prep 시퀀서가 j=0 을
//                restore 로 처리하려 들면 실물에서는 쓰레기 진폭을 읽고도
//                조용히 계속 돌아갑니다. 여기서는 즉시 오류로 잡힙니다.
//
// 타이밍은 전부 파라미터입니다. MIG 를 붙일 사람이 실제 지연을 알게 되면
// WR_LAT/RD_LAT/BEAT_GAP 만 바꿔서 같은 회귀를 다시 돌리면 됩니다.
// STALL_EN 을 켜면 의사난수 백프레셔가 걸려 handshake 결함이 드러납니다.
//
// 주소 계약 (grover_dram_param.vh)
//   슬롯 j 의 시작 주소 = GD_AMP_BASE + j * GD_ITER_STRIDE
//   GD_ITER_STRIDE = 92바이트/행 * 512행 = 47104바이트
//   한 beat = 한 행 = 736비트. 버스트 길이는 len+1 beat (len = 511).
//=====================================================================
`timescale 1ns/1ps
`include "grover_dram_param.vh"

module dram_burst_model #(
    // 쓰기 요청(wr_req)을 받고 첫 beat 를 수락하기까지 비워 두는 사이클.
    parameter integer WR_LAT   = 4,
    // 읽기 요청(rd_req)을 받고 첫 beat 를 유효하게 내보내기까지의 사이클.
    // DDR3L 의 활성화/CAS 지연이 들어갈 자리라 쓰기보다 길게 둡니다.
    parameter integer RD_LAT   = 12,
    // beat 와 beat 사이에 강제로 비우는 사이클. 0 이면 매 사이클 연속 전송.
    parameter integer BEAT_GAP = 0,
    // 1 이면 LFSR 로 불규칙한 백프레셔를 겁니다. 연속 전송만 가정한
    // handshake 결함을 잡는 용도입니다.
    parameter integer STALL_EN = 0,
    // 1 이면 버스트마다 한 줄씩 찍습니다. 디버깅용.
    parameter integer VERBOSE  = 0
)(
    input  wire                            clk,
    input  wire                            rstn,

    // 쓰기 버스트 (grover_dram_amp_store STORE 쪽)
    input  wire                            wr_req,
    input  wire [`GD_ADDR_W-1:0]           wr_addr,
    input  wire [`GD_BURST_LEN_W-1:0]      wr_len,
    input  wire                            wr_valid,
    input  wire [`GP_P*`GP_AMP_W-1:0]      wr_data,
    input  wire                            wr_last,
    output wire                            wr_ready,

    // 읽기 버스트 (grover_dram_amp_store RESTORE 쪽)
    input  wire                            rd_req,
    input  wire [`GD_ADDR_W-1:0]           rd_addr,
    input  wire [`GD_BURST_LEN_W-1:0]      rd_len,
    output reg                             rd_valid,
    output reg  [`GP_P*`GP_AMP_W-1:0]      rd_data,
    input  wire                            rd_ready,
    output reg                             rd_last,

    // 관측용. 테스트벤치가 이걸로 "몇 번 저장하고 몇 번 복원했나" 를 봅니다.
    output reg  [31:0]                     store_bursts,
    output reg  [31:0]                     restore_bursts,
    output wire [31:0]                     err_count
);
    localparam integer ROW_BITS = `GP_P * `GP_AMP_W;   // 736
    localparam integer ROWS     = `GP_ROWS;            // 512
    localparam integer SLOTS    = `GP_M_MAX + 1;       // 129 (j = 0..128)
    localparam integer CELLS    = SLOTS * ROWS;        // 66048

    // 슬롯 0 은 규격상 절대 안 씁니다. 그래도 배열은 통째로 잡아 두고,
    // "썼는지" 를 따로 표시해서 읽기 때 대조합니다.
    reg [ROW_BITS-1:0] mem     [0:CELLS-1];
    reg                written [0:CELLS-1];

    integer i;

    // 오류 카운터는 쓰기/읽기 FSM 이 각자 하나씩 가집니다. 하나를 두 개의
    // always 블록에서 올리면 다중 구동이 되어 시뮬레이터마다 결과가
    // 달라집니다.
    reg [31:0] err_w;
    reg [31:0] err_r;
    assign err_count = err_w + err_r;

    //-----------------------------------------------------------------
    // 주소 -> 슬롯 변환. 음수 반환값이 오류 코드입니다.
    //   -1 베이스보다 앞  -2 슬롯 경계 어긋남  -3 슬롯 범위 밖
    //-----------------------------------------------------------------
    function integer addr_to_slot;
        input [`GD_ADDR_W-1:0] a;
        integer off;
        begin
            off = a - `GD_AMP_BASE;
            if (off < 0)
                addr_to_slot = -1;
            else if ((off % `GD_ITER_STRIDE) != 0)
                addr_to_slot = -2;
            else if ((off / `GD_ITER_STRIDE) >= SLOTS)
                addr_to_slot = -3;
            else
                addr_to_slot = off / `GD_ITER_STRIDE;
        end
    endfunction

    //-----------------------------------------------------------------
    // 백프레셔용 LFSR. STALL_EN=0 이면 아무 영향이 없습니다.
    //-----------------------------------------------------------------
    reg [15:0] lfsr;
    wire       stall_now = (STALL_EN != 0) && lfsr[0];


    always @(posedge clk) begin
        if (!rstn) lfsr <= 16'hACE1;
        else       lfsr <= {lfsr[0] ^ lfsr[2] ^ lfsr[3] ^ lfsr[5], lfsr[15:1]};
    end

    //-----------------------------------------------------------------
    // 쓰기 FSM
    //-----------------------------------------------------------------
    localparam [1:0] W_IDLE = 2'd0, W_LAT = 2'd1, W_RUN = 2'd2;

    reg [1:0]   w_st;
    reg [31:0]  w_base;      // 슬롯 시작 셀 번호
    reg [31:0]  w_cnt;       // 지금까지 받은 beat 수
    reg [31:0]  w_len;       // 이번 버스트의 len (beat 수 - 1)
    reg [31:0]  w_wait;
    reg [31:0]  w_gap;
    integer     w_slot;

    //-----------------------------------------------------------------
    // wr_ready 는 조합이어야 합니다. 레지스터로 두면 "이번 사이클에 안
    // 받으면서 ready 는 들고 있는" 한 사이클짜리 창이 생깁니다 (전송 직후
    // beat 간격을 시작할 때). 그 창을 본 마스터는 받아들여지지도 않은 beat
    // 를 보낸 것으로 세고 행이 통째로 밀립니다. valid/ready 계약이 원래
    // 금지하는 상황이라, 모델이 그걸 어기면 안 됩니다.
    //-----------------------------------------------------------------
    assign wr_ready = (w_st == W_RUN) && (w_gap == 32'd0) && !stall_now;

    always @(posedge clk) begin
        if (!rstn) begin
            w_st         <= W_IDLE;
            w_base       <= 32'd0;
            w_cnt        <= 32'd0;
            w_len        <= 32'd0;
            w_wait       <= 32'd0;
            w_gap        <= 32'd0;
            store_bursts <= 32'd0;
            err_w        <= 32'd0;
        end else begin
            case (w_st)
                W_IDLE: begin
                    // 요청 없이 데이터부터 들이미는 것은 계약 위반입니다.
                    if (wr_valid && !wr_req) begin
                        err_w <= err_w + 1;
                        $display("[DRAM] 오류: 쓰기 요청 없이 wr_valid 가 떴습니다 (t=%0t)", $time);
                    end
                    if (wr_req) begin
                        w_slot = addr_to_slot(wr_addr);
                        if (w_slot < 0) begin
                            err_w <= err_w + 1;
                            $display("[DRAM] 오류: 쓰기 주소 0x%08x 가 잘못됐습니다 (코드 %0d)",
                                     wr_addr, w_slot);
                            w_base <= 32'd0;
                        end else if (w_slot == 0) begin
                            err_w <= err_w + 1;
                            $display("[DRAM] 오류: 슬롯 0 에 쓰려 합니다. j=0 은 INIT 로 재생성해야 합니다");
                            w_base <= 32'd0;
                        end else begin
                            w_base <= w_slot * ROWS;
                        end
                        w_len  <= {{(32-`GD_BURST_LEN_W){1'b0}}, wr_len};
                        w_cnt  <= 32'd0;
                        w_wait <= WR_LAT;
                        w_st   <= W_LAT;
                    end
                end

                W_LAT: begin
                    if (w_wait <= 1) begin
                        w_st  <= W_RUN;
                        w_gap <= 32'd0;
                    end else begin
                        w_wait <= w_wait - 1;
                    end
                end

                W_RUN: begin
                    if (w_gap != 0) begin
                        w_gap <= w_gap - 1;
                    end else if (wr_valid && wr_ready) begin
                        mem[w_base + w_cnt]     <= wr_data;
                        written[w_base + w_cnt] <= 1'b1;

                        // 마지막 beat 표시가 카운터와 어긋나면 잡습니다.
                        if (wr_last != (w_cnt == w_len)) begin
                            err_w <= err_w + 1;
                            $display("[DRAM] 오류: wr_last 불일치 beat=%0d len=%0d last=%0b",
                                     w_cnt, w_len, wr_last);
                        end

                        if (w_cnt == w_len) begin
                            store_bursts <= store_bursts + 1;
                            w_st         <= W_IDLE;
                            if (VERBOSE != 0)
                                $display("[DRAM] 저장 완료 슬롯 %0d (%0d beat, t=%0t)",
                                         w_base / ROWS, w_len + 1, $time);
                        end else begin
                            w_cnt <= w_cnt + 1;
                            w_gap <= BEAT_GAP;
                        end
                    end
                end

                default: w_st <= W_IDLE;
            endcase
        end
    end

    //-----------------------------------------------------------------
    // 읽기 FSM
    //-----------------------------------------------------------------
    localparam [1:0] R_IDLE = 2'd0, R_LAT = 2'd1, R_RUN = 2'd2;

    reg [1:0]   r_st;
    reg [31:0]  r_base;
    reg [31:0]  r_cnt;
    reg [31:0]  r_len;
    reg [31:0]  r_wait;
    reg [31:0]  r_gap;
    integer     r_slot;
    integer     unwritten;

    always @(posedge clk) begin
        if (!rstn) begin
            r_st           <= R_IDLE;
            r_base         <= 32'd0;
            r_cnt          <= 32'd0;
            r_len          <= 32'd0;
            r_wait         <= 32'd0;
            r_gap          <= 32'd0;
            rd_valid       <= 1'b0;
            rd_last        <= 1'b0;
            rd_data        <= {ROW_BITS{1'b0}};
            restore_bursts <= 32'd0;
            err_r          <= 32'd0;
        end else begin
            case (r_st)
                R_IDLE: begin
                    rd_valid <= 1'b0;
                    rd_last  <= 1'b0;
                    if (rd_req) begin
                        r_slot = addr_to_slot(rd_addr);
                        if (r_slot < 0) begin
                            err_r <= err_r + 1;
                            $display("[DRAM] 오류: 읽기 주소 0x%08x 가 잘못됐습니다 (코드 %0d)",
                                     rd_addr, r_slot);
                            r_base <= 32'd0;
                        end else begin
                            // 이 갈래에서 제일 무서운 결함: 쓴 적 없는 슬롯을
                            // 읽고도 아무 일 없다는 듯 진행하는 것. 실물이라면
                            // 이전 세션 찌꺼기가 나오고 진폭이 조용히 망가진
                            // 채로 탐색이 계속됩니다.
                            unwritten = 0;
                            for (i = 0; i < ROWS; i = i + 1)
                                if (written[r_slot * ROWS + i] !== 1'b1)
                                    unwritten = unwritten + 1;
                            if (unwritten != 0) begin
                                err_r <= err_r + 1;
                                $display("[DRAM] 오류: 슬롯 %0d 을 읽으려는데 %0d행이 기록된 적 없습니다",
                                         r_slot, unwritten);
                            end
                            r_base <= r_slot * ROWS;
                        end
                        r_len  <= {{(32-`GD_BURST_LEN_W){1'b0}}, rd_len};
                        r_cnt  <= 32'd0;
                        r_wait <= RD_LAT;
                        r_st   <= R_LAT;
                    end
                end

                R_LAT: begin
                    if (r_wait <= 1) begin
                        rd_data  <= mem[r_base];
                        rd_valid <= 1'b1;
                        rd_last  <= (r_len == 32'd0);
                        r_st     <= R_RUN;
                    end else begin
                        r_wait <= r_wait - 1;
                    end
                end

                R_RUN: begin
                    if (r_gap != 0) begin
                        // 간격 삽입 중. 마지막 한 사이클에 다음 beat 를 실어
                        // 두었다가 곧바로 valid 를 올립니다.
                        r_gap <= r_gap - 1;
                        if (r_gap == 1) begin
                            rd_data  <= mem[r_base + r_cnt];
                            rd_valid <= 1'b1;
                            rd_last  <= (r_cnt == r_len);
                        end else begin
                            rd_valid <= 1'b0;
                        end
                    end else if (rd_valid && rd_ready) begin
                        if (r_cnt == r_len) begin
                            rd_valid       <= 1'b0;
                            rd_last        <= 1'b0;
                            restore_bursts <= restore_bursts + 1;
                            r_st           <= R_IDLE;
                            if (VERBOSE != 0)
                                $display("[DRAM] 복원 완료 슬롯 %0d (%0d beat, t=%0t)",
                                         r_base / ROWS, r_len + 1, $time);
                        end else begin
                            r_cnt <= r_cnt + 1;
                            if ((BEAT_GAP != 0) || stall_now) begin
                                rd_valid <= 1'b0;
                                r_gap    <= (BEAT_GAP != 0) ? BEAT_GAP : 1;
                            end else begin
                                rd_data <= mem[r_base + r_cnt + 1];
                                rd_last <= ((r_cnt + 1) == r_len);
                            end
                        end
                    end
                end

                default: r_st <= R_IDLE;
            endcase
        end
    end

    //-----------------------------------------------------------------
    // 초기화. written 만 지웁니다. mem 은 일부러 안 지웁니다 -- 실물 DRAM 도
    // 전원 인가 직후 내용이 정해져 있지 않고, 그 상태에서 읽으면 안 된다는
    // 것이 지금 검사하려는 계약이기 때문입니다.
    //-----------------------------------------------------------------
    initial begin
        for (i = 0; i < CELLS; i = i + 1) begin
            written[i] = 1'b0;
            mem[i]     = {ROW_BITS{1'bx}};
        end
    end

endmodule
