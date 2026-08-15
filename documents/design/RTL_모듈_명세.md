# RTL 모듈 명세 — 안에 무엇을 짜는가

> 2026-08-15. [인터페이스_계약.md](인터페이스_계약.md)가 **포트**를 정한다면 이 문서는 **본문**을 정합니다.
> 담당별로 자기 절만 읽으면 됩니다 — A는 §2, B는 §3, C는 §4, D는 §5.
> 일정은 [3주_일정표.md](3주_일정표.md), 원리의 근거는 [13장](../study_references/13_오라클_확산_측정_데이터패스.md) ·
> [14장](../study_references/14_다중정답과_최솟값탐색.md) · [16장](../study_references/16_반복제어와_재개캐시.md) · [17장](../study_references/17_RVX_SoC_통합.md)입니다.
>
> 아래 코드는 **골격**입니다. 그대로 붙여 넣어 돌아가는 코드가 아니라, 무엇을 어떤 모양으로
> 짜야 하는지와 **어디서 조용히 틀리는지**를 보여 주기 위한 것입니다.

---

## 1. 공통 코딩 규약

전원이 지킵니다. 하나만 어긋나도 통합에서 잡기 어려운 차이가 생깁니다.

| 규칙 | 이유 |
|---|---|
| **Verilog-2001 범위로 제한** (`-g2012` 로 컴파일하되 문법은 2001) | iverilog와 원격 ModelSim의 `$signed`·산술 시프트 해석 차이를 피합니다 |
| 리셋은 **동기 액티브 로우 `rstn`** 하나. 비동기 리셋 금지 | BRAM 출력 레지스터에 비동기 리셋이 안 붙습니다 |
| 순차는 `<=`, 조합 `always @*` 는 `=`. 한 `always` 에 섞지 않기 | |
| 부호 있는 연산에는 **`$signed()` 를 명시** | 폭이 섞이면 합성기가 무부호로 확장합니다 |
| 인스턴스는 **named port connection** (`.clk(clk)`) | 포트 순서가 바뀌어도 안 깨집니다 |
| 파라미터는 `` `include "grover_param.vh" `` 매크로만 사용. 숫자 리터럴 금지 | `NB`·`P` 를 바꿔 스테이징합니다 |
| 메모리는 `(* ram_style = "block" *)` 명시 | 추론이 LUTRAM으로 새면 자원이 폭발합니다 |
| `grover_top.v` 이하 어디에도 **`ervp_*.vh` include 금지** | RVX 의존성은 `grover_soc_top.v`(래퍼)에만. 깨지면 B·C·D가 원격 서버에 묶입니다 |

**핸드셰이크는 예외 없이** [인터페이스_계약 §2](인터페이스_계약.md)를 따릅니다 — `start` 는 1사이클 펄스(busy면 무시), `busy` 는 start 다음 사이클에 1이고 done과 같은 사이클에 0, `done` 은 1사이클 펄스.

---

## 2. A — 통신 · 시스템 (4개)

### 2.1 `grover_top.v` — 배선판

**하는 일**: 21개 모듈을 인스턴스화하고, 두 군데의 조정 로직을 소유합니다. 자체 연산은 없습니다.

**조정 로직 ① — `amp_mem` 주소 먹스.** 반복(`ctrl_fsm`)과 측정(`born_sampler`)이 둘 다 진폭을 읽습니다. 둘은 `shot_fsm` 이 순서를 보장해 절대 동시에 돌지 않으므로 먹스 하나면 됩니다.

```verilog
assign amp_raddr = meas_busy ? meas_addr  : iter_raddr;
assign amp_re    = meas_busy ? meas_re    : iter_re;
assign amp_waddr = iter_waddr;                          // 측정은 쓰기 경로를 안 씀
assign amp_we    = meas_busy ? 1'b0       : iter_we;    // ★ 측정은 읽기 전용
```

마지막 줄이 **재개 캐시가 성립하는 물리적 근거**입니다. 측정 중 `amp_we` 가 강제로 0이라 진폭 배열이 보존되고, 그래서 실패한 샷의 상태를 이어 쓸 수 있습니다. D의 `tb_cache_bbht.v` 가 이 신호를 감시합니다.

**조정 로직 ② — `sat_sticky` 래치.** 32레인의 `sat` 를 OR해 끈적이 비트로 남깁니다. 포화는 값을 상한에 붙일 뿐 아무 신호도 내지 않으므로, 이 비트가 없으면 정책이 발동했는지 관측할 방법이 없습니다.

```verilog
always @(posedge clk)
  if (!rstn)         sat_sticky <= 1'b0;
  else if (cmd_start) sat_sticky <= 1'b0;     // start 가 클리어
  else if (|lane_sat) sat_sticky <= 1'b1;     // 한 번 서면 유지
```

**함정**: 빈 모듈 스텁 단계에서도 `iverilog -g2012 -o /dev/null hardware/src/*.v` 가 통과해야 합니다. 포트 이름 오타는 여기서 다 걸립니다.

### 2.2 `grover_mmio.v` — APB 슬레이브 CSR

**하는 일**: APB 2상(셋업/액세스) 트랜잭션을 받아 주소를 디코드하고, 설정을 저장하고, 명령을 펄스로 바꾸고, 상태 입력 포트를 읽기 응답에 반사합니다.

**RVX 규약** — 레지스터 간격 **8바이트**(오프셋 `0x0, 0x8, 0x10, …`), `rpready` 는 상수 1(대기 없음), 미할당 주소는 `rpslverr`. 포트 이름(`rp*`)은 `lec_apb` 예제의 `test1_apb.v` 에서 그대로 베낍니다.

**세 종류의 레지스터가 각각 다르게 동작합니다.**

```verilog
wire sel = psel & penable;
wire [4:0] idx = paddr[7:3];          // 8바이트 간격 → 하위 3비트 버림

// ── ① 설정 레지스터: 저장 + 쓰기 스트로브를 밖으로 ──
always @(posedge clk)
  if (!rstn)                       r_thr_a <= 16'd0;
  else if (sel & pwrite & (idx==IDX_THR_A)) r_thr_a <= pwdata[15:0];
assign we_thr_a = sel & pwrite & (idx==IDX_THR_A);   // ★ 반드시 포트로 내보낼 것

// ── ② 명령 레지스터: 저장 공간 없음. 쓰는 행위 자체가 명령 ──
assign cmd_start = sel & pwrite & (idx==IDX_START);  // 1사이클 펄스, 읽으면 0

// ── ③ 상태 레지스터: 저장하지 않고 입력 포트를 그대로 반사 ──
always @* case (idx)
  IDX_STATUS : prdata = {26'd0, st_too_many, st_sat_sticky,
                         st_cache_valid, st_verify_hit, st_done, st_busy};
  IDX_CAND   : prdata = {17'd0, st_cand};
  ...
endcase
```

**캐시 무효화 배선 — 이 모듈의 존재 이유 절반입니다.**

```verilog
assign cfg_we = we_mode | we_thr_a | we_thr_b | we_n_qubits | we_enum_mode
              | we_data_addr | we_data_words | we_data_seed | we_data_sel
              | cmd_clear_mask | cmd_load_start;
```

게이트 몇 개짜리 OR가 "낡은 진폭 위에 새 오라클이 얹혀 조용히 틀린 답이 나오는" 버그를 통째로 없앱니다.

**함정 둘.** ① 예제의 **생성된** MMIO 블록은 설정 레지스터의 `we` 를 모듈 안에 가둬 둡니다. 생성기를 쓰려면 입력 XML에서 스트로브를 내보내게 해야 하는데 스키마가 미확인이라, **수기 작성이 기본안**입니다(100줄). ② `start` 펄스가 `done`·`verify_hit`·`cycle_cnt`·`passes_run` 을 **같이 클리어**해야 합니다. 안 그러면 폴링이 직전 실행의 `done=1` 을 보고 통과해 낡은 `cand` 를 읽습니다.

**검증** — `tb_grover_csr.v`: 전 레지스터 write-read 라운드트립 + ● 레지스터 쓰기 하나하나가 `cache_valid` 를 내리는지.

### 2.3 `grover_ahb_master.v` — INCR16 버스트 DMA

**하는 일**: SoC 시스템 SRAM의 배열을 `data_mem` 으로 옮깁니다. $n=15$ 면 64 KB = 32비트 워드 16,384개 = **INCR16 버스트 1,024개**.

**AHB 규약** — 주소 위상과 데이터 위상이 한 사이클 어긋나 파이프라인됩니다. 버스트 첫 전송은 `HTRANS=NONSEQ`, 나머지 15개는 `SEQ`, 소비 쪽이 못 받으면 `BUSY` 를 실어 버스트를 끊지 않고 기다립니다.

```verilog
localparam HT_IDLE=2'b00, HT_BUSY=2'b01, HT_NONSEQ=2'b10, HT_SEQ=2'b11;
// HBURST = 3'b111 (INCR16), HSIZE = 3'b010 (4바이트), HWRITE = 0

S_IDLE  : load_start 펄스 → 주소·남은워드 래치, S_REQ
S_REQ   : hbusreq=1, hgrant 대기
S_ADDR  : haddr=cur, htrans=NONSEQ, beat=0
S_BURST : 매 사이클 haddr += 4, htrans=SEQ, beat++
          hready 로 hrdata 수령 → 32비트를 16비트 두 칸으로 쪼개 data_mem 기록
          beat==15 → 다음 버스트 or 완료
S_DONE  : load_done 펄스
```

**함정 셋.** ① **32비트 한 전송 = 16비트 데이터 두 칸**입니다. 엔디안(하위 16비트가 짝수 인덱스인가)을 골든과 맞추십시오 — 어긋나면 데이터가 통째로 뒤섞입니다. ② **워드 수는 16의 배수**여야 버스트가 안 끊깁니다($N/2$ 는 $n\ge5$ 면 자연히 만족하지만 규약으로 검사). ③ 적재 중에는 `busy` 가 서고 `start` 펄스를 **무시**합니다. 절반만 채워진 `data_mem` 위에서 오라클을 돌리면 아무 경고 없이 틀린 답이 나옵니다.

**검증** — `tb_ahb_load.v`: 가짜 AHB 슬레이브에서 64 KB를 옮긴 뒤 `data_mem` 전 워드 일치.

### 2.4 `grover_data_gen.v` — 곱셈 없는 데이터 생성기

**하는 일**: 시드 하나로 `data_mem` 을 채웁니다. 호스트와 SRAM을 아예 건너뛰므로 벤치마크가 훨씬 빠르고, 시드가 같으면 배열이 같아 재현성도 확보됩니다.

```verilog
// xorshift32 — 시프트와 XOR 만. 사이클당 32비트 = 데이터 두 칸
always @(posedge clk) if (step) begin
  x <= x3;
end
wire [31:0] x1 = x  ^ (x  << 13);
wire [31:0] x2 = x1 ^ (x1 >> 17);
wire [31:0] x3 = x2 ^ (x2 <<  5);
```

**함정**: 선형 합동 생성기(LCG)를 쓰지 마십시오. 32비트 곱셈이 Spartan-7의 DSP48 하나에 안 들어가 여러 개가 잡히고, 그러면 "확산·오라클·INIT 경로 DSP 0개"라는 점검 기준이 흐려집니다.

**검증** — 같은 시드에서 골든과 **비트 동일 수열**, 합성 시 이 모듈 DSP 0개.

---

## 3. B — 오라클 · 술어 (3개)

### 3.1 `grover_predicate.v` — 이 프로젝트의 주제 그 자체

**하는 일**: `data_mem` 한 칸을 보고 술어를 만족하는지 판정합니다. **정답이 어디 있는지 아는 회로가 아닙니다.** 조합논리이고 레지스터가 없습니다.

**핵심 통찰**: 비교기 IP를 부를 필요가 없습니다. **비교는 뺄셈의 부호비트 하나**입니다. 그리고 `GT` 는 피연산자를 바꿔 넣기만 하면 되므로 공짜이고, `RANGE` 의 하한 검사가 `GT` 와 **완전히 같은 식**이라 감산기 하나를 셋이 나눠 씁니다.

```verilog
`include "grover_param.vh"

module grover_predicate (
  input        [1:0]           mode,
  input signed [`GP_W-1:0]     value, thr_a, thr_b,
  input                        found,
  output                       hit
);
  localparam M_LT=2'b00, M_GT=2'b01, M_EQ=2'b10, M_RG=2'b11;

  // ★ 17비트 부호확장. 이 세 줄이 없으면 value=-32768, thr_a=1 에서 뺄셈이
  //   오버플로해 부호비트가 뒤집히고, 회로가 아무 경고 없이 틀립니다.
  wire signed [`GP_W:0] v = {value[`GP_W-1], value};
  wire signed [`GP_W:0] a = {thr_a[`GP_W-1], thr_a};
  wire signed [`GP_W:0] b = {thr_b[`GP_W-1], thr_b};

  // 감산기 1 — LT 는 (v−a), GT 와 RANGE 하한은 (a−v). 피연산자만 교환.
  wire swap = (mode == M_GT) | (mode == M_RG);
  wire signed [`GP_W:0] d1 = swap ? (a - v) : (v - a);

  // 감산기 2 — RANGE 상한 전용 (v < b)
  wire signed [`GP_W:0] d2 = v - b;

  // EQ 는 감산기조차 필요 없음. XOR 한 층 + NOR 한 층이 감산 결과 0 검사보다 짧습니다.
  wire eq_hit = ~|(value ^ thr_a);

  reg raw;
  always @* case (mode)
    M_LT : raw = d1[`GP_W];                  // v < a
    M_GT : raw = d1[`GP_W];                  // a < v   (교환됐으므로 같은 비트)
    M_EQ : raw = eq_hit;
    M_RG : raw = d1[`GP_W] & d2[`GP_W];      // a < v  &&  v < b
  endcase

  assign hit = raw & ~found;                 // 열거 모드: 이미 찾은 칸은 제외
endmodule
```

**자원**: 17비트 감산기 2개 + 16입력 XOR-NOR + 먹스. 레인당 1개이므로 **32벌**이 깔립니다.
**지연 목표**: 3 LUT 단 이내. 이 경로가 1패스의 임계 경로에 그대로 들어갑니다.

**검증** (`tb_predicate.v`) — 술어 4종 × 경계값 전수 + 무작위 10⁵개에서 `golden/predicate.py` 와 일치. 경계값 목록: `thr_a`, `thr_a±1`, `thr_b`, `thr_b±1`, `-32768`, `-32767`, `0`, `32766`, `32767`, 그리고 **부호가 교차하는 조합**. `value=-32768, thr_a=1` 케이스를 반드시 명시적으로 넣으십시오.

### 3.2 `grover_verify.v` — 고전 검증

**하는 일**: 측정이 뱉은 후보 하나로 `data_mem[cand]` 를 읽어 술어를 **다시** 판정합니다. Born 샘플링은 확률적이라 오답을 뱉을 수 있고, 이 한 칸 확인이 IP의 출력을 "틀릴 수도 있는 확률적 답"에서 "맞다고 확인된 답, 또는 아직 못 찾음"으로 바꿉니다.

**구조**: `grover_predicate` 를 **한 벌 더 인스턴스화**합니다. 오라클과 완전히 같은 식이고 적용 범위만 다릅니다 — 오라클은 N칸, 검증은 1칸.

```verilog
S_IDLE : vfy_start → one_addr <= cand;  vfy_busy <= 1;  S_READ
S_READ : (data_mem 동기 읽기 1사이클 대기)              S_JUDGE
S_JUDGE: vfy_hit <= u_pred.hit;  vfy_done <= 1;  vfy_busy <= 0;  S_IDLE
```

**함정**: `found` 입력에 `mask_mem` 의 `one_bit` 를 물려야 합니다. 열거 모드에서 이미 찾은 인덱스가 다시 나오면 검증이 **떨어뜨려야** 합니다.

**검증**: 오라클이 `hit=1` 로 표시한 인덱스는 검증도 반드시 통과 — 무작위 1,000케이스.

### 3.3 `grover_mask_mem.v` — 열거 마스크

**하는 일**: 이미 찾은 인덱스를 1비트로 기록합니다. 1024 × 32b = BRAM36 **1개**. 열거 모드에서만 쓰이고, 해 하나만 반환하는 모드에서는 통째로 뺄 수 있습니다.

**주소 나누기**: 인덱스 `i` 의 상위 10비트가 워드 주소, 하위 5비트가 그 워드 안의 비트 위치입니다. `amp_mem`·`data_mem` 의 뱅킹과 **정확히 같은 규칙**이라, 병렬 읽기 `rdata[31:0]` 이 그대로 32레인의 `found` 가 됩니다.

**세 가지 동작**

| 동작 | 사이클 | 방법 |
|---|--:|---|
| 병렬 읽기 | 1 | 포트 A, `addr` = 상위 10비트 |
| 1비트 세우기 (`set`) | **2** | **read-modify-write** — 워드를 읽어 OR한 뒤 되씀 |
| 전체 클리어 (`mclr`) | **1024** | 주소를 훑으며 0을 씀. 즉시가 아님 |

```verilog
// set: BRAM 은 비트 단위 쓰기가 안 되므로 RMW 2사이클
S_SET1 : b_addr <= set_idx[`GP_NB-1:`GP_LOGP];  // 읽기
S_SET2 : b_wdata <= b_rdata | (32'd1 << set_idx[`GP_LOGP-1:0]);  b_we <= 1;
```

**함정**: `mclr` 이 1,024사이클 걸린다는 사실을 상위(`shot_fsm`)가 알아야 합니다. `mclr_busy`/`mclr_done` 을 §1의 핸드셰이크 규약대로 내십시오 — 클리어가 끝나기 전에 라운드가 시작되면 지운 줄 알았던 비트가 남아 있습니다.

### 3.4 열거 라운드 (B가 규칙을 소유, `shot_fsm` 에 결선)

해 하나를 찾을 때마다 `found[cand] ← 1` 을 세우고, **캐시를 무효화한 뒤** 다음 라운드를 시작합니다. 마스크가 바뀌면 오라클이 바뀐 것이므로 반드시 초기화가 들어갑니다 — 그래서 **열거 모드에서는 캐시 이득이 0**입니다. 캐시는 한 라운드 안의 샷들 사이에서만 일합니다.

**검증**: 발표자료 6p 예시(N=8, `EQ` 12, 정답 {1,3,5})에서 라운드마다 $M$ 이 3→2→1→0 으로 줄고 **중복 없이** 셋 다 나옴.

---

## 4. C — 데이터패스 · 수치 (8개)

### 4.1 `grover_amp_mem.v` / `grover_data_mem.v` — 32뱅크

**하는 일**: 진폭·데이터 배열을 32뱅크로 쪼개 한 사이클에 32칸을 읽습니다.

**주소 나누기**: 인덱스의 **하위 5비트가 뱅크 번호, 상위 10비트가 뱅크 내 주소**. 사이클 $c$ 에는 32뱅크가 **모두 같은 주소 $c$** 를 읽으므로 뱅크 충돌이 원리적으로 0이고, 크로스바나 순열망이 필요 없습니다.

**★ 반드시 true dual port여야 합니다.** 데이터패스가 `PIPE_LAT = 2` 로 흐르므로 사이클 $t$ 에 주소 $c$ 를 읽으면서 동시에 주소 $c-2$ 를 되쓰고, **두 주소가 다릅니다.** 읽기/쓰기 배타 포트를 쓰면 매 사이클 충돌해 패스가 두 배로 늘어납니다. RAMB18E1은 TDP 모드에서 포트당 1024×18을 지원하므로 포트 A를 읽기, 포트 B를 쓰기로 씁니다.

```verilog
(* ram_style = "block" *) reg [`GP_DW-1:0] bank [0:`GP_DEPTH-1];

always @(posedge clk) begin          // 포트 A — 읽기
  if (re) rdata_r <= bank[raddr];
end
always @(posedge clk) begin          // 포트 B — 쓰기
  if (we) bank[waddr] <= wdata;
end
```

`data_mem` 은 포트 B를 **적재(쓰기)와 검증(1칸 읽기)이 나눠 씁니다.** 둘은 시간적으로 겹치지 않으므로(적재 중 실행 금지) 먹스 하나면 됩니다.

**함정**: `(* ram_style = "block" *)` 을 빼면 합성기가 32뱅크를 LUTRAM으로 추론해 LUT가 폭발할 수 있습니다. 리셋을 메모리 배열에 걸지 마십시오 — BRAM 추론이 깨집니다.

### 4.2 `grover_lane.v` — 레인 하나 (× 32)

**하는 일**: 1패스에서는 조건부 부호 반전, 2패스에서는 평균 중심 반사. 조합논리입니다.

```verilog
// ── 1패스: 조건부 2의 보수 부정. 곱셈도 보조 큐비트도 없습니다 ──
//    hit=0 → amp 그대로,  hit=1 → ~amp + 1 = −amp
wire signed [`GP_DW-1:0] flipped = (amp_in ^ {`GP_DW{hit}}) + hit;

// ── 2패스: 2·mean − amp. TMW(20b) 로 계산한 뒤 DW(18b) 로 대칭 포화 ──
wire signed [`GP_TMW-1:0] amp_ext = {{(`GP_TMW-`GP_DW){amp_in[`GP_DW-1]}}, amp_in};
wire signed [`GP_TMW-1:0] diff    = two_mean - amp_ext;
wire ovf_p = (diff > `GP_AMP_MAX);
wire ovf_n = (diff < `GP_AMP_MIN);
wire signed [`GP_DW-1:0] diffused = ovf_p ? `GP_AMP_MAX :
                                    ovf_n ? `GP_AMP_MIN : diff[`GP_DW-1:0];

assign amp_out  = phase ? diffused : flipped;   // amp_mem 되쓰기
assign amp_tree = flipped;                      // 1패스에서 가산 트리로
assign sat      = phase & (ovf_p | ovf_n);      // top 에서 OR → sat_sticky
```

**함정 둘.** ① `AMP_MIN` 이 컨테이너 최솟값 `-131072` 가 아니라 **`-131071`** 인 이유는 2의 보수에서 `-131072` 를 부호 반전하면 `+131072` 가 되어 18비트에 안 담기기 때문입니다. 랩어라운드로 두면 그 칸에 대해 **오라클이 조용히 항등이 됩니다.** 대칭 포화를 쓰면 부호 반전이 언제나 정확합니다. ② 2배 곱셈이 이 모듈에 없는 것이 정상입니다 — `two_mean` 이 이미 2×평균이라 시프트가 `two_mean_calc` 쪽에 들어가 있습니다.

### 4.3 `grover_adder_tree.v` — 32입력 5단

**하는 일**: 한 사이클에 읽은 32개 진폭을 더해 부분합 하나로 만듭니다. 조합논리입니다.

```verilog
wire signed [`GP_DW  :0] l1 [0:15];   // 19b
wire signed [`GP_DW+1:0] l2 [0: 7];   // 20b
wire signed [`GP_DW+2:0] l3 [0: 3];   // 21b
wire signed [`GP_DW+3:0] l4 [0: 1];   // 22b
genvar i;
generate
  // ★ 짝짓기 순서 고정: (0,1)(2,3)…(30,31) — 골든 tree_sum() 과 반드시 동일
  for (i=0;i<16;i=i+1) begin : g1
    assign l1[i] = $signed(din[(2*i  )*`GP_DW +: `GP_DW])
                 + $signed(din[(2*i+1)*`GP_DW +: `GP_DW]);
  end
  for (i=0;i< 8;i=i+1) begin : g2  assign l2[i] = l1[2*i] + l1[2*i+1];  end
  for (i=0;i< 4;i=i+1) begin : g3  assign l3[i] = l2[2*i] + l2[2*i+1];  end
  for (i=0;i< 2;i=i+1) begin : g4  assign l4[i] = l3[2*i] + l3[2*i+1];  end
endgenerate
assign partial = l4[0] + l4[1];       // 23b = PSW
```

**함정**: **짝짓기 순서를 문서에 적고 골든이 그대로 따라야 합니다.** 정수 덧셈은 폭이 충분하면 순서에 무관하지만, 3단 사다리의 첫 칸인 **float64 모델과 대조할 때는 결합법칙이 성립하지 않아 순서가 곧 결과**입니다. `sum += a[i]` 로 순차 누산한 파이썬과 5단 트리로 더한 RTL은 마지막 비트가 다를 수 있고, 그러면 "왜 안 맞지"로 며칠을 씁니다.

**타이밍**: 5단이 100 MHz에 안 들어가면 2단 파이프라인을 넣고 `sum_accum` 의 지연을 보정합니다. 넣으면 통합 1·2 테스트벤치를 **전부 재실행**해야 하므로 마지막 수단입니다.

### 4.4 `grover_sum_accum.v`

1패스 동안 부분합을 누적합니다. `clear` 로 0, `en` 으로 더하기.

```verilog
always @(posedge clk)
  if (!rstn || clear) total <= {`GP_ACCW{1'b0}};
  else if (en)        total <= total + {{(`GP_ACCW-`GP_PSW){partial[`GP_PSW-1]}}, partial};
```

폭 `ACCW=35` 의 근거: 진폭 크기 ≤ 2¹⁷, N = 2¹⁵ → 합 < 2³². 부호 1비트 + 여유 2비트.

### 4.5 `grover_two_mean_calc.v` — 반올림이 일어나는 유일한 곳

**하는 일**: 누산기를 $n-1$ 칸 **한 번에** 밀어 2×평균을 만듭니다.

**왜 $n-1$ 인가**: 확산이 실제로 쓰는 값은 평균이 아니라 **2×평균**입니다. $2/2^n = 1/2^{n-1}$ 이므로 $n$ 칸 시프트 후 2를 곱하는 대신 처음부터 $n-1$ 칸만 밀면 한 번에 나옵니다.

```verilog
wire [4:0] K = n_qubits - 5'd1;                        // n=15 → 14

wire signed [`GP_ACCW-1:0] q = $signed(total) >>> K;   // 산술 우시프트 = floor
wire rbit = total[K-1];                                // 버려지는 비트 중 최상위

// 그 아래에 1이 하나라도 있나 — K 가 런타임이라 마스크를 만들어 씁니다
wire [`GP_ACCW-1:0] mask = ({{(`GP_ACCW-1){1'b0}},1'b1} << (K-1)) - 1;
wire sticky = |(total & mask);

// round-half-to-even: 버려지는 부분이 정확히 절반이면 결과 LSB 가 1일 때만 올림
wire signed [`GP_ACCW-1:0] rounded = q + (rbit & (sticky | q[0]));
assign two_mean = rounded[`GP_TMW-1:0];
```

**함정 셋.** ① **`>>> n` 으로 밀었다가 `<<< 1` 로 되미는 2단 구현은 금지입니다.** 떨어져 나간 최하위 비트가 0으로 채워지고 반올림 지점이 두 곳으로 갈라져 골든 모델과 영원히 어긋납니다. ② `n_qubits` 가 런타임 가변이므로 **배럴 시프터**입니다(35비트 × 5단 ≈ 200 LUT). 상수 시프트로 짜면 `n` 을 바꿀 수 없습니다. ③ `K=0` 이면 `total[K-1]` 이 감기므로 `n_qubits >= 5` 를 전제로 두십시오(P=32 뱅킹이 이미 요구합니다).

**한 반복에서 소수부가 깎이는 곳은 여기 한 순간뿐입니다.** 오라클의 부호 반전은 정확하고, 반사의 뺄셈도 두 피연산자가 모두 Q2.16이라 정확합니다. round-half-to-even이 적용되는 자리도 오직 여기입니다.

**검증** (`tb_two_mean_calc.v`) — 무작위 `total` 10⁶개 + **tie 케이스 1,000개**(버려지는 부분이 정확히 절반, 즉 `t ≡ 2^(K-1) mod 2^K`)에서 파이썬 모델과 일치. tie를 안 넣으면 half-to-even이 틀려도 통과합니다.

### 4.6 `grover_ctrl_fsm.v` — 안쪽 반복 FSM (이 프로젝트에서 가장 까다로운 모듈)

**하는 일**: `S_INIT → (S_PASS1 → S_MEAN → S_PASS2) × Δj` 를 돌리며 주소와 인에이블을 만듭니다.

**파이프라인 정렬이 난점입니다.** BRAM 동기 읽기가 1사이클 지연되므로 3단으로 흐릅니다.

```
 t   : amp_raddr / data_addr 제시, amp_re=1
 t+1 : rdata 유효 → predicate → lane → adder_tree (전부 조합)
       lane 출력을 wdata_r 에 래치, partial 을 sum_accum 에 누적
 t+2 : amp_waddr = (t의 주소), amp_we=1 로 wdata_r 되쓰기
```

```verilog
reg [`GP_AW-1:0] ac;                 // 발행 주소
reg              issue;              // 이번 사이클에 주소를 냈나
reg [`GP_AW-1:0] ac_d1, ac_d2;
reg              v_d1, v_d2;
always @(posedge clk) begin
  ac_d1 <= ac;    ac_d2 <= ac_d1;
  v_d1  <= issue; v_d2  <= v_d1;
end

// n_qubits 가 런타임이면 뱅크 깊이도 줄어듭니다
wire [`GP_AW-1:0] depth_m1 = (1 << (n_qubits - `GP_LOGP)) - 1;

assign amp_raddr = ac;
assign amp_re    = issue & (state != S_INIT);
assign amp_waddr = (state == S_INIT) ? ac    : ac_d2;   // INIT 은 읽지 않으므로 지연 없음
assign amp_we    = (state == S_INIT) ? issue : v_d2;
assign data_addr = ac;
assign acc_en    = v_d1 & (state == S_PASS1);           // 누적은 t+1
```

**상태 전이**

| 상태 | 길이 | 하는 일 | 다음 |
|---|--:|---|---|
| `S_IDLE` | — | `iter_start` 대기 | `do_init ? S_INIT : S_PASS1` |
| `S_INIT` | `DEPTH` | 전 칸에 `init_amp` 기입 (§4.7) | `Δj==0 ? S_FIN : S_PASS1` |
| `S_PASS1` | `DEPTH + 2` | 술어 판정 · 부호 반전 · 되쓰기 · **동시에 누산** | `S_MEAN` |
| `S_MEAN` | 1 | `two_mean` 확정 (조합, 래치만) | `S_PASS2` |
| `S_PASS2` | `DEPTH + 2` | `2·mean − amp` 되쓰기 | `--Δj>0 ? S_PASS1 : S_FIN` |
| `S_FIN` | 1 | `iter_done` 펄스, `iter_busy` 하강 | `S_IDLE` |

**초기 진폭은 상수가 아니라 함수입니다.** `n_qubits` 가 런타임 가변이므로 `S_INIT` 이 쓰는 값을 매번 계산합니다.

```verilog
wire [4:0] sh = n_qubits[0] ? ((n_qubits - 5'd1) >> 1) : (n_qubits >> 1);
wire signed [`GP_DW-1:0] init_amp =
     n_qubits[0] ? (`GP_INV_SQRT2_Q216 >>> sh)   // 홀수 n — 1/√2 분기
                 : (`GP_ONE_Q216       >>> sh);  // 짝수 n — 정확
```

$n=15$ 면 `46341 >> 7 = 362` 입니다. 제곱근기가 통째로 사라지는 것은 $N = 2^n$ 이라는 사실 덕분입니다.

**함정 셋.** ① `pass_tick` 을 패스마다 한 번 내야 D의 `passes_run` 이 셉니다. ② 반복 1회는 2,048이 아니라 **`2·(DEPTH+2)+1 = 2,053`** 사이클입니다. 테스트벤치 assert에 2,048을 박지 말고 `2*DEPTH + ITER_OVH` 로 쓰고, 확정된 `ITER_OVH` 를 [인터페이스_계약 §6.3](인터페이스_계약.md)에 되적으십시오. ③ 1차 검증 기준은 사이클 단위 비교가 아니라 **패스 종료 시점의 배열 전체 비교**입니다. 파이프라인이 한 칸 어긋나도 최종 배열은 맞을 수 있고, 반대로 배열이 틀리면 무조건 실패입니다.

### 4.7 `grover_born_sampler.v` — 2단 병렬 측정

**하는 일**: 진폭 제곱에 비례하는 확률로 인덱스 하나를 뽑습니다. **인덱스 순서가 무관**하다는 성질을 이용해 뱅크를 먼저 고르고 그 안에서 칸을 고릅니다.

**왜 분포가 안 바뀌나**: 인덱스 $i$ 가 뱅크 $b$ 에 속할 때 이 절차가 $i$ 를 뽑을 확률은 두 단의 곱 `(S_b/total) × (a_i²/S_b) = a_i²/total` 로 뱅크 합이 약분됩니다. 더 근본적으로는 역변환 샘플링이 순회 순서에 무관합니다.

| 단계 | 사이클 | 하는 일 |
|---|--:|---|
| `S_P1` | `DEPTH+2` | 32뱅크 동시 읽기 → 제곱기 32개 → 뱅크별 누산 `S[0..31]`(46b) |
| `S_ACC` | 32 | 누적합 `C[b] = C[b-1] + S[b]` 저장, `total = C[31]`(51b) |
| `S_RND` | 2~4 | 기각 샘플링으로 `r ∈ [0, total)` 균등 추출 |
| `S_SEL` | 32 | `C[b] > r` 인 첫 뱅크 `b*`, 잔차 `r' = r − C[b*−1]` |
| `S_P2` | `DEPTH+2` | `b*` 뱅크만 스캔, 제곱 누적이 `r'` 를 처음 넘는 주소 |
| `S_DONE` | 1 | `cand = {addr, b*}` |

```verilog
// ── 제곱기 32개 = 이 IP 전체에서 DSP 를 쓰는 유일한 곳 (DSP 32/120) ──
genvar i;
generate for (i=0;i<`GP_P;i=i+1) begin : g_sq
  wire signed [`GP_DW-1:0] a = $signed(amp_rdata[i*`GP_DW +: `GP_DW]);
  wire [`GP_SQW-1:0] sq = a * a;                  // 36b, ★ 자르지 말 것
  always @(posedge clk)
    if (p1_clear)   S[i] <= 0;
    else if (p1_en) S[i] <= S[i] + sq;            // 46b
end endgenerate

// ── 기각 샘플링: total 의 최상위 1 위치 +1 비트만 뽑아 재시도율을 절반 이하로 ──
// rw = msb_index(total) + 1;  r = lfsr[rw-1:0];  accept if (r < total) else 재추출
```

**안전망 2줄이 필수입니다.**

```verilog
if (sel_done_without_cross)  bstar <= 5'd31;      // prefix-sum 이 r 을 못 넘음
if (scan_reached_end)        cand  <= last_index; // 스캔이 배열 끝에 닿음
```

초기 진폭의 반올림 때문에 노름이 정확히 1이 아니라(홀수 $n$ 에서 0.99989) 난수를 끝까지 못 넘을 수 있습니다. 이 두 줄이 없으면 FSM이 배열 끝에서 멈추지 못하고 **매달립니다.** 확률적으로는 거의 일어나지 않지만, "거의"에 회로를 걸어 둘 수는 없습니다.

**함정 셋.** ① **36비트 제곱을 자르지 마십시오.** 잘린 하위 비트가 곧 확률 왜곡이고, 값이 작은 칸일수록 상대 오차가 커져 분포가 체계적으로 기웁니다. ② 누산기 폭이 확산 경로의 `ACCW=35` 와 **완전히 별개**입니다. 재는 대상이 진폭의 합이 아니라 진폭 제곱의 합이라 자릿수 계산이 처음부터 다릅니다(`MACCW=46`, `TOTW=51`). ③ 난수 소비 개수를 D의 규약과 **정확히** 맞추십시오 — 기각이 일어났을 때 몇 개를 쓰는지까지 포함해서. 어긋나면 골든과 영원히 비트정확이 안 됩니다.

**검증** (`tb_born_dist.v`) — n=10, 고정 amp 배열로 10⁵ 샘플 → 이론 분포 대비 **χ² p > 0.01**. 그리고 **패스 1도 패스 2도 `amp_mem` 을 읽기만 하는지** 확인하십시오. 이 읽기 전용 성질이 재개 캐시의 근거입니다.

---

## 5. D — 캐시 · 반복 제어 (5개)

### 5.1 `grover_lfsr.v` — 난수원

**하는 일**: `j` 추첨과 측정 문턱값에 쓸 난수를 냅니다. 진폭마다 뽑는 것이 아니라 **샷당 몇 번**뿐이라 비용이 사실상 없습니다.

```verilog
always @(posedge clk)
  if (!rstn)        x <= SEED_DEFAULT;
  else if (seed_we) x <= seed;
  else if (draw)    x <= next(x);       // 다항식은 §계약 9 에서 확정
assign rnd = x;
```

**함정**: **다항식·시드·추출 순서를 문서에 못 박고 골든이 그대로 따라야 합니다.** 이것이 다르면 골든 모델과 RTL이 영원히 bit-exact가 되지 않습니다. 특히 `j ~ U[0,m)` 을 만들 때 **LFSR 출력을 마스킹만 하면 `m` 이 2의 거듭제곱이 아닐 때 균등하지 않습니다.** BBHT의 "성공 확률 ≥ 1/4" 보장이 균등성을 전제하므로 기각 샘플링 같은 규약이 필요하고, **기각이 일어났을 때 소비하는 난수 개수까지** 골든이 똑같이 세야 합니다.

### 5.2 `grover_iter_rom.v` — m 수열 30항

**하는 일**: BBHT의 $m \leftarrow \min(1.2m, \sqrt N)$ 을 실시간 산술 대신 구워 둔 표에서 읽습니다.

**왜 ROM인가**: 1.2배는 시프트로 떨어지지 않고, 클램프 $\sqrt N = 181.02$ 도 2의 거듭제곱이 아닙니다. $n=15$ 에서 항이 **30개**뿐이라($n=12$ 면 24항) LUT 몇 개면 들어갑니다.

```verilog
always @* case (idx)
  5'd0 : m_val = 16'd1;
  5'd1 : m_val = 16'd1;      // floor(1.2×1) = 1
  5'd2 : m_val = 16'd1;
  ...                         // 골든 m_rom() 이 뽑은 수열을 그대로 굽습니다
  default: m_val = 16'd181;   // √32768 클램프
endcase
```

**함정**: 골든의 `m_rom()` 과 **전 항이 일치**해야 합니다. 반올림 방향(floor인가 round인가) 하나로 수열 전체가 밀립니다.

### 5.3 `grover_cache_ctrl.v` — 이 프로젝트의 핵심 기여

**하는 일**: 이번 샷이 초기화부터 돌지, 차이만큼만 이어 돌지 판정합니다.

**자원: 레지스터 두 개가 전부입니다. BRAM 0개.** 진폭 배열의 사본을 뜨는 것이 아니라, 이미 거기 있는 배열을 **지우지 않는** 것이기 때문입니다.

```verilog
// ── 판정 (조합) ──
wire do_init = (~cache_valid) | force_init | (j_req < j_cur);
wire [15:0] delta_j = do_init ? j_req : (j_req - j_cur);

// ── 상태 (레지스터 둘) ──
always @(posedge clk) begin
  if (!rstn) begin
    j_cur <= 16'd0;  cache_valid <= 1'b0;
  end else begin
    if (cfg_we)         cache_valid <= 1'b0;      // ★ 하드웨어 자동 무효화
    else if (iter_done) begin
      j_cur <= j_req_latched;  cache_valid <= 1'b1;
    end
  end
end
```

**왜 이게 같은 알고리즘인가**: 그로버 한 바퀴를 $G = D\cdot O$ 라 쓰면 재개 경로가 만드는 연산열은 $(DO)^{j_{target}} = (DO)^{j_{target}-j_{cur}}\cdot(DO)^{j_{cur}}$ 이고, 유니터리의 곱은 결합적이라 어디서 끊어 읽든 순효과가 같습니다. 우리 산술이 결정적이므로(round-half-to-even, 포화 지점과 누산 순서 고정) 결과는 근사적으로가 아니라 **비트 단위로 동일**합니다. 측정 난수는 샷마다 새로 뽑으므로 각 샷은 여전히 독립 시행이고 BBHT 통계도 그대로입니다.

**함정 셋.** ① **되감기를 넣지 마십시오.** `j_req < j_cur` 이면 뒤로 감는 대신 INIT부터 다시 합니다 — 실측상 되감기가 오히려 1% 느리고($j$ 가 절반 넘게 줄어드는 경우가 흔해 INIT 후 전진이 더 쌉니다) 고정소수점에서 $OD$ 는 $DO$ 의 정확한 역이 아니라 가역성 증명 부담이 붙습니다. ② **무효화를 소프트웨어에 맡기지 마십시오.** `cfg_we` 는 A의 CSR 주소 디코드에서 공짜로 나오는 신호입니다. 펌웨어에 맡기면 나중에 술어를 하나 더 추가한 사람이 빼먹는 순간 낡은 진폭 위에 새 오라클이 얹혀 **조용히 틀린 답**이 나옵니다. ③ `j_cur` 갱신은 `iter_done` 에서만 합니다. 중간에 갱신하면 실행이 중단됐을 때 상태가 거짓말을 합니다.

**검증**: 데이터패스 없이 단독 tb로 다섯 경우를 전수 확인 — 무효 상태 / `force_init` / `j_req < j_cur` / `j_req >= j_cur` / `cfg_we` 무효화. **C를 기다리지 마십시오.**

### 5.4 `grover_shot_fsm.v` — 바깥 샷 루프

**하는 일**: `m` 갱신, `j` 추첨, 캐시 판정, 반복·측정·검증 기동, 재시도, 열거 라운드까지 전부. 펌웨어가 보는 것은 "설정 → `start` → 폴링 → 결과 읽기" 네 줄뿐입니다.

| 상태 | 하는 일 | 다음 |
|---|---|---|
| `S_IDLE` | `start` 대기 | `S_SETUP` |
| `S_SETUP` | `m ← 1`, `shots ← 0`, 카운터 클리어 | `S_DRAW` |
| `S_DRAW` | `j_req = auto_shot ? U[0,m) : cfg_j_target` | `S_CACHE` |
| `S_CACHE` | `cache_ctrl` 의 `do_init`·`delta_j` 래치 | `S_ITER` |
| `S_ITER` | `iter_start` 펄스 → `iter_done` 대기 | `S_MEAS` |
| `S_MEAS` | `meas_start` → `meas_done`, `cand` 수령 | `S_VFY` |
| `S_VFY` | `vfy_start` → `vfy_done` | `S_JUDGE` |
| `S_JUDGE` | `vfy_hit` ? `S_HIT` : (`m` 갱신, `shots++`, 상한 검사) | `S_DRAW` / `S_MISS` |
| `S_HIT` | 열거면 `mask_set`, `m ← 1` 후 `S_DRAW`; 아니면 종료 | `S_DRAW` / `S_DONE` |
| `S_MISS` | `shots == shot_cap` — `verify_hit=0` 으로 종료 | `S_DONE` |
| `S_DONE` | `done` 펄스, `busy` 하강 | `S_IDLE` |

**두 모드가 한 FSM에 들어갑니다.** `auto_shot=1` 이면 LFSR이 매 샷 `j_req` 를 뽑고, `auto_shot=0` 이면 앱이 CSR에 쓴 절대값을 그대로 씁니다. **CSR `j_target` 레지스터를 하드웨어가 되쓰지 않습니다** — 생성된 MMIO의 설정 레지스터는 APB 쓰기로만 바뀌므로 IP가 거꾸로 쓸 포트가 없고, 먹스 하나로 정리하는 편이 맞습니다.

```verilog
wire [15:0] j_req = auto_shot ? lfsr_draw_in_range : cfg_j_target;
```

**카운터 둘을 반드시 갈라 셉니다.**

```verilog
always @(posedge clk) begin
  if (start)              begin cycle_cnt <= 0; passes_run <= 0; end
  else if (busy)          cycle_cnt  <= cycle_cnt + 1;        // 벽시계
  if (pass_tick)          passes_run <= passes_run + 1;       // 알고리즘 지표
end
```

재개 캐시는 **벽시계만 줄이고 알고리즘 지표는 줄이지 않습니다.** 이걸 섞어 "그로버 반복을 35% 줄였다"고 쓰면 거짓말이 됩니다 — 줄어든 것은 에뮬레이션 시간이지 알고리즘이 오라클에 던진 질의 횟수가 아닙니다. 카운터를 둘 두는 이유가 이것입니다.

**함정**: `shot_cap` 이 없으면 $M=0$ 일 때 **영원히 끝나지 않습니다.** BBHT는 정답이 없으면 원리적으로 종료하지 않고, 그러면 펌웨어의 폴링도 호스트의 대기도 같이 매답니다. 종료 조건 자체는 미정이지만(고전 스캔 1패스 vs 상한 도달), **상한 레지스터는 지금 넣어 두십시오.**

**검증**: 자율 모드가 같은 seed에서 펌웨어 구동 모드와 **동일한 `j_target` 수열**을 만들고 샷 수·`cand` 가 일치.

### 5.5 `grover_result_fifo.v` — 열거 결과 큐

`push`/`idx` 로 넣고 `dout`/`count`/`empty`/`full`. 깊이가 곧 `M_max` 입니다.

**미정과 묶여 있습니다.** 이 FIFO를 두면 깊이만큼 하드웨어 비용이 붙고, 안 두면 라운드마다 펌웨어가 읽어 가면 됩니다(왕복은 늘지만 공짜). **3주 일정에서는 가장 먼저 잘라도 되는 모듈**이라 마지막에 짜십시오.

---

## 6. 무엇을 먼저 짜는가 — 난이도와 의존 순서

| 순위 | 모듈 | 난이도 | 왜 이 순서인가 |
|:-:|---|:-:|---|
| 1 | `grover_predicate` (B) | 낮음 | 조합논리. 첫날에 끝나고 tb도 진리표라 명확 |
| 1 | `grover_lfsr`·`grover_iter_rom` (D) | 낮음 | 골든 수열과 대조만 하면 끝 |
| 1 | `grover_param.vh`·`sum_accum`·`adder_tree` (C) | 낮음 | 폭 계산만 맞으면 됨 |
| 2 | `grover_two_mean_calc` (C) | **중** | 배럴 시프터 + half-to-even. tie 테스트가 관문 |
| 2 | `grover_cache_ctrl` (D) | 낮음 | 규칙 3줄. 단독 tb로 전수 검증 가능 |
| 2 | `grover_lane` (C) | 낮음 | 조합. 대칭 포화만 조심 |
| 3 | `grover_amp_mem`·`data_mem` (C) | 중 | TDP 추론이 제대로 되는지 합성 리포트로 확인 |
| 3 | `grover_mmio` (A) | 중 | 세 종류 레지스터의 시맨틱 차이 |
| 4 | **`grover_ctrl_fsm` (C)** | **높음** | 파이프라인 정렬. 이 프로젝트에서 가장 어려운 모듈 |
| 4 | `grover_verify`·`mask_mem` (B) | 중 | RMW 2사이클, 클리어 1024사이클 |
| 5 | **`grover_born_sampler` (C)** | **높음** | 5단 FSM + 46/51비트 누산 + 기각 샘플링 + 안전망 |
| 5 | **`grover_shot_fsm` (D)** | **높음** | 10상태. 두 모드와 열거 라운드가 겹침 |
| 6 | `grover_ahb_master` (A) | 높음 | AHB 파이프라인. 가장 RVX 의존적 |
| 7 | `grover_data_gen`·`result_fifo` | 낮음 | 곁가지. 마지막 |

**어려운 셋이 서로 다른 사람에게 갈라져 있는 것이 이 분담의 의도입니다.** `ctrl_fsm`(C) · `born_sampler`(C) · `shot_fsm`(D) 중 앞의 둘이 같은 사람이라 C의 3주차가 가장 빡빡하고, 밀리면 [3주_일정표 §6](3주_일정표.md)의 조정 밸브 3번(측정을 직렬 CDF로 임시 구현)이 먼저 발동합니다.
