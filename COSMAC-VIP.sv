//============================================================================
//
//  RCA COSMAC VIP (CDP18S711) for MiSTer
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;

wire [1:0] ar = status[122:121];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

// ioctl indexes: boot0.rom = 0x00 (monitor), boot1.rom = 0x40 (CHIP-8 interpreter), F1 = 1, F2 = 2, monitor = 3
`include "build_id.v"
// OSD lines are 28 chars wide, options include a colon, so 27
localparam CONF_STR = {
	"COSMAC-VIP;;",
	"-;",


	// === LOAD ===
	"F1,CH8,Load CHIP-8;",
	"F2,BIN,Load Binary;",
	"-;",

	// === AUDIO & VIDEO ===
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"-;",

	// === SYSTEM ===
	"P1,System;",
	"P1O[1],RAM,4K,2K;",
	"P1O[3],Color board,None,VP-590;",
	"P1O[5:4],Reset to,Auto,Monitor,Program in RAM;",
	"P1F3,ROM,Load Monitor ROM;",
	"-;",

	// === RESET ===
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	// === VERSION ===
	"v,0;",
	"V,v",`BUILD_DATE
};

wire         forced_scandoubler;
wire   [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;

wire         ioctl_download;
wire  [15:0] ioctl_index;
wire         ioctl_wr;
wire  [26:0] ioctl_addr;
wire   [7:0] ioctl_dout;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask(0),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(0),

	.ps2_key(ps2_key)
);

///////////////////////   CLOCKS   ///////////////////////////////

// 28.17024 MHz = 8x the 3.52128 MHz crystal; CPU and 1861 run at crystal / 2.
wire clk_sys;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys)
);

// The pixel enable runs at 4x the CPU clock. A fractional accumulator sets the
// rate: 3.52128 MHz / 2 on a plain VIP (exactly every 4th clk_sys, as before),
// 7.15909 MHz / 4 = 1.7897725 MHz with the VP-590, whose 1862 drives the bus
// CLOCK line. Increments are 4 * f_cpu / clk_sys over the modulus 2817024.
localparam [21:0] CE_MOD     = 22'd2817024;
localparam [21:0] CE_INC_VIP = 22'd704256;   // 1.76064 MHz
localparam [21:0] CE_INC_590 = 22'd715909;   // 1.7897725 MHz

reg  [21:0] ce_acc = 0;
reg   [1:0] ce_div = 0;
reg         ce_pix = 0;
wire [21:0] ce_inc  = status[3] ? CE_INC_590 : CE_INC_VIP;
wire [22:0] ce_next = ce_acc + ce_inc;

always @(posedge clk_sys) begin
	ce_pix <= 0;
	if (ce_next >= CE_MOD) begin
		ce_acc <= ce_next - CE_MOD;
		ce_pix <= 1;
	end
	else ce_acc <= ce_next[21:0];
	if (ce_pix) ce_div <= ce_div + 1'd1;
end

wire ce_cpu = ce_pix && &ce_div;

// RUN switch down while any reset source is active
wire reset = RESET | status[0] | buttons[1] | ioctl_download;

///////////////////////   KEYPAD   ///////////////////////////////

// PC keys -> VIP hex keypad, same physical layout:
//   1 2 3 4    1 2 3 C
//   Q W E R    4 5 6 D
//   A S D F    7 8 9 E
//   Z X C V    A 0 B F
reg [15:0] keypad = 0;
reg        ps2_old = 0;
always @(posedge clk_sys) begin
	ps2_old <= ps2_key[10];
	if (ps2_old != ps2_key[10] && !ps2_key[8]) begin
		case (ps2_key[7:0])
			8'h16: keypad[4'h1] <= ps2_key[9];
			8'h1E: keypad[4'h2] <= ps2_key[9];
			8'h26: keypad[4'h3] <= ps2_key[9];
			8'h25: keypad[4'hC] <= ps2_key[9];
			8'h15: keypad[4'h4] <= ps2_key[9];
			8'h1D: keypad[4'h5] <= ps2_key[9];
			8'h24: keypad[4'h6] <= ps2_key[9];
			8'h2D: keypad[4'hD] <= ps2_key[9];
			8'h1C: keypad[4'h7] <= ps2_key[9];
			8'h1B: keypad[4'h8] <= ps2_key[9];
			8'h23: keypad[4'h9] <= ps2_key[9];
			8'h2B: keypad[4'hE] <= ps2_key[9];
			8'h1A: keypad[4'hA] <= ps2_key[9];
			8'h22: keypad[4'h0] <= ps2_key[9];
			8'h21: keypad[4'hB] <= ps2_key[9];
			8'h2A: keypad[4'hF] <= ps2_key[9];
			default: ;
		endcase
	end
end

// The VIP enters the monitor only if key C is held when RUN goes up. The OSD
// swallows keys, so the core holds C for ~0.25 s after a reset that should
// enter the monitor. "Reset to" picks which resets those are:
//   Auto:           monitor until a CH8/BIN is loaded, then the program, until
//                   the core is reloaded
//   Monitor:        always the monitor, except the reset of the load itself
//   Program in RAM: never hold C
// The reset that ends a CH8/BIN load always starts the program, like a real
// VIP reset without C.
wire       ld_prog = ioctl_download && (ioctl_index[7:0] == 8'h01 || ioctl_index[7:0] == 8'h02);
reg        prog_loaded = 0;
always @(posedge clk_sys) if (ld_prog) prog_loaded <= 1;

wire [1:0] reset_to = status[5:4];
wire       to_prog  = ld_prog || reset_to == 2'd2 || (reset_to == 2'd0 && prog_loaded);
reg [18:0] hold_c = 0;
always @(posedge clk_sys) begin
	if (reset) hold_c <= to_prog ? 19'd0 : 19'h7FFFF;
	else if (ce_cpu && hold_c) hold_c <= hold_c - 1'd1;
end

wire [15:0] keys = keypad | {3'b000, |hold_c, 12'h000};

///////////////////////   CORE   /////////////////////////////////

wire        q;
wire        pixel;
wire        vid_dma_stb, vid_disp_en;
wire  [2:0] vid_dma_idx, vid_dot_idx;
wire  [7:0] exp_ma, exp_bus;
wire  [2:0] exp_n;
wire        exp_tpa, exp_tpb, exp_mrd_n, exp_mwr_n, exp_run;
wire        hsync, vsync, hblank, vblank;
wire signed [7:0] audio;

vip_core vip_core
(
	.clk(clk_sys),
	.ce(ce_cpu),
	.reset(reset),
	.ram_2k(status[1]),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index[7:0]),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr[15:0]),
	.ioctl_dout(ioctl_dout),

	.keypad(keys),

	.exp_ma(exp_ma),
	.exp_tpa(exp_tpa),
	.exp_tpb(exp_tpb),
	.exp_mrd_n(exp_mrd_n),
	.exp_mwr_n(exp_mwr_n),
	.exp_bus(exp_bus),
	.exp_n(exp_n),
	.exp_sc(),
	.exp_run(exp_run),
	.exp_cs(),
	.exp_cdef_n(),
	.exp_bus_in(8'hFF),
	.exp_bus_oe(1'b0),
	.exp_indis(1'b0),
	.exp_int_n(1'b1),
	.exp_dma_in_n(1'b1),
	.exp_dma_out_n(1'b1),
	.exp_ef_n(4'hF),

	.io_out(),
	.io_in(8'h00),
	.io_inst(1'b0),

	.q(q),
	.audio(audio),

	.pixel(pixel),
	.vid_dma_stb(vid_dma_stb),
	.vid_dma_idx(vid_dma_idx),
	.vid_dot_idx(vid_dot_idx),
	.vid_disp_en(vid_disp_en),
	.hsync(hsync),
	.vsync(vsync),
	.hblank(hblank),
	.vblank(vblank)
);

///////////////////////   VP-590   ///////////////////////////////

wire       color_board = status[3];
wire [2:0] col_rgb;
wire       col_bg;

vp590 vp590
(
	.clk(clk_sys),
	.ce(ce_cpu),
	.reset(!exp_run),
	.ma(exp_ma),
	.tpa(exp_tpa),
	.tpb(exp_tpb),
	.mrd_n(exp_mrd_n),
	.mwr_n(exp_mwr_n),
	.bus(exp_bus),
	.n(exp_n),
	.dma_stb(vid_dma_stb),
	.dma_idx(vid_dma_idx),
	.dot_idx(vid_dot_idx),
	.disp_en(vid_disp_en),
	.luma(pixel),
	.blank(hblank | vblank),
	.rgb(col_rgb),
	.bckgnd(col_bg)
);

///////////////////////   VIDEO   ////////////////////////////////

// Background channels at reduced luminance (0x80), as in StudioII
wire [7:0] col_on = col_bg ? 8'h80 : 8'hFF;
wire [2:0] rgb    = color_board ? col_rgb : {3{pixel}};

assign CLK_VIDEO = clk_sys;
assign CE_PIXEL  = ce_pix;   // 4 samples per 1861 dot (384 px line, like StudioII); the bare dot rate (96 px) was never tested on hardware

assign VGA_DE = ~(hblank | vblank);
assign VGA_HS = hsync;
assign VGA_VS = vsync;
assign VGA_R  = rgb[2] ? col_on : 8'h00;
assign VGA_G  = rgb[1] ? col_on : 8'h00;
assign VGA_B  = rgb[0] ? col_on : 8'h00;

///////////////////////   AUDIO   ////////////////////////////////

assign AUDIO_S   = 1;
assign AUDIO_MIX = 0;
assign AUDIO_L   = {audio, 8'd0};
assign AUDIO_R   = {audio, 8'd0};

assign LED_USER = q;

endmodule
