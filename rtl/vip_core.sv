// RCA COSMAC VIP (CDP18S711) board: CPU, 1861, memory, I/O decode, keypad, tone.
// Board logic follows manual Appendix E; external signals follow Table II (I/O port)
// and Table III (expansion interface).

module vip_core
(
	input         clk,
	input         ce,             // 1802 clock, 1.76064 MHz
	input         reset,          // RUN switch down
	input         ram_2k,

	input         ioctl_download,
	input   [7:0] ioctl_index,
	input         ioctl_wr,
	input  [15:0] ioctl_addr,
	input   [7:0] ioctl_dout,

	input  [15:0] keypad,

	// Expansion interface (Table III)
	output  [7:0] exp_ma,
	output        exp_tpa,
	output        exp_tpb,
	output        exp_mrd_n,
	output        exp_mwr_n,
	output  [7:0] exp_bus,        // data bus as resolved on the board
	output  [2:0] exp_n,
	output  [1:0] exp_sc,
	output        exp_run,
	output        exp_cs,         // operating system ROM select (pad X)
	output        exp_cdef_n,     // low when RAM pages C-F are selected
	input   [7:0] exp_bus_in,
	input         exp_bus_oe,
	input         exp_indis,      // high disables internal RAM (pad 19)
	input         exp_int_n,
	input         exp_dma_in_n,
	input         exp_dma_out_n,
	input   [4:1] exp_ef_n,       // EF1/EF3 pads, EF4 from the I/O port

	// I/O port (Table II)
	output  [7:0] io_out,         // U24, OUT 3
	input   [7:0] io_in,          // U25, INP 3
	input         io_inst,        // U25 input strobe

	output        q,
	output signed [7:0] audio,

	output        pixel,
	output        hsync,
	output        vsync,
	output        hblank,
	output        vblank
);

///////////////////////   LOADER   ///////////////////////////////

// ioctl indexes: 0x00 boot0.rom / 3 OSD = monitor ROM, 0x40 boot1.rom = CHIP-8 interpreter,
// 1 = .CH8 (RAM 0200, interpreter copied to 0000 afterwards), 2 = .BIN (RAM 0000)
wire ld_rom    = ioctl_index == 8'h00 || ioctl_index == 8'h03;
wire ld_interp = ioctl_index == 8'h40;
wire ld_ch8    = ioctl_index == 8'h01;
wire ld_bin    = ioctl_index == 8'h02;

reg  [7:0] interp[512];
reg  [7:0] interp_q;
reg  [9:0] copy_cnt = 10'h3FF;     // bit 9 set = idle
reg  [8:0] copy_dst;
reg        copy_wr;
reg        dl_old;

wire copy_busy = !copy_cnt[9] || copy_wr;

always @(posedge clk) begin
	dl_old <= ioctl_download;
	if (ioctl_download && ioctl_wr && ld_interp) interp[ioctl_addr[8:0]] <= ioctl_dout;

	interp_q <= interp[copy_cnt[8:0]];
	copy_dst <= copy_cnt[8:0];
	copy_wr  <= !copy_cnt[9];
	if (dl_old && !ioctl_download && ld_ch8) copy_cnt <= 0;
	else if (!copy_cnt[9]) copy_cnt <= copy_cnt + 1'd1;
end

///////////////////////   CPU   //////////////////////////////////

wire       run = !(reset || copy_busy);

wire [7:0] cpu_dout, ma;
wire       cpu_oe, tpa, tpb, mrd_n, mwr_n;
wire [1:0] sc;
wire [2:0] n;
wire       int_n, dmao_n, efx_n;
wire [4:1] ef_n;
wire [7:0] bus;

cdp1802 cpu
(
	.clk(clk),
	.ce(ce),
	.clear_n(run),
	.wait_n(1'b1),
	.int_n(int_n & exp_int_n),
	.dma_in_n(exp_dma_in_n),
	.dma_out_n(dmao_n & exp_dma_out_n),
	.ef_n(ef_n),
	.bus_in(bus),
	.bus_out(cpu_dout),
	.bus_oe(cpu_oe),
	.ma(ma),
	.tpa(tpa),
	.tpb(tpb),
	.mrd_n(mrd_n),
	.mwr_n(mwr_n),
	.sc(sc),
	.n(n),
	.q(q)
);

///////////////////////   MEMORY DECODE   ////////////////////////

// U6A: cleared while RUN is down, set by any N2 I/O pulse (OUT 4 in the monitor).
// U6B: held set by U6A, otherwise latches A15 at TPA. U8 latches A8-A11 at TPA.
reg       u6a, u6b;
reg [3:0] a_hi;

always @(posedge clk) begin
	if (!run) u6a <= 0;
	else if (ce && tpb && n[2]) u6a <= 1;

	if (!u6a) u6b <= 1;
	else if (ce && tpa) u6b <= ma[7];

	if (ce && tpa) a_hi <= ma[3:0];
end

wire [11:0] addr     = {a_hi, ma};
wire        rom_cs   = u6b;
wire        ram_sect = !ram_2k || !a_hi[3];             // 2K board has sections 0-1 only
wire        ram_cs   = !rom_cs && !exp_indis && ram_sect;

reg [7:0] rom[512];
reg [7:0] ram[4096];
reg [7:0] rom_q, ram_q;

wire        ld_ram_wr = ioctl_download && ioctl_wr && (ld_ch8 || ld_bin);
wire [11:0] ld_addr   = ld_ch8 ? ioctl_addr[11:0] + 12'h200 : ioctl_addr[11:0];

always @(posedge clk) begin
	if (ioctl_download && ioctl_wr && ld_rom) rom[ioctl_addr[8:0]] <= ioctl_dout;
	rom_q <= rom[addr[8:0]];
end

always @(posedge clk) begin
	if (ld_ram_wr)                       ram[ld_addr] <= ioctl_dout;
	else if (copy_wr)                    ram[{3'd0, copy_dst}] <= interp_q;
	else if (ce && !mwr_n && ram_cs)     ram[addr] <= bus;
	ram_q <= ram[addr];
end

///////////////////////   I/O   //////////////////////////////////

// U11/U12 decode: 61 display off, 69 display on, 62 keypad latch, 63 output port, 6B input port
wire io1   = n == 3'd1;
wire io2   = n == 3'd2;
wire io3   = n == 3'd3;

reg  [3:0] key_latch;
reg  [7:0] out_port, in_port;

always @(posedge clk) begin
	if (!run) out_port <= 0;
	else if (ce && tpb && io3 && !mrd_n) out_port <= bus;

	if (ce && tpb && io2 && !mrd_n) key_latch <= bus[3:0];

	if (io_inst) in_port <= io_in;
end

assign io_out = out_port;

// Data bus: pull-ups read FF when nothing drives it
wire mem_oe = !mrd_n && (rom_cs || ram_cs);
wire inp_oe = io3 && mrd_n;

assign bus = cpu_oe     ? cpu_dout   :
             mem_oe     ? (rom_cs ? rom_q : ram_q) :
             inp_oe     ? in_port    :
             exp_bus_oe ? exp_bus_in :
                          8'hFF;

// EF1 = 1861 DISP STATUS, EF2 = cassette in, EF3 = selected key down, EF4 = I/O port
// TODO: cassette interface (EF2 in, Q out)
assign ef_n = {exp_ef_n[4], exp_ef_n[3] & ~keypad[key_latch], exp_ef_n[2], exp_ef_n[1] & efx_n};

///////////////////////   VIDEO   ////////////////////////////////

cdp1861 pixie
(
	.clk(clk),
	.ce(ce),
	.reset(!run),
	.tpa(tpa),
	.tpb(tpb),
	.sc(sc),
	.bus(bus),
	.disp_on(io1 && mrd_n),
	.disp_off(io1 && !mrd_n),
	.int_n(int_n),
	.dmao_n(dmao_n),
	.efx_n(efx_n),
	.video(pixel),
	.hsync(hsync),
	.vsync(vsync),
	.hblank(hblank),
	.vblank(vblank)
);

///////////////////////   TONE   /////////////////////////////////

// U15 CA555 astable, reset held by Q low. Steady state ~1306 Hz (calculated from Fig. E-3).
// TODO: model the start glide (~1.5 to 1.3 kHz over 20-30 ms) and the ~8 ms stop tail.
localparam TONE_HALF = 674;        // 1760640 / (2 * 1306)

reg [9:0] tone_cnt;
reg       tone;

always @(posedge clk) begin
	if (!q) begin
		tone_cnt <= 0;
		tone     <= 1;
	end
	else if (ce) begin
		if (tone_cnt == TONE_HALF - 1) begin
			tone_cnt <= 0;
			tone     <= ~tone;
		end
		else tone_cnt <= tone_cnt + 1'd1;
	end
end

assign audio = !q ? 8'sd0 : tone ? 8'sd64 : -8'sd64;

///////////////////////   EXPANSION   ////////////////////////////

assign exp_ma     = ma;
assign exp_tpa    = tpa;
assign exp_tpb    = tpb;
assign exp_mrd_n  = mrd_n;
assign exp_mwr_n  = mwr_n;
assign exp_bus    = bus;
assign exp_n      = n;
assign exp_sc     = sc;
assign exp_run    = run;
assign exp_cs     = rom_cs;        // TODO: confirm pad X polarity from Fig. E-2
assign exp_cdef_n = !(a_hi[3:2] == 2'b11);

endmodule
