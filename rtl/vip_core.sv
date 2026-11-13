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
	output        vid_dma_stb,    // 1861 line buffer slots, for a color board
	output  [2:0] vid_dma_idx,
	output  [2:0] vid_dot_idx,
	output        vid_disp_en,
	output        hsync,
	output        vsync,
	output        hblank,
	output        vblank,
	output        win_hblank,
	output        win_vblank
);

///////////////////////   LOADER   ///////////////////////////////

// ioctl indexes: 0x00 boot0.rom / 3 OSD = monitor ROM (up to 32K at 8000),
// 0x40 boot1.rom = CHIP-8 interpreter (512 bytes),
// 0x80 boot2.rom = CHIP-8X interpreter (768 bytes, VP-590/595 manual ch. II),
// 1 = .CH8 (RAM 0200), 4 = .C8X (RAM 0300): the matching interpreter is copied
// to 0000 afterwards, as if loaded from tape first. 2 = .BIN (RAM 0000).
wire ld_rom      = ioctl_index == 8'h00 || ioctl_index == 8'h03;
wire ld_interp   = ioctl_index == 8'h40;
wire ld_interp8x = ioctl_index == 8'h80;
wire ld_ch8      = ioctl_index == 8'h01;
wire ld_c8x      = ioctl_index == 8'h04;
wire ld_bin      = ioctl_index == 8'h02;

// Interpreter store: CHIP-8 at 000-1FF, CHIP-8X at 400-6FF
reg  [7:0] interp[2048];
reg  [7:0] interp_q;
reg  [9:0] copy_cnt = 0;
reg  [9:0] copy_end = 0;           // copy_cnt == copy_end = idle
reg        copy_8x;
reg  [9:0] copy_dst;
reg        copy_wr;
reg        dl_old;

wire copy_run  = copy_cnt != copy_end;
wire copy_busy = copy_run || copy_wr;

always @(posedge clk) begin
	dl_old <= ioctl_download;
	if (ioctl_download && ioctl_wr && ld_interp && ioctl_addr[15:9] == 0)
		interp[{2'b00, ioctl_addr[8:0]}] <= ioctl_dout;
	if (ioctl_download && ioctl_wr && ld_interp8x && ioctl_addr[15:0] < 16'h300)
		interp[{1'b1, ioctl_addr[9:0]}] <= ioctl_dout;

	interp_q <= interp[{copy_8x, copy_cnt}];
	copy_dst <= copy_cnt;
	copy_wr  <= copy_run;
	if (dl_old && !ioctl_download && (ld_ch8 || ld_c8x)) begin
		copy_cnt <= 0;
		copy_end <= ld_c8x ? 10'h300 : 10'h200;
		copy_8x  <= ld_c8x;
	end
	else if (copy_run) copy_cnt <= copy_cnt + 1'd1;
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
// U6B: held set by U6A, otherwise latches A15 at TPA. U8 latches A8-A11 at TPA;
// A12-A14 are latched too, for a ROM larger than the stock 512 bytes.
reg       u6a, u6b;
reg [6:0] a_hi;

// ROM socket: the stock 512-byte monitor, or a larger EPROM up to 32K
// (8000-FFFF) such as J-VIP. The image mirrors at its size rounded up to a
// power of two, so 512 bytes behaves exactly like the stock part. A ROM
// load sets the size; the next core load restores boot0.rom.
reg  [7:0] rom[32768];
reg [14:0] rom_top = 15'h01FF;
reg [14:0] rom_mask = 15'h01FF;

// A ROM larger than 512 bytes is taken as a J-VIP / VIP-S board (Bensadon and
// Miraglia, 2015; VIP-S 1b schematic): there RESET sets a U6B/U6C latch that
// any memory read with A15 high clears (U6D). J-VIP relies on it, since its
// no-key boot path jumps to 0000 without an N2 OUT.
wire rom_big = rom_mask[9];
reg  a15;

always @(posedge clk) begin
	if (!run) u6a <= 0;
	else if (ce && tpb && n[2]) u6a <= 1;
	else if (ce && tpb && !mrd_n && a15 && rom_big) u6a <= 1;

	if (!u6a) u6b <= 1;
	else if (ce && tpa) u6b <= ma[7];

	if (ce && tpa) {a15, a_hi} <= ma;
end

wire [11:0] addr     = {a_hi[3:0], ma};
wire        rom_cs   = u6b;
wire        ram_sect = !ram_2k || !a_hi[3];             // 2K board has sections 0-1 only
wire        ram_cs   = !rom_cs && !exp_indis && ram_sect;

reg  [7:0] ram[4096];
reg  [7:0] rom_q, ram_q;

wire [14:0] rom_smear = rom_top | rom_top >> 1 | rom_top >> 2 | rom_top >> 4 | rom_top >> 8;
wire [14:0] rom_addr  = {a_hi, ma} & rom_mask;

// Files reaching past 0FFF continue in expansion RAM (vp570)
wire [15:0] ld_full   = ld_ch8 ? ioctl_addr + 16'h200 :
                        ld_c8x ? ioctl_addr + 16'h300 : ioctl_addr;
wire        ld_ram_wr = ioctl_download && ioctl_wr && (ld_ch8 || ld_c8x || ld_bin) && ld_full[15:12] == 4'd0;
wire [11:0] ld_addr   = ld_full[11:0];

always @(posedge clk) begin
	if (ioctl_download && ioctl_wr && ld_rom && !ioctl_addr[15]) begin
		rom[ioctl_addr[14:0]] <= ioctl_dout;
		rom_top <= ioctl_addr[14:0] | 15'h01FF;
	end
	rom_mask <= rom_smear;
	rom_q <= rom[rom_addr];
end

always @(posedge clk) begin
	if (ld_ram_wr)                       ram[ld_addr] <= ioctl_dout;
	else if (copy_wr)                    ram[{2'd0, copy_dst}] <= interp_q;
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
	.dma_stb(vid_dma_stb),
	.dma_idx(vid_dma_idx),
	.dot_idx(vid_dot_idx),
	.disp_en(vid_disp_en),
	.video(pixel),
	.hsync(hsync),
	.vsync(vsync),
	.hblank(hblank),
	.vblank(vblank),
	.win_hblank(win_hblank),
	.win_vblank(win_vblank)
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
