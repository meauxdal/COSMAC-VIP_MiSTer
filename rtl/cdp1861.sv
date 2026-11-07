// RCA CDP1861 video display controller (Pixie).
// 14 machine cycles per line, 262 lines per field, display window lines 80-207.
// The line counter advances at the start of cycle 13, so INT/DISP STATUS lead the
// line by one cycle: S3 then lands 29 cycles before the first DMA burst (data sheet).
// DMA REQ starts in cycle 1 (first DMA cycle is the third of the line) and is held
// until eight bytes are loaded, so a late burst still delivers the full line.
// Bytes go to a line buffer and are shifted out at a fixed raster position.

module cdp1861
(
	input            clk,
	input            ce,          // CPU clock
	input            reset,

	input            tpa,
	input            tpb,
	input      [1:0] sc,
	input      [7:0] bus,
	input            disp_on,     // sampled at TPB
	input            disp_off,

	output           int_n,
	output           dmao_n,
	output           efx_n,       // DISP STATUS

	output reg       video,
	output reg       hsync,
	output reg       vsync,
	output reg       hblank,
	output reg       vblank,

	input    [127:0] dbg,         // DEBUG: 8 words drawn on lines 40-55, remove later
	output           dbg_en
);

assign dbg_en = enabled;

localparam LINES       = 262;
localparam DISP_START  = 80;
localparam DISP_END    = 208;

reg  [2:0] ph;
reg  [3:0] cyc;
reg  [8:0] line;
reg        enabled;
reg  [3:0] dcnt;
reg  [7:0] lbuf[8];

wire disp_line = line >= DISP_START && line < DISP_END;
wire dma_cyc   = tpb && sc == 2'd2;

always @(posedge clk) begin
	if (reset) begin
		ph <= 0; cyc <= 0; line <= 0;
		enabled <= 0; dcnt <= 0;
	end
	else if (ce) begin
		ph <= tpa ? 3'd2 : ph + 1'd1;

		if (ph == 7) begin
			if (cyc == 13) cyc <= 0;
			else cyc <= cyc + 1'd1;
			if (cyc == 12) line <= (line == LINES - 1) ? 9'd0 : line + 1'd1;
			if (cyc == 13) dcnt <= 0;
		end

		if (tpb) begin
			if (disp_on)  enabled <= 1;
			if (disp_off) enabled <= 0;
		end

		if (dma_cyc && enabled && disp_line && dcnt < 8) begin
			lbuf[dcnt[2:0]] <= bus;
			dcnt <= dcnt + 1'd1;
		end
	end
end

assign int_n  = !(enabled && line >= DISP_START - 2 && line < DISP_START);
assign efx_n  = !(enabled && ((line >= DISP_START - 4 && line < DISP_START) || (line >= DISP_END - 4 && line < DISP_END)));
assign dmao_n = !(enabled && disp_line && cyc >= 1 && cyc <= 12 && dcnt < 8);

// Raster: byte k is shown in cycle 5+k. Visible area wraps the counter boundary
// (cycles 3-13 and 0) so the 64-dot window is centered; vertical state is taken
// at the start of horizontal blanking.
wire [6:0] hpos = {cyc, ph};
wire [2:0] bidx = cyc[2:0] - 3'd5;

// DEBUG overlay: word k on lines 40+2k..41+2k, bit 15 first, 4 dots per bit (3 lit)
reg  [127:0] dbg_q;
wire [8:0]   dbg_l   = line - 9'd40;
wire [6:0]   dbg_x   = hpos - 7'd40;
wire         dbg_row = line >= 40 && line < 56 && hpos >= 40 && hpos < 104;
wire         dbg_dot = dbg_row && dbg_x[1:0] != 2'd3 && dbg_q[{dbg_l[3:1], 4'd15 - dbg_x[5:2]}];

always @(posedge clk) begin
	if (ce) begin
		if (line == 0 && hpos == 0) dbg_q <= dbg;
		video  <= dbg_dot || (enabled && disp_line && cyc >= 5 && cyc <= 12 && lbuf[bidx][3'd7 - ph]);
		hblank <= hpos >= 8 && hpos < 24;
		hsync  <= hpos >= 12 && hpos < 20;
		if (hpos == 8) begin
			vblank <= line < 32 || line >= 256;
			vsync  <= line >= 4 && line < 8;
		end
	end
end

endmodule
