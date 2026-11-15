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

// ioctl indexes: boot0.rom = 0x00 (monitor), boot1.rom = 0x40 (CHIP-8 interpreter),
// boot2.rom = 0x80 (CHIP-8X interpreter), F1 = 1, F2 = 2, monitor = 3, F4 = 4
`include "build_id.v"
// OSD lines are 28 chars wide, options include a colon, so 27
localparam CONF_STR = {
	"COSMAC-VIP;;",
	"-;",


	// === LOAD ===
	"F1,CH8,Load CHIP-8;",
	"F4,C8X,Load CHIP-8X;",
	"F2,BIN,Load Binary;",
	"-;",

	// === INPUT ===
	"P1,Input;",
	"P1O[16],Joystick,8-way,CHIP-8;",
	"P1O[18],Keyboard,Hex keypads,ASCII;",

	// === VIDEO ===
	"P2,Video;",
	"P2O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"P2O[8:7],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"P2O[6],Borders,Show,Hide;",
	"d0P2O[9],Vertical crop,Off,216p (5x);",
	"d0P2O[13:10],Crop offset,0,2,4,6,8,10,12,-12,-10,-8,-6,-4,-2;",
	"D1P2O[15:14],B/W palette,White,Amber,Green,Inverted;",

	// === SYSTEM ===
	"P3,System;",
	"P3O[2:1],RAM,4K,2K,32K;",
	"P3O[20:19],Color board,Auto,None,VP-590;",
	"P3O[22:21],Sound board,Auto,None,VP-595;",
	"P3F3,ROMBIN,Load ROM (8000-FFFF);",
	"P3-;",
	"P3O[27:23],Reset key,Auto,None,C (Monitor),3 (Life),4 (Black Jack),A,D,E,F;",
	"P3T[0],Reset;",
	"-;",

	// === RESET ===
	"R[0],Reset and close OSD;",
	"J1,Fire,Extra;",
	"jn,A,B;",
	// === VERSION ===
	"v,0;",
	"V,v",`BUILD_DATE
};

wire         forced_scandoubler;
wire  [21:0] gamma_bus;
wire   [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;
wire  [31:0] joystick_0, joystick_1;

wire         ioctl_download;
wire  [15:0] ioctl_index;
wire         ioctl_wr;
wire  [26:0] ioctl_addr;
wire   [7:0] ioctl_dout;

// Board selects. Auto: fitted while the last program loaded was a .c8x
// (CHIP-8X expects the VP-590 and VP-595), absent after a .ch8 or .bin.
// Bits 3 and 17 held the old None/VP-590 and None/VP-595 options; left unused.
reg          c8x_mode = 0;
always @(posedge clk_sys)
	if (ioctl_download && ioctl_index[7:0] == 8'h04) c8x_mode <= 1;
	else if (ioctl_download && (ioctl_index[7:0] == 8'h01 || ioctl_index[7:0] == 8'h02)) c8x_mode <= 0;

wire         color_board = status[20:19] == 2'd0 ? c8x_mode : status[20:19] == 2'd2;
wire         sound_board = status[22:21] == 2'd0 ? c8x_mode : status[22:21] == 2'd2;
wire         border_hide = status[6];
reg          en216p = 0;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask({color_board, en216p && !border_hide}),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(0),

	.ps2_key(ps2_key),
	.joystick_0(joystick_0),
	.joystick_1(joystick_1)
);

///////////////////////   CLOCKS   ///////////////////////////////

// clk_sys is 8x the CPU clock: 28.17024 MHz on a plain VIP (3.52128 MHz
// crystal / 2), 28.636364 MHz with the VP-590, whose 1862 drives the bus
// CLOCK line at 7.15909 MHz / 4. Keeping the pixel enable at exactly every 4th
// clk_sys holds the OSD steady: it draws on clk_video with a fixed pixel
// length, and a jittery CE_PIXEL makes the scaler sample its edges unevenly.
// The PLL's fractional M (K) is rewritten through pll_cfg when the board
// changes; M 8, N 1, C 15 stay, so VCO = 50 MHz * (8 + K / 2^32).
localparam [31:0] K_VIP = 32'd1937339402;   // VCO 422.5536 MHz
localparam [31:0] K_590 = 32'd2537935220;   // VCO 429.5455 MHz

wire        clk_sys;
wire [63:0] reconfig_to_pll, reconfig_from_pll;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.locked(),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);

wire        cfg_waitrequest;
reg         cfg_write = 0;
reg   [5:0] cfg_address = 0;
reg  [31:0] cfg_data = 0;

pll_cfg pll_cfg
(
	.mgmt_clk(CLK_50M),
	.mgmt_reset(0),
	.mgmt_waitrequest(cfg_waitrequest),
	.mgmt_read(0),
	.mgmt_readdata(),
	.mgmt_write(cfg_write),
	.mgmt_address(cfg_address),
	.mgmt_writedata(cfg_data),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);

// Board select into the CLK_50M domain; a write of K (reg 7) then start (2)
reg   [2:0] col_s = 0;
reg         col_pll = 0;        // the board the PLL is set for
reg         col_tgt = 0;
reg   [1:0] cfg_st = 0;
always @(posedge CLK_50M) begin
	col_s     <= {col_s[1:0], color_board};
	cfg_write <= 0;
	if (!cfg_waitrequest && !cfg_write) begin
		case (cfg_st)
			2'd0: if (col_s[2] != col_pll) begin
				col_tgt     <= col_s[2];
				cfg_address <= 6'd0;            // waitrequest mode
				cfg_data    <= 32'd0;
				cfg_write   <= 1;
				cfg_st      <= 2'd1;
			end
			2'd1: begin
				cfg_address <= 6'd7;
				cfg_data    <= col_tgt ? K_590 : K_VIP;
				cfg_write   <= 1;
				cfg_st      <= 2'd2;
			end
			2'd2: begin
				cfg_address <= 6'd2;
				cfg_data    <= 32'd0;
				cfg_write   <= 1;
				cfg_st      <= 2'd3;
			end
			2'd3: begin
				col_pll <= col_tgt;
				cfg_st  <= 2'd0;
			end
		endcase
	end
end

// Pixel enable every 4th clk_sys, the CPU every 4th pixel
reg   [1:0] ce_cnt = 0;
reg   [1:0] ce_div = 0;
reg         ce_pix = 0;
always @(posedge clk_sys) begin
	ce_cnt <= ce_cnt + 1'd1;
	ce_pix <= &ce_cnt;
	if (ce_pix) ce_div <= ce_div + 1'd1;
end

wire ce_cpu = ce_pix && &ce_div;

// F3 is the RUN switch: held = RESET, released = RUN. Keypad keys held
// through the release pick the boot path, as on a real VIP (C = monitor),
// so this reset never adds the OSD "Reset key".
reg run_sw = 0;
reg ps2_old_rs = 0;
always @(posedge clk_sys) begin
	ps2_old_rs <= ps2_key[10];
	if (ps2_old_rs != ps2_key[10] && !ps2_key[8] && ps2_key[7:0] == 8'h04)
		run_sw <= ps2_key[9];
end

// RUN switch down while any reset source is active
wire reset = RESET | status[0] | buttons[1] | ioctl_download | run_sw;

///////////////////////   KEYPAD   ///////////////////////////////

// PC keys -> VIP hex keypad and VP-580 second keypad, same physical layout:
//   1 2 3 4    7 8 9 0    1 2 3 C
//   Q W E R    U I O P    4 5 6 D
//   A S D F    J K L ;    7 8 9 E
//   Z X C V    M , . /    A 0 B F
reg [15:0] keypad = 0;
reg [15:0] keypad2 = 0;
reg        ps2_old = 0;
wire       ascii_kbd = status[18];
always @(posedge clk_sys) begin
	ps2_old <= ps2_key[10];
	if (ascii_kbd) begin
		keypad  <= 0;
		keypad2 <= 0;
	end
	else if (ps2_old != ps2_key[10] && !ps2_key[8]) begin
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

			8'h3D: keypad2[4'h1] <= ps2_key[9];
			8'h3E: keypad2[4'h2] <= ps2_key[9];
			8'h46: keypad2[4'h3] <= ps2_key[9];
			8'h45: keypad2[4'hC] <= ps2_key[9];
			8'h3C: keypad2[4'h4] <= ps2_key[9];
			8'h43: keypad2[4'h5] <= ps2_key[9];
			8'h44: keypad2[4'h6] <= ps2_key[9];
			8'h4D: keypad2[4'hD] <= ps2_key[9];
			8'h3B: keypad2[4'h7] <= ps2_key[9];
			8'h42: keypad2[4'h8] <= ps2_key[9];
			8'h4B: keypad2[4'h9] <= ps2_key[9];
			8'h4C: keypad2[4'hE] <= ps2_key[9];
			8'h3A: keypad2[4'hA] <= ps2_key[9];
			8'h41: keypad2[4'h0] <= ps2_key[9];
			8'h49: keypad2[4'hB] <= ps2_key[9];
			8'h4A: keypad2[4'hF] <= ps2_key[9];
			default: ;
		endcase
	end
end

// The VIP enters the monitor only if key C is held when RUN goes up, and ROMs
// such as J-VIP pick other boot paths by other held keys. The OSD swallows
// keys, so the core holds one key for ~0.25 s after a reset (not the F3 RUN
// switch, where the player holds the keys). "Reset key":
//   Auto:   C until a CH8/C8X/BIN is loaded, then none, until the core is
//           reloaded
//   None:   never hold a key (run the program in RAM)
//   C, 3, 4, A, D, E, F: always hold that key, except on the reset of a
//           program load. Only keys a known ROM uses are listed: J-VIP 3 =
//           Life, 4 = Black Jack, A/E/F = copy CHIP-8 (with Pinball / Animal
//           Race) to RAM, D = serial monitor. The field keeps 5 bits so more
//           keys can be appended without moving saved settings.
// The reset that ends a program load always starts the program, like a real
// VIP reset without C.
wire       ld_prog = ioctl_download && (ioctl_index[7:0] == 8'h01 || ioctl_index[7:0] == 8'h02 ||
                                        ioctl_index[7:0] == 8'h04);
reg        prog_loaded = 0;
always @(posedge clk_sys) if (ld_prog) prog_loaded <= 1;

// OSD index: 0 Auto, 1 None, 2 C, 3 '3', 4 '4', 5 A, 6 D, 7 E, 8 F
wire [4:0] reset_key = status[27:23];
reg  [3:0] hold_key;
always @(*) begin
	case (reset_key)
		5'd3:    hold_key = 4'h3;
		5'd4:    hold_key = 4'h4;
		5'd5:    hold_key = 4'hA;
		5'd6:    hold_key = 4'hD;
		5'd7:    hold_key = 4'hE;
		5'd8:    hold_key = 4'hF;
		default: hold_key = 4'hC;
	endcase
end
wire       hold_en   = !ld_prog && reset_key != 5'd1 && !(reset_key == 5'd0 && prog_loaded);
reg [18:0] hold = 0;
always @(posedge clk_sys) begin
	if (reset) hold <= hold_en && !run_sw ? 19'h7FFFF : 19'd0;
	else if (ce_cpu && hold) hold <= hold - 1'd1;
end

// Pad 1 is the VIP keypad, pad 2 the VP-580 second keypad
wire [15:0] joy_keys, joy2_keys;
vip_joystick vip_joystick
(
	.joy(joystick_0),
	.profile(status[16]),
	.keys(joy_keys)
);

vip_joystick vip_joystick2
(
	.joy(joystick_1),
	.profile(status[16]),
	.keys(joy2_keys)
);

wire [15:0] keys  = keypad | joy_keys | ({15'd0, |hold} << hold_key);
wire [15:0] keys2 = keypad2 | joy2_keys;

// The ASCII keyboard takes the PC keys from the keypads and EF4 from the
// second keypad: both use the I/O port flag line.
wire [7:0] kbd_data;
wire       kbd_strobe, kbd_ef_n;

vip_ascii_kbd vip_ascii_kbd
(
	.clk(clk_sys),
	.reset(reset),
	.ps2_key(ps2_key),
	.data(kbd_data),
	.strobe(kbd_strobe),
	.ef_n(kbd_ef_n)
);

///////////////////////   CORE   /////////////////////////////////

wire        q;
wire        pixel;
wire        vid_dma_stb, vid_disp_en;
wire  [2:0] vid_dma_idx, vid_dot_idx;
wire  [7:0] exp_ma, exp_bus;
wire  [2:0] exp_n;
wire        exp_tpa, exp_tpb, exp_mrd_n, exp_mwr_n, exp_run;
wire  [7:0] ram_bus;
wire        ram_oe, ram_indis;
wire        key2_ef4_n;
wire        hsync, vsync, hblank, vblank, win_hblank, win_vblank;
wire signed [7:0] audio;

vip_core vip_core
(
	.clk(clk_sys),
	.ce(ce_cpu),
	.reset(reset),
	.ram_2k(status[2:1] == 2'd1),

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
	.exp_bus_in(ram_bus),
	.exp_bus_oe(ram_oe),
	.exp_indis(ram_indis),
	.exp_int_n(1'b1),
	.exp_dma_in_n(1'b1),
	.exp_dma_out_n(1'b1),
	.exp_ef_n({ascii_kbd ? kbd_ef_n : key2_ef4_n, 3'b111}),

	.io_out(),
	.io_in(kbd_data),
	.io_inst(kbd_strobe && ascii_kbd),

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
	.vblank(vblank),
	.win_hblank(win_hblank),
	.win_vblank(win_vblank)
);

///////////////////////   VP-570   ///////////////////////////////

vp570 vp570
(
	.clk(clk_sys),
	.ce(ce_cpu),
	.enable(status[2:1] == 2'd2),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index[7:0]),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr[15:0]),
	.ioctl_dout(ioctl_dout),

	.ma(exp_ma),
	.tpa(exp_tpa),
	.mrd_n(exp_mrd_n),
	.mwr_n(exp_mwr_n),
	.bus(exp_bus),
	.bus_out(ram_bus),
	.bus_oe(ram_oe),
	.indis(ram_indis)
);

///////////////////////   VP-585   ///////////////////////////////

vp585 vp585
(
	.clk(clk_sys),
	.ce(ce_cpu),
	.tpb(exp_tpb),
	.mrd_n(exp_mrd_n),
	.bus(exp_bus),
	.n(exp_n),
	.keypad_b(keys2),
	.ef4_n(key2_ef4_n)
);

///////////////////////   VP-595   ///////////////////////////////

wire signed [7:0] snd_audio;

vp595 vp595
(
	.clk(clk_sys),
	.ce(ce_cpu),
	.reset(!exp_run),
	.tpb(exp_tpb),
	.mrd_n(exp_mrd_n),
	.bus(exp_bus),
	.n(exp_n),
	.q(q),
	.audio(snd_audio)
);

///////////////////////   VP-590   ///////////////////////////////

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

// B/W palettes for the 1-bit path: {dot on, dot off}
reg [47:0] bw_pal;
always @(*) begin
	case (status[15:14])
		2'd0: bw_pal = {24'hFFFFFF, 24'h000000};
		2'd1: bw_pal = {24'hFFBF5A, 24'h000000};
		2'd2: bw_pal = {24'h8FFF63, 24'h000000};
		2'd3: bw_pal = {24'h000000, 24'hFFFFFF};
	endcase
end

// VP-590 background channels at reduced luminance (0x80), as in StudioII
wire  [7:0] col_on  = col_bg ? 8'h80 : 8'hFF;
wire [23:0] col_out = {col_rgb[2] ? col_on : 8'h00,
                       col_rgb[1] ? col_on : 8'h00,
                       col_rgb[0] ? col_on : 8'h00};
wire [23:0] bw_out  = pixel ? bw_pal[47:24] : bw_pal[23:0];
wire [23:0] rgb     = color_board ? col_out : bw_out;

// Borders hidden: only the 64x128 bitmap window is displayed
wire vid_hblank  = border_hide ? win_hblank : hblank;
wire vid_vblank  = border_hide ? win_vblank : vblank;

// ce_pix gives 4 samples per 1861 dot (384 px line). The scandoubler gets 2
// (192 px), which fits its LINE_LENGTH.
wire ce_vid = forced_scandoubler ? (ce_pix & ce_div[0]) : ce_pix;
wire vga_de;

assign CLK_VIDEO = clk_sys;

video_mixer #(.LINE_LENGTH(192), .GAMMA(1)) video_mixer
(
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.ce_pix(ce_vid),
	.scandoubler(forced_scandoubler),
	.hq2x(1'b0),
	.gamma_bus(gamma_bus),
	.R(rgb[23:16]),
	.G(rgb[15:8]),
	.B(rgb[7:0]),
	.HSync(hsync),
	.VSync(vsync),
	.HBlank(vid_hblank),
	.VBlank(vid_vblank),
	.HDMI_FREEZE(HDMI_FREEZE),
	.freeze_sync(),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_VS(VGA_VS),
	.VGA_HS(VGA_HS),
	.VGA_DE(vga_de)
);

// 5x 216p crop at 1920x1080. With borders shown 224 lines are visible, so
// 216 leaves 44 border lines above and below the 128-line bitmap. The offset
// moves the window by -12 to +12 lines in steps of 2 (index 0-6 up from 0,
// 7-12 from -12), like the Studio II core.
reg [4:0] crop_off = 0;
always @(posedge CLK_VIDEO) begin
	en216p   <= HDMI_WIDTH == 12'd1920 && HDMI_HEIGHT == 12'd1080 && !forced_scandoubler;
	crop_off <= (status[13:10] < 4'd7) ? {status[13:10], 1'b0} : {status[13:10], 1'b0} - 5'd26;
end

// VSync one pixel later, so the DE falling edge and the VSync rising edge
// fall on separate pixel enables in video_freak
reg vf_vs = 0;
always @(posedge CLK_VIDEO) if (CE_PIXEL) vf_vs <= VGA_VS;

// Both boards make a 112 x 262 raster, so a CRT shows the same 1861 dot:
// 390/112 square pixels wide (NTSC, 240 lines) by 262.5/262 lines high. That
// gives 213:143 for the 96x224 frame and 1703:980 for the 64x128 bitmap.
wire  [1:0] ar     = status[122:121];
wire  [1:0] scale  = status[8:7];
wire [11:0] orig_x = border_hide ? 12'd1703 : 12'd213;
wire [11:0] orig_y = border_hide ? 12'd980  : 12'd143;
wire        orig   = !ar || scale;

video_freak video_freak
(
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.VGA_VS(vf_vs),
	.HDMI_WIDTH(HDMI_WIDTH),
	.HDMI_HEIGHT(HDMI_HEIGHT),
	.VGA_DE(VGA_DE),
	.VIDEO_ARX(VIDEO_ARX),
	.VIDEO_ARY(VIDEO_ARY),
	.VGA_DE_IN(vga_de),
	.ARX(orig ? orig_x : {10'd0, ar - 1'd1}),
	.ARY(orig ? orig_y : 12'd0),
	.CROP_SIZE((en216p && status[9]) ? 12'd216 : 12'd0),
	.CROP_OFF(crop_off),
	.SCALE({1'b0, scale})
);

///////////////////////   AUDIO   ////////////////////////////////

assign AUDIO_S   = 1;
assign AUDIO_MIX = 0;
// The VP-595 replaces the on-board tone
wire signed [7:0] audio_out = sound_board ? snd_audio : audio;

assign AUDIO_L   = {audio_out, 8'd0};
assign AUDIO_R   = {audio_out, 8'd0};

assign LED_USER = q;

endmodule
