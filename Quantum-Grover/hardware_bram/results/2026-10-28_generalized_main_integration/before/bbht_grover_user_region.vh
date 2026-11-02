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

/* DO NOT MODIFY THE ABOVE */
/* MUST MODIFY THE BELOW   */

//---------------------------------------------------------------------
// BBHT/Grover 가속기 결선
//
// 두 인터페이스(APB CSR, AHB DMA)가 같은 clk_accel 도메인에 있습니다.
// user_slaveif_apb_clkout / user_masterif_ahb_clkout 을 쓰므로 클럭은
// **유저가 넣어 줍니다** -- 아래 두 assign 이 그것입니다.
//
// network 쪽(gclk_noc)과의 CDC 는 RVX 가 sni_apb_asynch / mni_ahbm_asynch
// 로 이미 만들어 줍니다. wrapper 안에 CDC 를 또 넣으면 안 됩니다.
//
// 리셋은 두 인터페이스가 같은 reset group(3)에서 나오므로 함께 풀립니다.
// csr 쪽 하나만 받아 wrapper 전체에 씁니다.
//
// 모듈 이름은 소문자입니다. RVX 예제(tip_quantized_cnn)는 USER_* 대문자
// 규약을 쓰지만 Verilog 는 대소문자를 구분하므로, PJK 인수인계가 쓰는 이름
// (bbht_rvx_wrapper / bbht_grover_mmio / bbht_ahb_loader)에 맞춥니다.
//---------------------------------------------------------------------
assign i_grover_csr_clk = gclk_accel;
assign i_grover_dma_clk = gclk_accel;

bbht_rvx_wrapper
#(
	.SRAM_BASE(32'hE0000000),
	.SRAM_LAST(32'hE001FFFF)
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
	.shwdata      (i_grover_dma_shwdata)
);

// i_grover_dma_rstnn 은 위와 같은 reset group 이라 쓰지 않습니다.
// 미사용 경고가 뜨면 아래를 살리십시오.
//assign `NOT_CONNECT = i_grover_dma_rstnn;
