//==============================================================================
// bbht_uart_apb_bridge.v -- UART <-> APB 마스터 브리지
//
// RVX SoC의 rvc_orca 코어가 APB로 CSR을 읽고 쓰던 자리를 대신한다.
// 호스트 PC가 UART로 프레임을 보내면 그대로 APB 트랜잭션이 된다.
//
// bbht_grover_mmio.v 는 수정하지 않는다.  CSR 맵/오프셋/비트 배치가
// RVX 빌드와 완전히 동일하게 유지되므로, 두 빌드의 결과를 직접 대조할 수 있다.
//
//------------------------------------------------------------------------------
// 프레임 (바이너리, 리틀엔디언)
//------------------------------------------------------------------------------
//   쓰기   'W'(0x57) a[7:0] a[15:8] d[7:0] d[15:8] d[23:16] d[31:24]   7 B
//          -> 응답 1 B :  'K'(0x4B) 정상 / 'E'(0x45) pslverr
//
//   읽기   'R'(0x52) a[7:0] a[15:8]                                    3 B
//          -> 응답 5 B :  d[7:0] d[15:8] d[23:16] d[31:24] 상태
//                          상태 = 'K' 또는 'E'
//
//   핑     'P'(0x50)                                                   1 B
//          -> 응답 2 B :  'K' VERSION
//
//   그 외 바이트는 조용히 버린다 (재동기화용).  호스트는 'P'로 동기를 맞춘다.
//
//------------------------------------------------------------------------------
// 주소
//------------------------------------------------------------------------------
// 프레임의 16비트 주소는 CSR 오프셋이다 (0x00, 0x04, ...).  paddr 상위는 0으로
// 채운다.  MMIO가 paddr[11:0]만 디코드하므로 RVX의 베이스 주소
// (I_GROVER_CSR_SLAVE_BASEADDR = 0xE2020000)는 여기서 의미가 없다.
//
//------------------------------------------------------------------------------
// APB 타이밍
//------------------------------------------------------------------------------
// MMIO는 pready 상수 1이므로 ACCESS 위상이 정확히 1사이클이다.  penable을
// 1사이클만 세우는 것이 중요하다 -- FIFO_DATA 읽기의 cmd_res_pop 이 조합
// 펄스라서, ACCESS를 늘리면 결과 FIFO를 여러 번 pop 하게 된다.
//
//------------------------------------------------------------------------------
// 보율
//------------------------------------------------------------------------------
// 기본 1 Mbaud.  100 MHz / 1 Mbaud = 정확히 100 이라 분주 오차가 0이다.
// (115200은 868.06으로 나눠떨어지지 않는다)
//==============================================================================
`timescale 1ns/1ps

module bbht_uart_apb_bridge #(
    parameter integer CLK_HZ  = 100_000_000,
    parameter integer BAUD    = 1_000_000,
    parameter [7:0]   VERSION = 8'h01
) (
    input  wire        clk,
    input  wire        rstnn,

    // ---------------- UART ----------------
    input  wire        uart_rx,     // PC -> FPGA
    output wire        uart_tx,     // FPGA -> PC

    // ------------- APB master -------------
    output reg         psel,
    output reg         penable,
    output reg         pwrite,
    output reg  [31:0] paddr,
    output reg  [31:0] pwdata,

    input  wire        pready,
    input  wire [31:0] prdata,
    input  wire        pslverr
);

    localparam integer DIV      = CLK_HZ / BAUD;
    localparam integer DIV_HALF = DIV / 2;

    localparam [7:0] CMD_WRITE = 8'h57;   // 'W'
    localparam [7:0] CMD_READ  = 8'h52;   // 'R'
    localparam [7:0] CMD_PING  = 8'h50;   // 'P'
    localparam [7:0] RSP_OK    = 8'h4B;   // 'K'
    localparam [7:0] RSP_ERR   = 8'h45;   // 'E'

    //==========================================================================
    // UART 수신
    //==========================================================================
    reg [2:0]  rx_sync;
    always @(posedge clk) begin
        if (!rstnn) rx_sync <= 3'b111;
        else        rx_sync <= {rx_sync[1:0], uart_rx};
    end
    wire rx_pin = rx_sync[2];

    localparam [1:0] RX_IDLE = 2'd0,
                     RX_STRT = 2'd1,
                     RX_DATA = 2'd2,
                     RX_STOP = 2'd3;

    reg [1:0]  rx_st;
    reg [15:0] rx_cnt;
    reg [2:0]  rx_bit;
    reg [7:0]  rx_sh;
    reg [7:0]  rx_byte;
    reg        rx_valid;

    always @(posedge clk) begin
        if (!rstnn) begin
            rx_st    <= RX_IDLE;
            rx_cnt   <= 16'd0;
            rx_bit   <= 3'd0;
            rx_sh    <= 8'd0;
            rx_byte  <= 8'd0;
            rx_valid <= 1'b0;
        end
        else begin
            rx_valid <= 1'b0;

            case (rx_st)
                RX_IDLE: begin
                    if (!rx_pin) begin
                        rx_cnt <= DIV_HALF[15:0];
                        rx_st  <= RX_STRT;
                    end
                end

                RX_STRT: begin
                    if (rx_cnt == 16'd0) begin
                        if (!rx_pin) begin       // 시작 비트 재확인
                            rx_cnt <= DIV[15:0];
                            rx_bit <= 3'd0;
                            rx_st  <= RX_DATA;
                        end
                        else begin
                            rx_st <= RX_IDLE;    // 글리치
                        end
                    end
                    else rx_cnt <= rx_cnt - 16'd1;
                end

                RX_DATA: begin
                    if (rx_cnt == 16'd0) begin
                        rx_sh  <= {rx_pin, rx_sh[7:1]};   // LSB first
                        rx_cnt <= DIV[15:0];
                        if (rx_bit == 3'd7) rx_st <= RX_STOP;
                        else                rx_bit <= rx_bit + 3'd1;
                    end
                    else rx_cnt <= rx_cnt - 16'd1;
                end

                RX_STOP: begin
                    if (rx_cnt == 16'd0) begin
                        if (rx_pin) begin        // 정상 정지 비트
                            rx_byte  <= rx_sh;
                            rx_valid <= 1'b1;
                        end
                        rx_st <= RX_IDLE;        // 프레이밍 오류면 버림
                    end
                    else rx_cnt <= rx_cnt - 16'd1;
                end
            endcase
        end
    end

    //==========================================================================
    // UART 송신
    //==========================================================================
    localparam [1:0] TX_IDLE = 2'd0,
                     TX_STRT = 2'd1,
                     TX_DATA = 2'd2,
                     TX_STOP = 2'd3;

    reg [1:0]  tx_st;
    reg [15:0] tx_cnt;
    reg [2:0]  tx_bit;
    reg [7:0]  tx_sh;
    reg        tx_out;

    reg [7:0]  tx_byte;
    reg        tx_send;
    wire       tx_ready = (tx_st == TX_IDLE);

    assign uart_tx = tx_out;

    always @(posedge clk) begin
        if (!rstnn) begin
            tx_st  <= TX_IDLE;
            tx_cnt <= 16'd0;
            tx_bit <= 3'd0;
            tx_sh  <= 8'd0;
            tx_out <= 1'b1;
        end
        else begin
            case (tx_st)
                TX_IDLE: begin
                    tx_out <= 1'b1;
                    if (tx_send) begin
                        tx_sh  <= tx_byte;
                        tx_cnt <= DIV[15:0];
                        tx_out <= 1'b0;          // 시작 비트
                        tx_st  <= TX_STRT;
                    end
                end

                TX_STRT: begin
                    if (tx_cnt == 16'd0) begin
                        tx_out <= tx_sh[0];
                        tx_sh  <= {1'b0, tx_sh[7:1]};
                        tx_bit <= 3'd0;
                        tx_cnt <= DIV[15:0];
                        tx_st  <= TX_DATA;
                    end
                    else tx_cnt <= tx_cnt - 16'd1;
                end

                TX_DATA: begin
                    if (tx_cnt == 16'd0) begin
                        tx_cnt <= DIV[15:0];
                        if (tx_bit == 3'd7) begin
                            tx_out <= 1'b1;      // 정지 비트
                            tx_st  <= TX_STOP;
                        end
                        else begin
                            tx_out <= tx_sh[0];
                            tx_sh  <= {1'b0, tx_sh[7:1]};
                            tx_bit <= tx_bit + 3'd1;
                        end
                    end
                    else tx_cnt <= tx_cnt - 16'd1;
                end

                TX_STOP: begin
                    if (tx_cnt == 16'd0) tx_st <= TX_IDLE;
                    else                 tx_cnt <= tx_cnt - 16'd1;
                end
            endcase
        end
    end

    //==========================================================================
    // 명령 파서 + APB 마스터
    //==========================================================================
    localparam [3:0] S_CMD     = 4'd0,
                     S_ARG     = 4'd1,
                     S_SETUP   = 4'd2,
                     S_ACCESS  = 4'd3,
                     S_CAPTURE = 4'd4,
                     S_RESP    = 4'd5;

    reg [3:0]  st;
    reg [2:0]  argn;        // 남은 인자 바이트 수
    reg [2:0]  argi;        // 수신한 인자 인덱스
    reg        is_write;

    reg [15:0] a_q;
    reg [31:0] d_q;

    reg [39:0] rsp_sh;      // 최대 5바이트
    reg [2:0]  rsp_n;

    always @(posedge clk) begin
        if (!rstnn) begin
            st       <= S_CMD;
            argn     <= 3'd0;
            argi     <= 3'd0;
            is_write <= 1'b0;
            a_q      <= 16'd0;
            d_q      <= 32'd0;
            rsp_sh   <= 40'd0;
            rsp_n    <= 3'd0;

            psel     <= 1'b0;
            penable  <= 1'b0;
            pwrite   <= 1'b0;
            paddr    <= 32'd0;
            pwdata   <= 32'd0;

            tx_send  <= 1'b0;
            tx_byte  <= 8'd0;
        end
        else begin
            tx_send <= 1'b0;

            case (st)

                //--------------------------------------------------------------
                S_CMD: begin
                    psel    <= 1'b0;
                    penable <= 1'b0;

                    if (rx_valid) begin
                        argi <= 3'd0;
                        case (rx_byte)
                            CMD_WRITE: begin
                                is_write <= 1'b1;
                                argn     <= 3'd6;   // addr2 + data4
                                st       <= S_ARG;
                            end
                            CMD_READ: begin
                                is_write <= 1'b0;
                                argn     <= 3'd2;   // addr2
                                st       <= S_ARG;
                            end
                            CMD_PING: begin
                                rsp_sh <= {24'd0, VERSION, RSP_OK};
                                rsp_n  <= 3'd2;
                                st     <= S_RESP;
                            end
                            default: begin
                                st <= S_CMD;        // 알 수 없는 바이트는 버림
                            end
                        endcase
                    end
                end

                //--------------------------------------------------------------
                S_ARG: begin
                    if (rx_valid) begin
                        case (argi)
                            3'd0: a_q[7:0]    <= rx_byte;
                            3'd1: a_q[15:8]   <= rx_byte;
                            3'd2: d_q[7:0]    <= rx_byte;
                            3'd3: d_q[15:8]   <= rx_byte;
                            3'd4: d_q[23:16]  <= rx_byte;
                            3'd5: d_q[31:24]  <= rx_byte;
                            default: ;
                        endcase

                        if (argi == (argn - 3'd1)) begin
                            st <= S_SETUP;
                        end
                        else begin
                            argi <= argi + 3'd1;
                        end
                    end
                end

                //--------------------------------------------------------------
                // APB 위상 전개.  레지스터 출력이므로 각 상태의 대입은 다음
                // 사이클에 슬레이브에게 보인다.  세 상태로 나눈 이유가 이것이다.
                //
                //   S_SETUP   에서 대입 -> S_ACCESS  사이클에 슬레이브가 SETUP 관측
                //   S_ACCESS  에서 대입 -> S_CAPTURE 사이클에 슬레이브가 ACCESS 관측
                //   S_CAPTURE 사이클에서 prdata/pslverr 가 유효하므로 여기서 포획
                //
                // penable 이 1인 사이클은 정확히 하나다.  FIFO_DATA 읽기의
                // cmd_res_pop 이 조합 펄스라 이 폭이 곧 pop 횟수가 된다.
                //--------------------------------------------------------------
                S_SETUP: begin
                    psel    <= 1'b1;
                    penable <= 1'b0;
                    pwrite  <= is_write;
                    paddr   <= {16'd0, a_q};
                    pwdata  <= d_q;
                    st      <= S_ACCESS;
                end

                S_ACCESS: begin
                    penable <= 1'b1;
                    st      <= S_CAPTURE;
                end

                S_CAPTURE: begin
                    if (pready) begin
                        psel    <= 1'b0;
                        penable <= 1'b0;

                        if (is_write) begin
                            rsp_sh <= {32'd0, (pslverr ? RSP_ERR : RSP_OK)};
                            rsp_n  <= 3'd1;
                        end
                        else begin
                            rsp_sh <= {(pslverr ? RSP_ERR : RSP_OK), prdata};
                            rsp_n  <= 3'd5;
                        end
                        st <= S_RESP;
                    end
                end

                //--------------------------------------------------------------
                S_RESP: begin
                    if (rsp_n == 3'd0) begin
                        st <= S_CMD;
                    end
                    else if (tx_ready && !tx_send) begin
                        tx_byte <= rsp_sh[7:0];
                        tx_send <= 1'b1;
                        rsp_sh  <= {8'd0, rsp_sh[39:8]};
                        rsp_n   <= rsp_n - 3'd1;
                    end
                end

                default: st <= S_CMD;

            endcase
        end
    end

endmodule
