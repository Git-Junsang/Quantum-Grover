/*****************/
/* Custom Region */
/*****************/

// wire clk_system;
// wire clk_core;
// wire clk_system_external;
// wire clk_system_debug;
// wire clk_local_access;
// wire clk_process_000;
// wire clk_noc;
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

// ------------------------------------------------------------
// Dedicated 100 MHz accelerator domain
//
// RVX clkout interfaces require the USER region to drive the
// user-side protocol clocks.  Both APB CSR and AHB DMA are
// intentionally placed in the same clk_accel domain as the
// BBHT/Grover wrapper and Main IP.
// ------------------------------------------------------------
assign i_grover_csr_clk = clk_accel;
assign i_grover_dma_clk = clk_accel;

bbht_rvx_wrapper
i_bbht_rvx_wrapper
(
        .clk(i_grover_csr_clk),
        .rstnn(i_grover_csr_rstnn),

        // APB CSR
        .psel(i_grover_csr_rpsel),
        .penable(i_grover_csr_rpenable),
        .pwrite(i_grover_csr_rpwrite),
        .paddr(i_grover_csr_rpaddr),
        .pwdata(i_grover_csr_rpwdata),

        .pready(i_grover_csr_rpready),
        .prdata(i_grover_csr_rprdata),
        .pslverr(i_grover_csr_rpslverr),

        // AHB DMA
        .shready(i_grover_dma_shready),

        .shaddr(i_grover_dma_shaddr),
        .shburst(i_grover_dma_shburst),
        .shmasterlock(i_grover_dma_shmasterlock),
        .shprot(i_grover_dma_shprot),
        .shsize(i_grover_dma_shsize),
        .shtrans(i_grover_dma_shtrans),
        .shwrite(i_grover_dma_shwrite),
        .shwdata(i_grover_dma_shwdata),

        .shrdata(i_grover_dma_shrdata),
        .shresp(i_grover_dma_shresp)
);

/*
USER_IP
#(
	.BW_ADDR(32),
	.BW_DATA(32)
)
i_grover_dma
(
	.clk(i_grover_dma_clk),
	.rstnn(i_grover_dma_rstnn),
	.shready(i_grover_dma_shready),
	.shaddr(i_grover_dma_shaddr),
	.shburst(i_grover_dma_shburst),
	.shmasterlock(i_grover_dma_shmasterlock),
	.shprot(i_grover_dma_shprot),
	.shsize(i_grover_dma_shsize),
	.shtrans(i_grover_dma_shtrans),
	.shwrite(i_grover_dma_shwrite),
	.shwdata(i_grover_dma_shwdata),
	.shrdata(i_grover_dma_shrdata),
	.shresp(i_grover_dma_shresp)
);
*/
//assign `NOT_CONNECT = i_grover_dma_clk;
//assign `NOT_CONNECT = i_grover_dma_rstnn;
//assign `NOT_CONNECT = i_grover_dma_shready;
//assign `NOT_CONNECT = i_grover_dma_shresp;
