//==============================================================================
// bbht_dataset_gen.v -- LPSoC BBHT/Grover standalone dataset generator
//
// bbht_ahb_loader.v 의 드롭인 대체품.  AHB 마스터로 SoC SRAM에서 데이터셋을
// 끌어오는 대신, 같은 데이터셋을 IP 안에서 직접 생성한다.  RVX SoC / 시스템
// SRAM / AHB 인터커넥트 / RISC-V 펌웨어 없이도 동작한다.
//
// Main-IP 쪽 핸드셰이크는 bbht_ahb_loader와 완전히 동일하다:
//   gen_start 펄스 -> load_start 1사이클 펄스 -> load_busy 대기
//                  -> data_wr_en 스트림 -> load_done 1사이클 펄스
//
//------------------------------------------------------------------------------
// 재현 대상 (main_clean.c, k4h4_clean_performance_final_20260904)
//------------------------------------------------------------------------------
// 1) 배경:  state = BACKGROUND_SEED (0x5EED1234)
//           for i in 0..DATA_COUNT-1:
//               value = xorshift32(&state) & 0xFFFF
//               if (value == TARGET_VALUE) value ^= 1
//               data[i] = value
//
// 2) 타깃:  state = TARGET_POS_SEED (0xA17E2026) 로 인덱스를 뽑되 중복 제거.
//           소프트웨어는 런타임에 O(n^2) 선형 탐색으로 중복을 걸렀지만,
//           그 결과는 시드가 고정이므로 결정적인 256개 목록이다.  여기서는
//           그 목록을 ROM으로 굽는다 (추첨 257회 중 충돌 1회로 확인됨).
//           for t in 0..target_count-1:
//               data[TARGET_ROM[t]] = TARGET_VALUE
//
//    타깃 집합은 중첩이다: 1 ⊂ 4 ⊂ 16 ⊂ 64 ⊂ 256.  target_count만 바꾸면
//    소프트웨어의 누적 적용과 동일한 배열이 나온다.
//
//------------------------------------------------------------------------------
// 골든 체크섬 (FNV-1a over 8192 x 32bit words, main_clean.c dataset_checksum())
//------------------------------------------------------------------------------
//   targets=  0 (배경만)  0x25FC125D
//   targets=  1           0x673F125D
//   targets=  4           0x65A0846E
//   targets= 16           0x3FBAFF29
//   targets= 64           0x72B6D504
//   targets=256           0x71B6FE37
//
//   data[0..7] = 24641 18286 20182 26047 35495 1497 44543 57376
//
//------------------------------------------------------------------------------
// 초과 쓰기에 대하여
//------------------------------------------------------------------------------
// 배경 DATA_COUNT회 + 타깃 target_count회 = 최대 16,640회를 쓰지만,
// grover_loader_ctrl 이 "duplicate addresses still count / saturate exactly at
// expected_count so extra accepted writes cannot overflow" 규약을 명시하고
// mem_wr_en = valid_write 로 초과 쓰기도 data_mem에 그대로 전달하므로,
// 2단계 방식이 별도 비트맵 없이 성립한다.  (RTL에서 확인함, 추정 아님)
//==============================================================================
`timescale 1ns/1ps

module bbht_dataset_gen #(
    parameter [31:0] BACKGROUND_SEED = 32'h5EED_1234,
    parameter [15:0] TARGET_VALUE    = 16'd12345,
    parameter integer MAX_TARGETS     = 256
) (
    input  wire               clk,
    input  wire               rstnn,

    // ---------------- CSR ----------------
    input  wire [14:0]        data_count,     // 1..16384
    input  wire [8:0]         target_count,   // 0..256
    input  wire               gen_start,      // 1-cycle pulse

    output wire               gen_busy,
    output wire               gen_error,
    output wire [4:0]         gen_error_bits, // {range, busy, resv, count, resv}

    // ------- Main IP dataset loader -------
    output wire               load_start,
    output wire               data_wr_en,
    output wire [13:0]        data_wr_addr,
    output wire signed [15:0] data_wr_data,
    output wire               load_done,
    input  wire               load_busy,
    input  wire               main_busy
);

    localparam [14:0] COUNT_MAX = 15'd16384;

    localparam [2:0] S_IDLE      = 3'd0,
                     S_WAIT_BUSY = 3'd1,
                     S_BG        = 3'd2,
                     S_TGT       = 3'd3,
                     S_FIN       = 3'd4;

    reg [2:0]  st;
    reg [31:0] lfsr_q;
    reg [14:0] n_q;         // latched data_count
    reg [8:0]  t_q;         // latched target_count
    reg [14:0] cnt_q;       // background index
    reg [8:0]  tcnt_q;      // target index

    reg        ld_start_q;
    reg        ld_done_q;
    reg        wr_en_q;
    reg [13:0] wr_addr_q;
    reg signed [15:0] wr_data_q;

    reg        e_count;
    reg        e_busy;
    reg        e_range;

    //--------------------------------------------------------------------------
    // Target index ROM -- 256 entries, 14-bit.
    // Derived from TARGET_POS_SEED = 0xA17E2026 with duplicate rejection.
    // Verified: 256 entries, 0 duplicates, max index 16297.
    //--------------------------------------------------------------------------
    reg [13:0] rom [0:MAX_TARGETS-1];

    initial begin
        rom[  0] = 14'd507  ; rom[  1] = 14'd4724 ; rom[  2] = 14'd2852 ; rom[  3] = 14'd8685 ;
        rom[  4] = 14'd4512 ; rom[  5] = 14'd10593; rom[  6] = 14'd7786 ; rom[  7] = 14'd15288;
        rom[  8] = 14'd491  ; rom[  9] = 14'd10839; rom[ 10] = 14'd1801 ; rom[ 11] = 14'd10931;
        rom[ 12] = 14'd5281 ; rom[ 13] = 14'd1721 ; rom[ 14] = 14'd14405; rom[ 15] = 14'd3947 ;
        rom[ 16] = 14'd14567; rom[ 17] = 14'd16090; rom[ 18] = 14'd682  ; rom[ 19] = 14'd8799 ;
        rom[ 20] = 14'd1038 ; rom[ 21] = 14'd14568; rom[ 22] = 14'd5200 ; rom[ 23] = 14'd160  ;
        rom[ 24] = 14'd12075; rom[ 25] = 14'd2888 ; rom[ 26] = 14'd5531 ; rom[ 27] = 14'd1825 ;
        rom[ 28] = 14'd11647; rom[ 29] = 14'd15469; rom[ 30] = 14'd14689; rom[ 31] = 14'd5270 ;
        rom[ 32] = 14'd8225 ; rom[ 33] = 14'd4362 ; rom[ 34] = 14'd11272; rom[ 35] = 14'd9302 ;
        rom[ 36] = 14'd14494; rom[ 37] = 14'd14542; rom[ 38] = 14'd3903 ; rom[ 39] = 14'd13048;
        rom[ 40] = 14'd7012 ; rom[ 41] = 14'd13012; rom[ 42] = 14'd534  ; rom[ 43] = 14'd4720 ;
        rom[ 44] = 14'd7400 ; rom[ 45] = 14'd10812; rom[ 46] = 14'd26   ; rom[ 47] = 14'd7247 ;
        rom[ 48] = 14'd4876 ; rom[ 49] = 14'd6247 ; rom[ 50] = 14'd586  ; rom[ 51] = 14'd8089 ;
        rom[ 52] = 14'd2335 ; rom[ 53] = 14'd3073 ; rom[ 54] = 14'd9927 ; rom[ 55] = 14'd3619 ;
        rom[ 56] = 14'd12001; rom[ 57] = 14'd15586; rom[ 58] = 14'd173  ; rom[ 59] = 14'd10234;
        rom[ 60] = 14'd5341 ; rom[ 61] = 14'd3304 ; rom[ 62] = 14'd3876 ; rom[ 63] = 14'd701  ;
        rom[ 64] = 14'd309  ; rom[ 65] = 14'd4269 ; rom[ 66] = 14'd7188 ; rom[ 67] = 14'd4956 ;
        rom[ 68] = 14'd15233; rom[ 69] = 14'd1640 ; rom[ 70] = 14'd12785; rom[ 71] = 14'd135  ;
        rom[ 72] = 14'd10365; rom[ 73] = 14'd15445; rom[ 74] = 14'd11990; rom[ 75] = 14'd11230;
        rom[ 76] = 14'd9501 ; rom[ 77] = 14'd8272 ; rom[ 78] = 14'd894  ; rom[ 79] = 14'd6194 ;
        rom[ 80] = 14'd9916 ; rom[ 81] = 14'd5681 ; rom[ 82] = 14'd1290 ; rom[ 83] = 14'd8189 ;
        rom[ 84] = 14'd10532; rom[ 85] = 14'd1930 ; rom[ 86] = 14'd7401 ; rom[ 87] = 14'd90   ;
        rom[ 88] = 14'd15374; rom[ 89] = 14'd2442 ; rom[ 90] = 14'd13107; rom[ 91] = 14'd9960 ;
        rom[ 92] = 14'd56   ; rom[ 93] = 14'd3661 ; rom[ 94] = 14'd807  ; rom[ 95] = 14'd3288 ;
        rom[ 96] = 14'd13749; rom[ 97] = 14'd10434; rom[ 98] = 14'd730  ; rom[ 99] = 14'd5948 ;
        rom[100] = 14'd333  ; rom[101] = 14'd533  ; rom[102] = 14'd629  ; rom[103] = 14'd15727;
        rom[104] = 14'd13221; rom[105] = 14'd1456 ; rom[106] = 14'd1393 ; rom[107] = 14'd6733 ;
        rom[108] = 14'd11907; rom[109] = 14'd5574 ; rom[110] = 14'd8252 ; rom[111] = 14'd9984 ;
        rom[112] = 14'd604  ; rom[113] = 14'd2302 ; rom[114] = 14'd10725; rom[115] = 14'd13232;
        rom[116] = 14'd2726 ; rom[117] = 14'd14410; rom[118] = 14'd1815 ; rom[119] = 14'd15464;
        rom[120] = 14'd2360 ; rom[121] = 14'd3335 ; rom[122] = 14'd411  ; rom[123] = 14'd12675;
        rom[124] = 14'd1939 ; rom[125] = 14'd2993 ; rom[126] = 14'd13239; rom[127] = 14'd4803 ;
        rom[128] = 14'd5387 ; rom[129] = 14'd6702 ; rom[130] = 14'd7091 ; rom[131] = 14'd7615 ;
        rom[132] = 14'd3237 ; rom[133] = 14'd16297; rom[134] = 14'd12629; rom[135] = 14'd9756 ;
        rom[136] = 14'd4389 ; rom[137] = 14'd12680; rom[138] = 14'd11383; rom[139] = 14'd11476;
        rom[140] = 14'd10964; rom[141] = 14'd8851 ; rom[142] = 14'd314  ; rom[143] = 14'd11256;
        rom[144] = 14'd1558 ; rom[145] = 14'd13968; rom[146] = 14'd10113; rom[147] = 14'd3545 ;
        rom[148] = 14'd3789 ; rom[149] = 14'd12535; rom[150] = 14'd10073; rom[151] = 14'd9972 ;
        rom[152] = 14'd3716 ; rom[153] = 14'd14992; rom[154] = 14'd10195; rom[155] = 14'd7780 ;
        rom[156] = 14'd7165 ; rom[157] = 14'd7326 ; rom[158] = 14'd8303 ; rom[159] = 14'd3061 ;
        rom[160] = 14'd7654 ; rom[161] = 14'd3728 ; rom[162] = 14'd9354 ; rom[163] = 14'd9953 ;
        rom[164] = 14'd11607; rom[165] = 14'd825  ; rom[166] = 14'd9492 ; rom[167] = 14'd873  ;
        rom[168] = 14'd9062 ; rom[169] = 14'd2874 ; rom[170] = 14'd8497 ; rom[171] = 14'd14549;
        rom[172] = 14'd8295 ; rom[173] = 14'd4588 ; rom[174] = 14'd13448; rom[175] = 14'd5424 ;
        rom[176] = 14'd4816 ; rom[177] = 14'd10421; rom[178] = 14'd2789 ; rom[179] = 14'd11739;
        rom[180] = 14'd15091; rom[181] = 14'd10842; rom[182] = 14'd11246; rom[183] = 14'd4222 ;
        rom[184] = 14'd9555 ; rom[185] = 14'd10503; rom[186] = 14'd7278 ; rom[187] = 14'd5451 ;
        rom[188] = 14'd12187; rom[189] = 14'd5857 ; rom[190] = 14'd14257; rom[191] = 14'd10598;
        rom[192] = 14'd3410 ; rom[193] = 14'd14161; rom[194] = 14'd958  ; rom[195] = 14'd8582 ;
        rom[196] = 14'd10026; rom[197] = 14'd13286; rom[198] = 14'd5605 ; rom[199] = 14'd11019;
        rom[200] = 14'd7571 ; rom[201] = 14'd9772 ; rom[202] = 14'd8328 ; rom[203] = 14'd13573;
        rom[204] = 14'd15304; rom[205] = 14'd2659 ; rom[206] = 14'd5666 ; rom[207] = 14'd1144 ;
        rom[208] = 14'd3915 ; rom[209] = 14'd9088 ; rom[210] = 14'd2906 ; rom[211] = 14'd10265;
        rom[212] = 14'd9459 ; rom[213] = 14'd11221; rom[214] = 14'd15590; rom[215] = 14'd14388;
        rom[216] = 14'd6487 ; rom[217] = 14'd1859 ; rom[218] = 14'd7665 ; rom[219] = 14'd12078;
        rom[220] = 14'd16060; rom[221] = 14'd6532 ; rom[222] = 14'd459  ; rom[223] = 14'd12329;
        rom[224] = 14'd8996 ; rom[225] = 14'd10082; rom[226] = 14'd9230 ; rom[227] = 14'd1563 ;
        rom[228] = 14'd8081 ; rom[229] = 14'd6940 ; rom[230] = 14'd12684; rom[231] = 14'd11111;
        rom[232] = 14'd15943; rom[233] = 14'd7233 ; rom[234] = 14'd8250 ; rom[235] = 14'd7482 ;
        rom[236] = 14'd1464 ; rom[237] = 14'd7844 ; rom[238] = 14'd15271; rom[239] = 14'd6007 ;
        rom[240] = 14'd1270 ; rom[241] = 14'd8472 ; rom[242] = 14'd12971; rom[243] = 14'd8546 ;
        rom[244] = 14'd1133 ; rom[245] = 14'd671  ; rom[246] = 14'd12986; rom[247] = 14'd8008 ;
        rom[248] = 14'd7167 ; rom[249] = 14'd12350; rom[250] = 14'd6300 ; rom[251] = 14'd2160 ;
        rom[252] = 14'd15859; rom[253] = 14'd11343; rom[254] = 14'd1034 ; rom[255] = 14'd5849 ;
    end

    //--------------------------------------------------------------------------
    // xorshift32 (13, 17, 5) -- combinational, matches C exactly.
    //   x ^= x << 13;  x ^= x >> 17;  x ^= x << 5;
    // The C helper substitutes 0x6D2B79F5 for a zero state before shifting.
    //--------------------------------------------------------------------------
    wire [31:0] xs_in  = (lfsr_q == 32'd0) ? 32'h6D2B_79F5 : lfsr_q;
    wire [31:0] xs_a   = xs_in ^ (xs_in << 13);
    wire [31:0] xs_b   = xs_a  ^ (xs_a  >> 17);
    wire [31:0] xs_nxt = xs_b  ^ (xs_b  << 5);

    wire [15:0] bg_raw  = xs_nxt[15:0];
    wire [15:0] bg_val  = (bg_raw == TARGET_VALUE) ? (bg_raw ^ 16'd1) : bg_raw;

    //--------------------------------------------------------------------------
    // Request validation
    //--------------------------------------------------------------------------
    wire count_bad = (data_count == 15'd0) || (data_count > COUNT_MAX);
    wire range_bad = (target_count > MAX_TARGETS[8:0]);

    wire req_bad   = count_bad | range_bad;

    wire gen_idle  = (st == S_IDLE) && (~ld_done_q);

    assign gen_busy       = ~gen_idle;
    assign gen_error_bits = {e_range, e_busy, 1'b0, e_count, 1'b0};
    assign gen_error      = |gen_error_bits;

    assign load_start   = ld_start_q;
    assign load_done    = ld_done_q;
    assign data_wr_en   = wr_en_q;
    assign data_wr_addr = wr_addr_q;
    assign data_wr_data = wr_data_q;

    wire [14:0] cnt_next  = cnt_q  + 15'd1;
    wire [8:0]  tcnt_next = tcnt_q + 9'd1;

    always @(posedge clk) begin
        if (!rstnn) begin
            st         <= S_IDLE;
            lfsr_q     <= BACKGROUND_SEED;
            n_q        <= 15'd0;
            t_q        <= 9'd0;
            cnt_q      <= 15'd0;
            tcnt_q     <= 9'd0;

            ld_start_q <= 1'b0;
            ld_done_q  <= 1'b0;
            wr_en_q    <= 1'b0;
            wr_addr_q  <= 14'd0;
            wr_data_q  <= 16'sd0;

            e_count    <= 1'b0;
            e_busy     <= 1'b0;
            e_range    <= 1'b0;
        end
        else begin
            ld_start_q <= 1'b0;
            ld_done_q  <= 1'b0;
            wr_en_q    <= 1'b0;

            if (gen_start) begin
                if ((~gen_idle) || main_busy) begin
                    e_busy <= 1'b1;
                end
                else if (req_bad) begin
                    if (count_bad) e_count <= 1'b1;
                    if (range_bad) e_range <= 1'b1;
                end
                else begin
                    e_count    <= 1'b0;
                    e_busy     <= 1'b0;
                    e_range    <= 1'b0;

                    lfsr_q     <= BACKGROUND_SEED;
                    n_q        <= data_count;
                    t_q        <= target_count;
                    cnt_q      <= 15'd0;
                    tcnt_q     <= 9'd0;

                    ld_start_q <= 1'b1;
                    st         <= S_WAIT_BUSY;
                end
            end

            case (st)

                S_IDLE: begin
                end

                S_WAIT_BUSY: begin
                    if (load_busy)
                        st <= S_BG;
                end

                // Background pass: one 16-bit element per cycle.
                S_BG: begin
                    wr_en_q   <= 1'b1;
                    wr_addr_q <= cnt_q[13:0];
                    wr_data_q <= $signed(bg_val);

                    lfsr_q    <= xs_nxt;
                    cnt_q     <= cnt_next;

                    if (cnt_next == n_q)
                        st <= (t_q == 9'd0) ? S_FIN : S_TGT;
                end

                // Target pass: overwrite the first t_q ROM positions.
                S_TGT: begin
                    wr_en_q   <= 1'b1;
                    wr_addr_q <= rom[tcnt_q[7:0]];
                    wr_data_q <= $signed(TARGET_VALUE);

                    tcnt_q    <= tcnt_next;

                    if (tcnt_next == t_q)
                        st <= S_FIN;
                end

                S_FIN: begin
                    ld_done_q <= 1'b1;
                    st        <= S_IDLE;
                end

                default: begin
                    st <= S_IDLE;
                end

            endcase
        end
    end

endmodule
