/*****************/
/* Custom Region */
/*****************/

// wire clk_accel;
// wire clk_system;
// wire clk_core;
// wire clk_system_external;
// wire clk_system_debug;
// wire clk_local_access;
// wire clk_process_000;
// wire clk_dram_if;
// wire clk_dram_sys;
// wire clk_dram_ref;
// wire clk_noc;
// wire gclk_accel;
// wire gclk_system;
// wire gclk_core;
// wire gclk_system_external;
// wire gclk_system_debug;
// wire gclk_local_access;
// wire gclk_process_000;
// wire gclk_noc;
// wire tick_1us;
// wire tick_62d5ms;
// wire tick_gpio;
// wire spi_common_sclk;
// wire spi_common_sdq0;
// wire global_rstnn;
// wire global_rstpp;
// wire [(6)-1:0] rstnn_seqeunce;
// wire [(6)-1:0] rstpp_seqeunce;
// wire rstnn_user;
// wire rstpp_user;
// wire i_grover_csr_clk;
// wire i_grover_csr_rstnn;
// wire i_grover_csr_rpsel;
// wire i_grover_csr_rpenable;
// wire i_grover_csr_rpwrite;
// wire [(32)-1:0] i_grover_csr_rpaddr;
// wire [(32)-1:0] i_grover_csr_rpwdata;
// wire i_grover_csr_rpready;
// wire [(32)-1:0] i_grover_csr_rprdata;
// wire i_grover_csr_rpslverr;
// wire i_grover_dma_clk;
// wire i_grover_dma_rstnn;
// wire i_grover_dma_shready;
// wire [(32)-1:0] i_grover_dma_shaddr;
// wire [(3)-1:0] i_grover_dma_shburst;
// wire i_grover_dma_shmasterlock;
// wire [(4)-1:0] i_grover_dma_shprot;
// wire [(3)-1:0] i_grover_dma_shsize;
// wire [(2)-1:0] i_grover_dma_shtrans;
// wire i_grover_dma_shwrite;
// wire [(32)-1:0] i_grover_dma_shwdata;
// wire [(32)-1:0] i_grover_dma_shrdata;
// wire i_grover_dma_shresp;
// wire i_grover_dram_clk;
// wire i_grover_dram_rstnn;
// wire i_grover_dram_sx4awready;
// wire i_grover_dram_sx4awvalid;
// wire [(32)-1:0] i_grover_dram_sx4awaddr;
// wire [(4)-1:0] i_grover_dram_sx4awid;
// wire [(8)-1:0] i_grover_dram_sx4awlen;
// wire [(3)-1:0] i_grover_dram_sx4awsize;
// wire [(2)-1:0] i_grover_dram_sx4awburst;
// wire i_grover_dram_sx4wready;
// wire i_grover_dram_sx4wvalid;
// wire [(32)-1:0] i_grover_dram_sx4wdata;
// wire [(32/8)-1:0] i_grover_dram_sx4wstrb;
// wire i_grover_dram_sx4wlast;
// wire i_grover_dram_sx4bready;
// wire i_grover_dram_sx4bvalid;
// wire [(4)-1:0] i_grover_dram_sx4bid;
// wire [(2)-1:0] i_grover_dram_sx4bresp;
// wire i_grover_dram_sx4arready;
// wire i_grover_dram_sx4arvalid;
// wire [(32)-1:0] i_grover_dram_sx4araddr;
// wire [(4)-1:0] i_grover_dram_sx4arid;
// wire [(8)-1:0] i_grover_dram_sx4arlen;
// wire [(3)-1:0] i_grover_dram_sx4arsize;
// wire [(2)-1:0] i_grover_dram_sx4arburst;
// wire i_grover_dram_sx4rready;
// wire i_grover_dram_sx4rvalid;
// wire [(4)-1:0] i_grover_dram_sx4rid;
// wire [(32)-1:0] i_grover_dram_sx4rdata;
// wire i_grover_dram_sx4rlast;
// wire [(2)-1:0] i_grover_dram_sx4rresp;

/* DO NOT MODIFY THE ABOVE */
/* MUST MODIFY THE BELOW   */

//---------------------------------------------------------------------
// BBHT/Grover DRAM 갈래 결선 (플랫폼 bbht_grover_dram)
//
// hardware_bram 의 user region 과 같은 틀에 AXI4 마스터 하나가 더 붙습니다.
//
//   i_grover_csr   APB 슬레이브   CSR 38개 (두 갈래 공통 정본)
//   i_grover_dma   AHB 마스터     System SRAM 의 데이터셋 적재
//   i_grover_dram  AXI4 마스터    진폭표 -> NoC -> slow_dram(MIG DDR3L)
//
// 세 인터페이스가 모두 *_clkout 이라 클럭은 유저가 넣어 줍니다(아래 assign
// 셋). NoC 쪽과의 CDC 는 RVX 가 만듭니다. 리셋은 셋이 같은 reset group(3)
// 이라 csr 쪽 하나를 씁니다.
//
// 가속기 클럭은 bram 쪽과 같이 gclk_accel 입니다. 2026-09-16 bram 구현에서
// 생성 RTL 이 assign gclk_accel = clk_accel; 인 순수 별칭임을 확인했습니다.
//
// 이 플랫폼은 use_large_ram_manually 로 링커가 DRAM 을 안 쓰므로(코드·데이터는
// 전부 SRAM) 진폭표를 DDR 맨 앞(AXI 0x0000_0000)부터 둡니다. 5.8 MiB 를 씁니다.
//---------------------------------------------------------------------
assign i_grover_csr_clk  = gclk_accel;
assign i_grover_dma_clk  = gclk_accel;
assign i_grover_dram_clk = gclk_accel;

wire [6:0] bbht_dram_frontier_j;
wire       bbht_dram_bridge_busy;
wire       bbht_dram_axi_error;

bbht_dram_axi_top
#(
	.SRAM_BASE     (32'hE0000000),
	.SRAM_LAST     (32'hE001FFFF),
	.DRAM_AXI_BASE (32'h00000000),
	.BW_TID        (4)
)
i_bbht
(
	.clk          (gclk_accel),
	.rstnn        (i_grover_csr_rstnn),

	.psel         (i_grover_csr_rpsel),
	.penable      (i_grover_csr_rpenable),
	.pwrite       (i_grover_csr_rpwrite),
	.paddr        (i_grover_csr_rpaddr),
	.pwdata       (i_grover_csr_rpwdata),
	.pready       (i_grover_csr_rpready),
	.prdata       (i_grover_csr_rprdata),
	.pslverr      (i_grover_csr_rpslverr),

	.shready      (i_grover_dma_shready),
	.shrdata      (i_grover_dma_shrdata),
	.shresp       (i_grover_dma_shresp),
	.shaddr       (i_grover_dma_shaddr),
	.shburst      (i_grover_dma_shburst),
	.shmasterlock (i_grover_dma_shmasterlock),
	.shprot       (i_grover_dma_shprot),
	.shsize       (i_grover_dma_shsize),
	.shtrans      (i_grover_dma_shtrans),
	.shwrite      (i_grover_dma_shwrite),
	.shwdata      (i_grover_dma_shwdata),

	.sx4awready   (i_grover_dram_sx4awready),
	.sx4awvalid   (i_grover_dram_sx4awvalid),
	.sx4awaddr    (i_grover_dram_sx4awaddr),
	.sx4awid      (i_grover_dram_sx4awid),
	.sx4awlen     (i_grover_dram_sx4awlen),
	.sx4awsize    (i_grover_dram_sx4awsize),
	.sx4awburst   (i_grover_dram_sx4awburst),
	.sx4wready    (i_grover_dram_sx4wready),
	.sx4wvalid    (i_grover_dram_sx4wvalid),
	.sx4wdata     (i_grover_dram_sx4wdata),
	.sx4wstrb     (i_grover_dram_sx4wstrb),
	.sx4wlast     (i_grover_dram_sx4wlast),
	.sx4bready    (i_grover_dram_sx4bready),
	.sx4bvalid    (i_grover_dram_sx4bvalid),
	.sx4bid       (i_grover_dram_sx4bid),
	.sx4bresp     (i_grover_dram_sx4bresp),
	.sx4arready   (i_grover_dram_sx4arready),
	.sx4arvalid   (i_grover_dram_sx4arvalid),
	.sx4araddr    (i_grover_dram_sx4araddr),
	.sx4arid      (i_grover_dram_sx4arid),
	.sx4arlen     (i_grover_dram_sx4arlen),
	.sx4arsize    (i_grover_dram_sx4arsize),
	.sx4arburst   (i_grover_dram_sx4arburst),
	.sx4rready    (i_grover_dram_sx4rready),
	.sx4rvalid    (i_grover_dram_sx4rvalid),
	.sx4rid       (i_grover_dram_sx4rid),
	.sx4rdata     (i_grover_dram_sx4rdata),
	.sx4rlast     (i_grover_dram_sx4rlast),
	.sx4rresp     (i_grover_dram_sx4rresp),

	.dram_frontier_j  (bbht_dram_frontier_j),
	.dram_bridge_busy (bbht_dram_bridge_busy),
	.dram_axi_error   (bbht_dram_axi_error)
);

// 관측점 셋은 지금 밖으로 안 냅니다. 보드에서 볼 일이 생기면 ILA 를 붙이십시오.
// i_grover_dma_rstnn / i_grover_dram_rstnn 은 csr 과 같은 reset group 이라 쓰지 않습니다.
//assign `NOT_CONNECT = i_grover_dma_rstnn;
//assign `NOT_CONNECT = i_grover_dram_rstnn;
