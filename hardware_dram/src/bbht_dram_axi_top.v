//=====================================================================
// bbht_dram_axi_top.v -- hardware_dram 갈래를 RVX 에 설치할 때 쓰는 최상단
//
// bbht_dram_top 은 DRAM burst 포트를 밖으로 낸 채로 끝납니다(시뮬에서는
// testbench/dram_burst_model.v 가 그 자리에 들어갑니다). 이 모듈은 그 포트에
// grover_dram_axi_bridge 를 물려 AXI4 마스터로 바꿉니다. 그러면 포트가
// RVX 인터페이스 셋과 한 줄씩 대응합니다.
//
//   APB 슬레이브   i_grover_csr   (user_slaveif_apb_clkout)   CSR 38개
//   AHB 마스터     i_grover_dma   (user_masterif_ahb_clkout)  데이터셋 적재
//   AXI4 마스터    i_grover_dram  (user_masterif_axi4_clkout) 진폭표 DDR3
//
// user region(bbht_grover_user_region.vh)이 이 모듈 하나만 뭅니다. 시뮬
// 하네스(testbench/tb_dram_axi_sys.v)도 같은 모듈에 AXI 메모리 모델을 붙여
// 쓰므로, 보드에 들어가는 RTL 과 시뮬로 검증한 RTL 이 같습니다.
//
// bbht_dram_top 은 고치지 않았습니다. 그쪽의 top 회귀(H1~H14)가 추상 포트
// 위에서 이미 돌고 있고, 이 모듈은 그 위에 한 겹을 더할 뿐입니다.
//=====================================================================
`timescale 1ns/1ps
`include "bbht_grover_csr.vh"
`include "grover_dram_param.vh"

module bbht_dram_axi_top #(
    parameter [31:0] SRAM_BASE      = 32'hE000_0000,
    parameter [31:0] SRAM_LAST      = 32'hE001_FFFF,
    // 진폭표가 놓이는 AXI 주소. grover_dram_axi_bridge 머리말 참조.
    parameter [31:0] DRAM_AXI_BASE  = 32'h0000_0000,
    parameter integer BW_TID        = 4
) (
    input  wire              clk,        // clk_accel
    input  wire              rstnn,

    // APB 슬레이브
    input  wire              psel,
    input  wire              penable,
    input  wire              pwrite,
    input  wire [31:0]       paddr,
    input  wire [31:0]       pwdata,
    output wire              pready,
    output wire [31:0]       prdata,
    output wire              pslverr,

    // AHB 마스터
    input  wire              shready,
    input  wire [31:0]       shrdata,
    input  wire              shresp,
    output wire [31:0]       shaddr,
    output wire [2:0]        shburst,
    output wire              shmasterlock,
    output wire [3:0]        shprot,
    output wire [2:0]        shsize,
    output wire [1:0]        shtrans,
    output wire              shwrite,
    output wire [31:0]       shwdata,

    // AXI4 마스터 (RVX sx4* 와 같은 이름·순서)
    input  wire              sx4awready,
    output wire              sx4awvalid,
    output wire [31:0]       sx4awaddr,
    output wire [BW_TID-1:0] sx4awid,
    output wire [7:0]        sx4awlen,
    output wire [2:0]        sx4awsize,
    output wire [1:0]        sx4awburst,
    input  wire              sx4wready,
    output wire              sx4wvalid,
    output wire [31:0]       sx4wdata,
    output wire [3:0]        sx4wstrb,
    output wire              sx4wlast,
    output wire              sx4bready,
    input  wire              sx4bvalid,
    input  wire [BW_TID-1:0] sx4bid,
    input  wire [1:0]        sx4bresp,
    input  wire              sx4arready,
    output wire              sx4arvalid,
    output wire [31:0]       sx4araddr,
    output wire [BW_TID-1:0] sx4arid,
    output wire [7:0]        sx4arlen,
    output wire [2:0]        sx4arsize,
    output wire [1:0]        sx4arburst,
    output wire              sx4rready,
    input  wire              sx4rvalid,
    input  wire [BW_TID-1:0] sx4rid,
    input  wire [31:0]       sx4rdata,
    input  wire              sx4rlast,
    input  wire [1:0]        sx4rresp,

    // 관측점 (보드에서는 ILA 나 LED 자리)
    output wire [`GP_J_W-1:0] dram_frontier_j,
    output wire               dram_bridge_busy,
    output wire               dram_axi_error
);
    localparam integer ROW_BITS = `GP_P * `GP_AMP_W;

    wire                         dram_wr_req, dram_wr_valid, dram_wr_last, dram_wr_ready;
    wire [`GD_ADDR_W-1:0]        dram_wr_addr;
    wire [`GD_BURST_LEN_W-1:0]   dram_wr_len;
    wire [ROW_BITS-1:0]          dram_wr_data;
    wire                         dram_rd_req, dram_rd_valid, dram_rd_ready, dram_rd_last;
    wire [`GD_ADDR_W-1:0]        dram_rd_addr;
    wire [`GD_BURST_LEN_W-1:0]   dram_rd_len;
    wire [ROW_BITS-1:0]          dram_rd_data;

    bbht_dram_top #(
        .SRAM_BASE (SRAM_BASE),
        .SRAM_LAST (SRAM_LAST)
    ) u_top (
        .clk            (clk),
        .rstnn          (rstnn),

        .psel           (psel),
        .penable        (penable),
        .pwrite         (pwrite),
        .paddr          (paddr),
        .pwdata         (pwdata),
        .pready         (pready),
        .prdata         (prdata),
        .pslverr        (pslverr),

        .shready        (shready),
        .shrdata        (shrdata),
        .shresp         (shresp),
        .shaddr         (shaddr),
        .shburst        (shburst),
        .shmasterlock   (shmasterlock),
        .shprot         (shprot),
        .shsize         (shsize),
        .shtrans        (shtrans),
        .shwrite        (shwrite),
        .shwdata        (shwdata),

        .dram_wr_req    (dram_wr_req),
        .dram_wr_addr   (dram_wr_addr),
        .dram_wr_len    (dram_wr_len),
        .dram_wr_valid  (dram_wr_valid),
        .dram_wr_data   (dram_wr_data),
        .dram_wr_last   (dram_wr_last),
        .dram_wr_ready  (dram_wr_ready),

        .dram_rd_req    (dram_rd_req),
        .dram_rd_addr   (dram_rd_addr),
        .dram_rd_len    (dram_rd_len),
        .dram_rd_valid  (dram_rd_valid),
        .dram_rd_data   (dram_rd_data),
        .dram_rd_ready  (dram_rd_ready),
        .dram_rd_last   (dram_rd_last),

        .dram_frontier_j(dram_frontier_j)
    );

    grover_dram_axi_bridge #(
        .AXI_BASE (DRAM_AXI_BASE),
        .BW_TID   (BW_TID)
    ) u_bridge (
        .clk            (clk),
        .rstn           (rstnn),

        .dram_wr_req    (dram_wr_req),
        .dram_wr_addr   (dram_wr_addr),
        .dram_wr_len    (dram_wr_len),
        .dram_wr_valid  (dram_wr_valid),
        .dram_wr_data   (dram_wr_data),
        .dram_wr_last   (dram_wr_last),
        .dram_wr_ready  (dram_wr_ready),

        .dram_rd_req    (dram_rd_req),
        .dram_rd_addr   (dram_rd_addr),
        .dram_rd_len    (dram_rd_len),
        .dram_rd_valid  (dram_rd_valid),
        .dram_rd_data   (dram_rd_data),
        .dram_rd_ready  (dram_rd_ready),
        .dram_rd_last   (dram_rd_last),

        .awvalid        (sx4awvalid),
        .awready        (sx4awready),
        .awaddr         (sx4awaddr),
        .awid           (sx4awid),
        .awlen          (sx4awlen),
        .awsize         (sx4awsize),
        .awburst        (sx4awburst),
        .wvalid         (sx4wvalid),
        .wready         (sx4wready),
        .wdata          (sx4wdata),
        .wstrb          (sx4wstrb),
        .wlast          (sx4wlast),
        .bready         (sx4bready),
        .bvalid         (sx4bvalid),
        .bid            (sx4bid),
        .bresp          (sx4bresp),
        .arvalid        (sx4arvalid),
        .arready        (sx4arready),
        .araddr         (sx4araddr),
        .arid           (sx4arid),
        .arlen          (sx4arlen),
        .arsize         (sx4arsize),
        .arburst        (sx4arburst),
        .rready         (sx4rready),
        .rvalid         (sx4rvalid),
        .rid            (sx4rid),
        .rdata          (sx4rdata),
        .rlast          (sx4rlast),
        .rresp          (sx4rresp),

        .busy           (dram_bridge_busy),
        .axi_error      (dram_axi_error)
    );

endmodule
