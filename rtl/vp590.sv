// RCA VP-590 Color Board: CDP1862 color generator, CDP1822 color RAM (256 x 3).
// Color RAM is write-only at C000-DFFF. A write at D000-DFFF gives one cell per
// display byte (8 x 32); C000-CFFF ignores A3/A4 (8 x 8 cells). The last write
// selects the mode. Color bits: 0 = R, 1 = B, 2 = G. OUT 5 steps the
// background: blue, black, green, red. Dots stay white until the first color
// RAM write (CON); the background shows only while the display and color are
// on.
// The board's 1862 drives the bus CLOCK line (7.15909 MHz / 4 = 1.7897725 MHz,
// per the VIPER 2.03.17 schematic); COSMAC-VIP.sv switches the CPU clock enable
// to that rate while the board is selected.

module vp590
(
	input            clk,
	input            ce,
	input            reset,

	// Expansion interface
	input      [7:0] ma,
	input            tpa,
	input            tpb,
	input            mrd_n,
	input            mwr_n,
	input      [7:0] bus,
	input      [2:0] n,

	// 1861 line buffer slots and video
	input            dma_stb,
	input      [2:0] dma_idx,
	input      [2:0] dot_idx,
	input            disp_en,
	input            luma,
	input            blank,

	output reg [2:0] rgb,         // {R,G,B}
	output reg       bckgnd       // rgb is background (reduced luminance)
);

reg  [7:4] a_hi;
reg        a12, con;
reg  [1:0] bg_idx;
reg  [2:0] cram[256];
reg  [2:0] cbuf[8];
reg  [7:0] cbuf_con;
reg  [2:0] dot_col;
reg        dot_con;

wire [7:0] cmask  = a12 ? 8'hFF : 8'hE7;
wire       cram_w = !mwr_n && a_hi[7:5] == 3'b110;
wire [7:0] wmask  = a_hi[4] ? 8'hFF : 8'hE7;

always @(posedge clk) begin
	if (reset) begin
		con    <= 0;
		bg_idx <= 0;
	end
	else if (ce) begin
		if (tpa) a_hi <= ma[7:4];

		if (cram_w) begin
			cram[ma & wmask] <= bus[2:0];
			a12 <= a_hi[4];
			con <= 1;
		end

		if (tpb && n == 3'd5 && !mrd_n) bg_idx <= bg_idx + 1'd1;

		if (dma_stb) begin
			cbuf[dma_idx]     <= cram[ma & cmask];
			cbuf_con[dma_idx] <= con;
		end

		dot_col <= cbuf[dot_idx];
		dot_con <= cbuf_con[dot_idx];
	end
end

reg [2:0] bg_col;
always @(*) begin
	case (bg_idx)
		2'd0:    bg_col = 3'b001;
		2'd1:    bg_col = 3'b000;
		2'd2:    bg_col = 3'b010;
		default: bg_col = 3'b100;
	endcase
end

always @(*) begin
	bckgnd = 0;
	if (blank)       rgb = 3'b000;
	else if (luma)   rgb = dot_con ? {dot_col[0], dot_col[2], dot_col[1]} : 3'b111;
	else if (disp_en && con) begin
		rgb    = bg_col;
		bckgnd = 1;
	end
	else             rgb = 3'b000;
end

endmodule
