//=====================================================================
// grover_top.v -- Grover IP 최상위 배선 (소유자 A)
//
// 계약 4.12. 20개 하위 모듈을 인스턴스화하고 조정 로직 셋을 소유합니다.
//   (1) amp_mem 읽기 포트의 주소 먹스 -- 반복과 측정이 다투는 유일한 자원
//   (2) INIT 구간의 amp 쓰기 데이터 먹스와 초기 진폭 계산
//   (3) 무효화 OR 와 sat_sticky 래치
//
// 철칙: 이 파일은 ervp_*.vh 를 include 하지 않습니다. RVX 의존성은 SoC
// 래퍼(grover_soc_top.v)에만 둡니다. 이 한 줄이 깨지면 iverilog 로 로컬에서
// 회귀를 돌리던 사람들이 통째로 원격 서버에 묶입니다.
//=====================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_top (
    input  wire        clk,
    input  wire        rstn,
    // ── APB3 슬레이브 (CSR) ─────────────────────────────────────────
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [7:0]  paddr,
    input  wire [31:0] pwdata,
    output wire [31:0] prdata,
    output wire        pready,
    output wire        pslverr,
    // ── AHB-Lite 마스터 (데이터 DMA) ────────────────────────────────
    output wire [31:0] haddr,
    output wire [1:0]  htrans,
    output wire        hwrite,
    output wire [2:0]  hsize,
    output wire [2:0]  hburst,
    output wire [3:0]  hprot,
    output wire [31:0] hwdata,
    input  wire        hready,
    input  wire        hresp,
    input  wire [31:0] hrdata,
    // ── 열거 결과 큐 ────────────────────────────────────────────────
    // 반환 경로가 아직 정해지지 않았습니다 (해설서 17.8절 6번 -- FIFO 를
    // CSR 에 붙일지, 호스트가 M 번 호출할지). 결정될 때까지 IP 경계 밖으로
    // 내놓아 두어 SoC 래퍼 쪽에서 묶을 수 있게 합니다.
    input  wire        res_pop,
    output wire [`GP_NB-1:0] res_dout,
    output wire        res_empty,
    output wire [7:0]  res_count
);
    localparam P    = `GP_P;
    localparam DW   = `GP_DW;
    localparam W    = `GP_W;
    localparam AW   = `GP_AW;
    localparam NB   = `GP_NB;
    localparam TMW  = `GP_TMW;

    // ── CSR ─────────────────────────────────────────────────────────
    wire [1:0]  cfg_mode;
    wire [15:0] cfg_thr_a, cfg_thr_b, cfg_j_target;
    wire [4:0]  cfg_n_qubits;
    wire        cfg_enum_mode, cfg_auto_shot, cfg_data_sel;
    wire [31:0] cfg_data_addr, cfg_data_words, cfg_data_seed;
    wire        cmd_clear_mask, cmd_load_start, cmd_force_init, cmd_start;
    wire        csr_cfg_we;

    // ── 블록 사이 신호 ──────────────────────────────────────────────
    wire        shot_start, do_init, iter_start, iter_do_init;
    wire [15:0] j_req, delta_j, iter_count, j_cur;
    wire        cache_valid, iter_busy, iter_done, pass_tick;
    wire [3:0]  fsm_state;
    wire [AW-1:0] iter_amp_raddr, iter_amp_waddr, iter_data_addr;
    wire        iter_amp_re, iter_amp_we, iter_data_re;
    wire        phase, acc_clear, acc_en;

    wire        meas_start, meas_busy, meas_done, meas_re;
    wire [AW-1:0] meas_addr;
    wire [NB-1:0] meas_cand;

    wire        vfy_start, vfy_busy, vfy_done, vfy_hit;
    wire [NB-1:0] vfy_addr;

    wire        mask_set, mclr_busy, mclr_done;
    wire [NB-1:0] mask_idx;

    wire [31:0] rnd;
    wire        rnd_draw_shot, rnd_draw_meas;
    wire [4:0]  rom_idx;
    wire [15:0] rom_m;

    wire        res_push, res_full;
    wire [NB-1:0] res_din;

    wire        shot_busy, shot_done, too_many, verify_hit;
    wire [NB-1:0] shot_cand;
    wire [15:0] shots;
    wire [31:0] cycle_cnt, passes_run;

    // ── 초기 진폭 (계약 1.3) ────────────────────────────────────────
    // n 이 런타임 가변이라 헤더 상수로 굳히지 않고 여기서 계산합니다.
    // 홀수 n 만 1/sqrt(2) 를 반올림하는 대가를 치릅니다 -- n=15 에서 362,
    // 오차 0.011%. 그 오차 때문에 노름이 정확히 1 이 아니고, 그래서
    // born_sampler 에 안전망 두 줄이 필요합니다.
    wire [4:0] init_sh = cfg_n_qubits[0] ? ((cfg_n_qubits - 5'd1) >> 1)
                                         : (cfg_n_qubits >> 1);
    wire signed [DW-1:0] init_amp = cfg_n_qubits[0]
                                  ? (`GP_INV_SQRT2_Q216 >>> init_sh)
                                  : (`GP_ONE_Q216       >>> init_sh);

    // ── 메모리 버스 ─────────────────────────────────────────────────
    wire [P*DW-1:0] amp_rdata, amp_wdata;
    wire [P*W-1:0]  data_rdata;
    wire [P-1:0]    mask_rdata;
    wire signed [W-1:0] one_rdata;
    wire            one_bit;

    // 계약 4.12 -- 두 마스터가 amp_mem 읽기 주소를 다툽니다.
    // amp_we 가 측정 중 강제로 0 인 것이 재개 캐시가 성립하는 물리적 근거입니다.
    // 이 한 줄이 깨지면 캐시의 정당화가 통째로 무너집니다.
    wire [AW-1:0] amp_raddr = meas_busy ? meas_addr : iter_amp_raddr;
    wire          amp_re    = meas_busy ? meas_re   : iter_amp_re;
    wire          amp_we    = meas_busy ? 1'b0      : iter_amp_we;

    // INIT 구간에는 레인 출력 대신 초기 진폭 상수를 씁니다.
    wire init_active = (fsm_state == `GP_ST_INIT);

    // ── 적재 경로 (AHB DMA 또는 온칩 생성기) ────────────────────────
    wire        ahb_wr_en, gen_wr_en, load_busy_ahb, load_busy_gen;
    wire        ahb_done, gen_done, ahb_err;
    wire [NB-1:0] ahb_wr_addr, gen_wr_addr;
    wire signed [W-1:0] ahb_wr_data, gen_wr_data;

    wire        dm_we    = cfg_data_sel ? gen_wr_en   : ahb_wr_en;
    wire [NB-1:0] dm_waddr = cfg_data_sel ? gen_wr_addr : ahb_wr_addr;
    wire signed [W-1:0] dm_wdata = cfg_data_sel ? gen_wr_data : ahb_wr_data;
    wire        load_busy = load_busy_ahb | load_busy_gen;

    // ── 레인 배열 ───────────────────────────────────────────────────
    wire [P*DW-1:0] tree_din;
    wire [P*DW-1:0] amp_wdata_lane;
    wire [P-1:0]    lane_hit, lane_sat;
    wire signed [TMW-1:0] two_mean;

    genvar b;
    generate
        for (b = 0; b < P; b = b + 1) begin : g_lane
            // 열거 모드가 아니면 마스크를 보지 않습니다. 마스크는 클리어되어
            // 있겠지만, 모드로 한 번 더 막아 두는 편이 안전합니다.
            wire found_b = cfg_enum_mode & mask_rdata[b];

            grover_predicate u_pred (
                .mode  (cfg_mode),
                .value (data_rdata[b*W +: W]),
                .thr_a (cfg_thr_a),
                .thr_b (cfg_thr_b),
                .found (found_b),
                .hit   (lane_hit[b])
            );

            grover_lane u_lane (
                .phase    (phase),
                .hit      (lane_hit[b]),
                .amp_in   (amp_rdata[b*DW +: DW]),
                .two_mean (two_mean),
                .amp_out  (amp_wdata_lane[b*DW +: DW]),
                .amp_tree (tree_din[b*DW +: DW]),
                .sat      (lane_sat[b])
            );
        end
    endgenerate

    // PIPE_LAT=2 의 t+1 레지스터입니다. 이것이 있어야 BRAM 읽기 -> 술어 ->
    // 레인 -> BRAM 쓰기가 한 사이클에 몰리지 않습니다. INIT 은 읽지 않으므로
    // 레지스터를 거치지 않고 상수를 바로 씁니다.
    reg [P*DW-1:0] amp_wdata_r;
    always @(posedge clk) amp_wdata_r <= amp_wdata_lane;
    assign amp_wdata = init_active ? {P{init_amp}} : amp_wdata_r;

    // ── 누산 -> 평균 ────────────────────────────────────────────────
    wire signed [`GP_PSW-1:0]  partial;
    wire signed [`GP_ACCW-1:0] total;

    grover_adder_tree u_tree (.din(tree_din), .partial(partial));

    grover_sum_accum u_accum (
        .clk(clk), .rstn(rstn),
        .clear(acc_clear), .en(acc_en),
        .partial(partial), .total(total)
    );

    grover_two_mean_calc u_mean (
        .total(total), .n_qubits(cfg_n_qubits), .two_mean(two_mean)
    );

    // ── 메모리 ──────────────────────────────────────────────────────
    grover_amp_mem u_amp (
        .clk(clk),
        .raddr(amp_raddr), .re(amp_re), .rdata(amp_rdata),
        .waddr(iter_amp_waddr), .we(amp_we), .wdata(amp_wdata)
    );

    grover_data_mem u_data (
        .clk(clk),
        .addr(iter_data_addr), .re(iter_data_re), .rdata(data_rdata),
        .wr_addr(dm_waddr), .we(dm_we), .wdata(dm_wdata),
        .one_addr(vfy_addr), .one_rdata(one_rdata)
    );

    grover_mask_mem u_mask (
        .clk(clk), .rstn(rstn),
        .addr(iter_data_addr), .re(iter_data_re), .rdata(mask_rdata),
        .set(mask_set), .set_idx(mask_idx),
        .one_addr(vfy_addr), .one_bit(one_bit),
        .mclr_start(cmd_clear_mask), .mclr_busy(mclr_busy), .mclr_done(mclr_done)
    );

    // ── 반복 · 측정 · 검증 ──────────────────────────────────────────
    grover_ctrl_fsm u_ctrl (
        .clk(clk), .rstn(rstn),
        .iter_start(iter_start), .iter_do_init(iter_do_init),
        .iter_count(iter_count), .n_qubits(cfg_n_qubits),
        .iter_busy(iter_busy), .iter_done(iter_done),
        .state(fsm_state),
        .amp_raddr(iter_amp_raddr), .amp_waddr(iter_amp_waddr),
        .amp_re(iter_amp_re), .amp_we(iter_amp_we),
        .data_addr(iter_data_addr), .data_re(iter_data_re),
        .phase(phase), .acc_clear(acc_clear), .acc_en(acc_en),
        .pass_tick(pass_tick)
    );

    grover_born_sampler u_meas (
        .clk(clk), .rstn(rstn),
        .meas_start(meas_start), .n_qubits(cfg_n_qubits),
        .rnd(rnd), .rnd_draw(rnd_draw_meas),
        .amp_rdata(amp_rdata),
        .meas_addr(meas_addr), .meas_re(meas_re),
        .meas_busy(meas_busy), .meas_done(meas_done), .cand(meas_cand)
    );

    grover_verify u_vfy (
        .clk(clk), .rstn(rstn),
        .vfy_start(vfy_start), .cand(meas_cand),
        .mode(cfg_mode), .thr_a(cfg_thr_a), .thr_b(cfg_thr_b),
        // 오라클 레인과 같은 게이트를 겁니다. 열거 모드가 아니면 mask_mem 은
        // 클리어된 적이 없을 수 있고(BRAM 초기값은 약속되지 않습니다), 그
        // 쓰레기 비트가 검증에 새면 멀쩡한 해가 조용히 기각됩니다.
        .one_addr(vfy_addr), .one_rdata(one_rdata),
        .mask_bit(cfg_enum_mode & one_bit),
        .vfy_busy(vfy_busy), .vfy_done(vfy_done), .vfy_hit(vfy_hit)
    );

    // ── 캐시 · 샷 루프 · 난수 ───────────────────────────────────────
    // 마스크가 바뀌면 오라클이 바뀌므로 CSR 무효화와 같은 취급을 합니다.
    wire cache_inval = csr_cfg_we | mask_set;

    grover_cache_ctrl u_cache (
        .clk(clk), .rstn(rstn),
        .shot_start(shot_start), .j_req(j_req),
        .force_init(cmd_force_init), .cfg_we(cache_inval),
        .iter_done(iter_done),
        .do_init(do_init), .delta_j(delta_j),
        .j_cur(j_cur), .cache_valid(cache_valid)
    );

    grover_iter_rom u_rom (
        .idx(rom_idx), .n_qubits(cfg_n_qubits), .m(rom_m), .last()
    );

    // 시드의 출처와 리셋 값은 계약 9절에서 아직 미정입니다. 지금은 리셋
    // 상수에서 자유 진행하고, 규약이 정해지면 여기에 CSR 을 물립니다.
    grover_lfsr u_lfsr (
        .clk(clk), .rstn(rstn),
        .seed_we(1'b0), .seed(32'd0),
        .draw(rnd_draw_shot | rnd_draw_meas),
        .rnd(rnd)
    );

    grover_result_fifo u_resq (
        .clk(clk), .rstn(rstn), .clr(cmd_clear_mask),
        .push(res_push), .din(res_din),
        .pop(res_pop), .dout(res_dout),
        .empty(res_empty), .full(res_full), .count(res_count)
    );

    grover_shot_fsm u_shot (
        .clk(clk), .rstn(rstn),
        .start(cmd_start), .auto_shot(cfg_auto_shot), .enum_mode(cfg_enum_mode),
        .cfg_j_target(cfg_j_target), .n_qubits(cfg_n_qubits),
        .shot_cap(`GP_SHOT_CAP),
        .shot_start(shot_start), .j_req(j_req),
        .do_init(do_init), .delta_j(delta_j),
        .iter_start(iter_start), .iter_do_init(iter_do_init),
        .iter_count(iter_count), .iter_done(iter_done), .pass_tick(pass_tick),
        .meas_start(meas_start), .meas_done(meas_done), .meas_cand(meas_cand),
        .vfy_start(vfy_start), .vfy_done(vfy_done), .vfy_hit(vfy_hit),
        .mask_set(mask_set), .mask_idx(mask_idx), .mclr_busy(mclr_busy),
        .rnd(rnd), .rnd_draw(rnd_draw_shot),
        .rom_idx(rom_idx), .rom_m(rom_m),
        .res_push(res_push), .res_data(res_din), .res_full(res_full),
        .busy(shot_busy), .done(shot_done), .too_many(too_many),
        .verify_hit(verify_hit), .cand(shot_cand), .shots(shots),
        .cycle_cnt(cycle_cnt), .passes_run(passes_run)
    );

    // ── 적재 ────────────────────────────────────────────────────────
    grover_ahb_master u_ahb (
        .clk(clk), .rstn(rstn),
        .load_start(cmd_load_start & ~cfg_data_sel),
        .src_addr(cfg_data_addr), .words(cfg_data_words),
        .load_busy(load_busy_ahb), .load_done(ahb_done), .load_err(ahb_err),
        .wr_en(ahb_wr_en), .wr_addr(ahb_wr_addr), .wr_data(ahb_wr_data),
        .haddr(haddr), .htrans(htrans), .hwrite(hwrite), .hsize(hsize),
        .hburst(hburst), .hprot(hprot), .hwdata(hwdata),
        .hready(hready), .hresp(hresp), .hrdata(hrdata)
    );

    grover_data_gen u_gen (
        .clk(clk), .rstn(rstn),
        .gen_start(cmd_load_start & cfg_data_sel),
        .seed(cfg_data_seed), .words(cfg_data_words),
        .wr_en(gen_wr_en), .wr_addr(gen_wr_addr), .wr_data(gen_wr_data),
        .gen_busy(load_busy_gen), .gen_done(gen_done)
    );

    // ── 포화 스티키 (계약 10절 C -> A) ──────────────────────────────
    // 정상 동작에서는 서지 않아야 합니다. 서면 Q2.16 이 모자란다는 신호이고,
    // 그때는 DW 를 올리는 대신 P 를 낮추는 것이 BRAM 예산상 대안입니다.
    reg sat_sticky;
    always @(posedge clk) begin
        if (!rstn)          sat_sticky <= 1'b0;
        else if (cmd_start) sat_sticky <= 1'b0;
        else if (|lane_sat) sat_sticky <= 1'b1;
    end

    grover_mmio u_mmio (
        .clk(clk), .rstn(rstn),
        .psel(psel), .penable(penable), .pwrite(pwrite), .paddr(paddr),
        .pwdata(pwdata), .prdata(prdata), .pready(pready), .pslverr(pslverr),
        .cfg_mode(cfg_mode), .cfg_thr_a(cfg_thr_a), .cfg_thr_b(cfg_thr_b),
        .cfg_n_qubits(cfg_n_qubits), .cfg_enum_mode(cfg_enum_mode),
        .cfg_auto_shot(cfg_auto_shot), .cfg_j_target(cfg_j_target),
        .cfg_data_addr(cfg_data_addr), .cfg_data_words(cfg_data_words),
        .cfg_data_seed(cfg_data_seed), .cfg_data_sel(cfg_data_sel),
        .cmd_clear_mask(cmd_clear_mask), .cmd_load_start(cmd_load_start),
        .cmd_force_init(cmd_force_init), .cmd_start(cmd_start),
        .cfg_we(csr_cfg_we),
        .st_busy(shot_busy | load_busy | mclr_busy), .st_done_pulse(shot_done),
        .st_verify_hit(verify_hit), .st_cache_valid(cache_valid),
        .st_sat_sticky(sat_sticky), .st_too_many(too_many),
        .st_cand(shot_cand), .st_j_cur(j_cur),
        .st_cycle_cnt(cycle_cnt), .st_passes_run(passes_run)
    );
endmodule
