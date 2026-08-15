//=====================================================================
// grover_mmio.v -- APB 슬레이브 CSR (소유자 A)
//
// 통신_명령_데이터패스.md 3.3절 통합안. 레지스터 20개, 간격 8바이트.
// RVX mmio 생성기의 입력 XML 스키마가 아직 확인되지 않았고(해설서 17.8절
// 5번), 무엇보다 생성된 블록이 밖으로 내보내는 쓰기 스트로브가 명령형
// 레지스터의 것 하나뿐이라 설정 레지스터의 무효화 OR 를 만들 수 없습니다.
// 그래서 3.3절이 기본안으로 둔 (b) 수기 작성 쪽을 따릅니다.
//
// 세 가지 규약을 지킵니다.
//   - 명령형 레지스터는 저장 공간이 없습니다. 쓰면 1사이클 펄스가 나가고
//     읽으면 0 입니다. 무엇을 썼는지는 무시합니다.
//   - 상태 레지스터는 입력 포트를 그대로 반사합니다.
//   - 설정 레지스터는 여기 저장되고 값이 출력 와이어로 상시 나갑니다.
//
// 무효화 배선이 이 파일의 핵심입니다. ● 가 붙은 레지스터에 쓰기가 들어오면
// 그 자리에서 cfg_we 가 서고 cache_valid 가 0 으로 떨어집니다. 이것을
// 펌웨어에 맡기면 나중에 술어를 하나 더 추가한 사람이 무효화를 빼먹는
// 순간, 크래시도 타임아웃도 아닌 그럴듯한 인덱스 하나가 나옵니다.
//=====================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_mmio (
    input  wire        clk,
    input  wire        rstn,
    // APB3 슬레이브
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [7:0]  paddr,
    input  wire [31:0] pwdata,
    output reg  [31:0] prdata,
    output wire        pready,
    output reg         pslverr,
    // 설정 출력 (RW)
    output reg  [1:0]  cfg_mode,
    output reg  [15:0] cfg_thr_a,
    output reg  [15:0] cfg_thr_b,
    output reg  [4:0]  cfg_n_qubits,
    output reg         cfg_enum_mode,
    output reg         cfg_auto_shot,
    output reg  [15:0] cfg_j_target,
    output reg  [31:0] cfg_data_addr,
    output reg  [31:0] cfg_data_words,
    output reg  [31:0] cfg_data_seed,
    output reg         cfg_data_sel,
    // 명령 펄스 (W1P)
    output reg         cmd_clear_mask,
    output reg         cmd_load_start,
    output reg         cmd_force_init,
    output reg         cmd_start,
    // 무효화 OR -- ● 가 붙은 레지스터의 쓰기 스트로브를 모은 것
    output wire        cfg_we,
    // 상태 입력 (RO)
    input  wire        st_busy,
    input  wire        st_done_pulse,
    input  wire        st_verify_hit,
    input  wire        st_cache_valid,
    input  wire        st_sat_sticky,
    input  wire        st_too_many,
    input  wire [`GP_NB-1:0] st_cand,
    input  wire [15:0] st_j_cur,
    input  wire [31:0] st_cycle_cnt,
    input  wire [31:0] st_passes_run
);
    localparam R_MODE       = 5'd0,  R_THR_A      = 5'd1,  R_THR_B     = 5'd2,
               R_NQUBITS    = 5'd3,  R_ENUM       = 5'd4,  R_AUTOSHOT  = 5'd5,
               R_JTARGET    = 5'd6,  R_DATA_ADDR  = 5'd7,  R_DATA_WORDS= 5'd8,
               R_DATA_SEED  = 5'd9,  R_DATA_SEL   = 5'd10, R_CLEAR_MASK= 5'd11,
               R_LOAD_START = 5'd12, R_FORCE_INIT = 5'd13, R_START     = 5'd14,
               R_STATUS     = 5'd15, R_CAND       = 5'd16, R_JCUR      = 5'd17,
               R_CYCLE_CNT  = 5'd18, R_PASSES_RUN = 5'd19;

    localparam N_REG = 20;

    assign pready = 1'b1;                      // 대기 상태 없음

    wire [4:0] ridx    = paddr[7:3];
    wire       aligned = (paddr[2:0] == 3'b000);
    wire       mapped  = aligned && (ridx < N_REG);
    wire       access  = psel & penable;
    wire       wr      = access &  pwrite & mapped;
    wire       rd      = access & ~pwrite & mapped;

    // 레지스터별 쓰기 스트로브
    wire we_mode   = wr && (ridx == R_MODE);
    wire we_thr_a  = wr && (ridx == R_THR_A);
    wire we_thr_b  = wr && (ridx == R_THR_B);
    wire we_nq     = wr && (ridx == R_NQUBITS);
    wire we_enum   = wr && (ridx == R_ENUM);
    wire we_auto   = wr && (ridx == R_AUTOSHOT);
    wire we_jtgt   = wr && (ridx == R_JTARGET);
    wire we_daddr  = wr && (ridx == R_DATA_ADDR);
    wire we_dwords = wr && (ridx == R_DATA_WORDS);
    wire we_dseed  = wr && (ridx == R_DATA_SEED);
    wire we_dsel   = wr && (ridx == R_DATA_SEL);

    // 3.4절의 무효화 OR. auto_shot · j_target · start 는 ● 가 아닙니다 --
    // 모드와 목표 반복 수는 진폭 배열의 내용을 바꾸지 않기 때문입니다.
    assign cfg_we = we_mode | we_thr_a | we_thr_b | we_nq | we_enum |
                    we_daddr | we_dwords | we_dseed | we_dsel |
                    cmd_clear_mask | cmd_load_start;

    // done 은 IP 에서 1사이클 펄스로 옵니다. 폴링이 놓치지 않도록 여기서
    // 유지형으로 바꾸고 start 가 클리어합니다 (통신 규약 1).
    reg done_sticky;

    always @(posedge clk) begin
        if (!rstn) begin
            cfg_mode       <= 2'd0;
            cfg_thr_a      <= 16'd0;
            cfg_thr_b      <= 16'd0;
            cfg_n_qubits   <= 5'd15;
            cfg_enum_mode  <= 1'b0;
            cfg_auto_shot  <= 1'b1;
            cfg_j_target   <= 16'd0;
            cfg_data_addr  <= 32'd0;
            cfg_data_words <= 32'd0;
            cfg_data_seed  <= 32'd1;
            cfg_data_sel   <= 1'b1;      // 기본은 온칩 생성기
            cmd_clear_mask <= 1'b0;
            cmd_load_start <= 1'b0;
            cmd_force_init <= 1'b0;
            cmd_start      <= 1'b0;
            done_sticky    <= 1'b0;
        end else begin
            cmd_clear_mask <= 1'b0;
            cmd_load_start <= 1'b0;
            cmd_force_init <= 1'b0;
            cmd_start      <= 1'b0;

            if (we_mode)   cfg_mode       <= pwdata[1:0];
            if (we_thr_a)  cfg_thr_a      <= pwdata[15:0];
            if (we_thr_b)  cfg_thr_b      <= pwdata[15:0];
            if (we_nq)     cfg_n_qubits   <= pwdata[4:0];
            if (we_enum)   cfg_enum_mode  <= pwdata[0];
            if (we_auto)   cfg_auto_shot  <= pwdata[0];
            if (we_jtgt)   cfg_j_target   <= pwdata[15:0];
            if (we_daddr)  cfg_data_addr  <= pwdata;
            if (we_dwords) cfg_data_words <= pwdata;
            if (we_dseed)  cfg_data_seed  <= pwdata;
            if (we_dsel)   cfg_data_sel   <= pwdata[0];

            if (wr && (ridx == R_CLEAR_MASK)) cmd_clear_mask <= 1'b1;
            if (wr && (ridx == R_LOAD_START)) cmd_load_start <= 1'b1;
            if (wr && (ridx == R_FORCE_INIT)) cmd_force_init <= 1'b1;
            if (wr && (ridx == R_START))      cmd_start      <= 1'b1;

            if (wr && (ridx == R_START)) done_sticky <= 1'b0;
            else if (st_done_pulse)      done_sticky <= 1'b1;
        end
    end

    wire [31:0] status_w = {26'd0, st_too_many, st_sat_sticky, st_cache_valid,
                            st_verify_hit, done_sticky, st_busy};

    always @* begin
        case (ridx)
            R_MODE        : prdata = {30'd0, cfg_mode};
            R_THR_A       : prdata = {16'd0, cfg_thr_a};
            R_THR_B       : prdata = {16'd0, cfg_thr_b};
            R_NQUBITS     : prdata = {27'd0, cfg_n_qubits};
            R_ENUM        : prdata = {31'd0, cfg_enum_mode};
            R_AUTOSHOT    : prdata = {31'd0, cfg_auto_shot};
            R_JTARGET     : prdata = {16'd0, cfg_j_target};
            R_DATA_ADDR   : prdata = cfg_data_addr;
            R_DATA_WORDS  : prdata = cfg_data_words;
            R_DATA_SEED   : prdata = cfg_data_seed;
            R_DATA_SEL    : prdata = {31'd0, cfg_data_sel};
            R_STATUS      : prdata = status_w;
            R_CAND        : prdata = {{(32-`GP_NB){1'b0}}, st_cand};
            R_JCUR        : prdata = {16'd0, st_j_cur};
            R_CYCLE_CNT   : prdata = st_cycle_cnt;
            R_PASSES_RUN  : prdata = st_passes_run;
            default       : prdata = 32'd0;   // 명령형 레지스터는 읽으면 0
        endcase
    end

    // 정렬되지 않은 접근과 미할당 주소는 오류로 떨어집니다.
    always @* pslverr = access && !mapped;
endmodule
