//=====================================================================
// tb_dram_axi_sys.v -- 보드에 들어가는 DRAM 갈래 RTL 을 통째로 감싼 시뮬 틀
//
// bbht_dram_axi_top(통신 계층 + Main IP + AXI 브리지)에 axi4_mem_model 을
// 붙이고, 밖으로는 APB 와 AHB 만 냅니다. C++ 하네스(tb_dram_predicate500.cpp)가
// 실제 펌웨어 드라이버(bbht_grover_driver.c)로 이 두 포트를 두드립니다.
// hardware_bram 의 tb_predicate500.cpp 가 bbht_rvx_wrapper 를 두드리는 것과
// 같은 모양이라, 두 갈래를 같은 자극·같은 드라이버로 맞댈 수 있습니다.
//
//   드라이버 --APB/AHB--> bbht_dram_axi_top --AXI4--> axi4_mem_model
//
// 보드와 다른 것은 AXI 뒤쪽 하나입니다(NoC 와 MIG 대신 모델).
//=====================================================================
`timescale 1ns/1ps

module tb_dram_axi_sys #(
    parameter integer AR_LAT   = 20,
    parameter integer B_LAT    = 8,
    parameter integer STALL_EN = 0
) (
    input  wire        clk,
    input  wire        rstnn,

    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] paddr,
    input  wire [31:0] pwdata,
    output wire        pready,
    output wire [31:0] prdata,
    output wire        pslverr,

    input  wire        shready,
    input  wire [31:0] shrdata,
    input  wire        shresp,
    output wire [31:0] shaddr,
    output wire [2:0]  shburst,
    output wire        shmasterlock,
    output wire [3:0]  shprot,
    output wire [2:0]  shsize,
    output wire [1:0]  shtrans,
    output wire        shwrite,
    output wire [31:0] shwdata,

    // 관측
    output wire [31:0] mem_err_count,
    output wire [31:0] mem_wr_bursts,
    output wire [31:0] mem_rd_bursts,
    output wire        axi_error,
    output wire [6:0]  frontier_j
);
    localparam integer TID = 4;

    wire           awready, awvalid, wready, wvalid, wlast, bready, bvalid;
    wire           arready, arvalid, rready, rvalid, rlast;
    wire [31:0]    awaddr, araddr, wdata, rdata;
    wire [TID-1:0] awid, arid, bid, rid;
    wire [7:0]     awlen, arlen;
    wire [2:0]     awsize, arsize;
    wire [1:0]     awburst, arburst, bresp, rresp;
    wire [3:0]     wstrb;
    wire           bridge_busy;

    bbht_dram_axi_top #(.BW_TID(TID)) u_dut (
        .clk (clk), .rstnn (rstnn),
        .psel (psel), .penable (penable), .pwrite (pwrite), .paddr (paddr),
        .pwdata (pwdata), .pready (pready), .prdata (prdata), .pslverr (pslverr),
        .shready (shready), .shrdata (shrdata), .shresp (shresp), .shaddr (shaddr),
        .shburst (shburst), .shmasterlock (shmasterlock), .shprot (shprot),
        .shsize (shsize), .shtrans (shtrans), .shwrite (shwrite), .shwdata (shwdata),
        .sx4awready (awready), .sx4awvalid (awvalid), .sx4awaddr (awaddr),
        .sx4awid (awid), .sx4awlen (awlen), .sx4awsize (awsize), .sx4awburst (awburst),
        .sx4wready (wready), .sx4wvalid (wvalid), .sx4wdata (wdata),
        .sx4wstrb (wstrb), .sx4wlast (wlast),
        .sx4bready (bready), .sx4bvalid (bvalid), .sx4bid (bid), .sx4bresp (bresp),
        .sx4arready (arready), .sx4arvalid (arvalid), .sx4araddr (araddr),
        .sx4arid (arid), .sx4arlen (arlen), .sx4arsize (arsize), .sx4arburst (arburst),
        .sx4rready (rready), .sx4rvalid (rvalid), .sx4rid (rid), .sx4rdata (rdata),
        .sx4rlast (rlast), .sx4rresp (rresp),
        .dram_frontier_j (frontier_j),
        .dram_bridge_busy (bridge_busy),
        .dram_axi_error (axi_error)
    );

    axi4_mem_model #(
        .BW_TID (TID), .AR_LAT (AR_LAT), .B_LAT (B_LAT), .STALL_EN (STALL_EN)
    ) u_mem (
        .clk (clk), .rstn (rstnn),
        .awready (awready), .awvalid (awvalid), .awaddr (awaddr), .awid (awid),
        .awlen (awlen), .awsize (awsize), .awburst (awburst),
        .wready (wready), .wvalid (wvalid), .wdata (wdata), .wstrb (wstrb), .wlast (wlast),
        .bready (bready), .bvalid (bvalid), .bid (bid), .bresp (bresp),
        .arready (arready), .arvalid (arvalid), .araddr (araddr), .arid (arid),
        .arlen (arlen), .arsize (arsize), .arburst (arburst),
        .rready (rready), .rvalid (rvalid), .rid (rid), .rdata (rdata),
        .rlast (rlast), .rresp (rresp),
        .err_count (mem_err_count), .wr_bursts (mem_wr_bursts), .rd_bursts (mem_rd_bursts)
    );

    wire _unused = bridge_busy;
endmodule
