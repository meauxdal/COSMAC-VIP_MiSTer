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
localparam CONF_STR = {
	"COSMAC-VIP;;",
	"-;",
	"F1,CH8,Load CHIP-8;",
	"F2,BIN,Load Binary;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"-;",
	"P1,System;",
	"P1O[1],RAM,4K,2K;",
	"P1F3,ROM,Load Monitor ROM;",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
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

reg [3:0] ce_div = 0;
always @(posedge clk_sys) ce_div <= ce_div + 1'd1;
wire ce_cpu = &ce_div;

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

///////////////////////   CORE   /////////////////////////////////

wire        q;
wire        pixel;
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

	.keypad(keypad),

	.exp_ma(),
	.exp_tpa(),
	.exp_tpb(),
	.exp_mrd_n(),
	.exp_mwr_n(),
	.exp_bus(),
	.exp_n(),
	.exp_sc(),
	.exp_run(),
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
	.hsync(hsync),
	.vsync(vsync),
	.hblank(hblank),
	.vblank(vblank)
);

///////////////////////   VIDEO   ////////////////////////////////

assign CLK_VIDEO = clk_sys;
assign CE_PIXEL  = ce_cpu;

assign VGA_DE = ~(hblank | vblank);
assign VGA_HS = hsync;
assign VGA_VS = vsync;
assign VGA_R  = {8{pixel}};
assign VGA_G  = {8{pixel}};
assign VGA_B  = {8{pixel}};

///////////////////////   AUDIO   ////////////////////////////////

assign AUDIO_S   = 1;
assign AUDIO_MIX = 0;
assign AUDIO_L   = {audio, 8'd0};
assign AUDIO_R   = {audio, 8'd0};

assign LED_USER = q;

endmodule
