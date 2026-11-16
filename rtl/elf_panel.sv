// COSMAC Elf front panel on the VIP expansion bus (optional, not part of a
// real VIP). The Elf (Popular Electronics, 1976) and Netronics Elf II use
// port 4, which the VIP leaves undecoded:
//   OUT 4 (64)  latch a byte into the two hex displays
//   INP 4 (6C)  read the eight data switches
//   EF4         IN button, held low while pressed
// Q drives an LED as well as the VIP speaker.
//
// Switches are entered Elf II style: each hex keypad key shifts its digit
// into the low nibble, so 3 then A gives 3A. Enter is the IN button. The
// keys still reach the VIP keypad (EF3), which Elf programs do not read.
//
// The overlay draws the switch LEDs, the two hex digits and the Q LED below
// the 64x128 bitmap, or over its bottom edge when the borders are hidden.

module elf_panel
(
	input         clk,
	input         ce,             // CPU clock enable
	input         ce_pix,         // 4 per 1861 dot
	input         enable,

	// Expansion interface
	input         tpb,
	input         mrd_n,
	input   [7:0] bus,
	input   [2:0] n,
	output  [7:0] bus_out,
	output        bus_oe,
	output        ef4_n,

	input  [15:0] keypad,         // PC hex keypad, one bit per key
	input  [10:0] ps2_key,
	input         q,

	// Video timing from the 1861
	input         hblank,
	input         vblank,
	input         win_hblank,
	input         win_vblank,
	input         border_hide,
	output        draw,
	output [23:0] rgb
);

///////////////////////   PORT 4   ///////////////////////////////

reg  [7:0] leds = 0;
reg  [7:0] sw = 0;
reg        in_btn = 0;
reg [15:0] keypad_d = 0;
reg        ps2_old = 0;

wire [15:0] key_down = keypad & ~keypad_d;

// Lowest newly pressed key; two keys in one clock are not a concern
reg  [3:0] key_hex;
always @(*) begin
	key_hex = 0;
	for (integer i = 15; i >= 0; i = i - 1)
		if (key_down[i]) key_hex = i;
end

always @(posedge clk) begin
	if (ce && tpb && enable && n == 3'd4 && !mrd_n) leds <= bus;

	keypad_d <= keypad;
	if (enable && |key_down) sw <= {sw[3:0], key_hex};

	// Enter, main or keypad (E0 5A)
	ps2_old <= ps2_key[10];
	if (ps2_old != ps2_key[10] && ps2_key[7:0] == 8'h5A)
		in_btn <= ps2_key[9];
end

assign bus_out = sw;
assign bus_oe  = enable && n == 3'd4 && mrd_n;
assign ef4_n   = !(enable && in_btn);

///////////////////////   OVERLAY   //////////////////////////////

// wx, wy count from the top left pixel of the bitmap window and run on past
// it, so the area below the bitmap is wy 128 and up. x_ok, y_ok are low
// until the window has been reached in this line or frame.
reg  [8:0] wx = 0;
reg  [8:0] wy = 0;
reg        x_ok = 0, y_ok = 0;
reg        hb_d = 0;

always @(posedge clk) if (ce_pix) begin
	hb_d <= hblank;

	if (hblank) begin
		x_ok <= 0;
		wx   <= 0;
	end
	else if (x_ok || !win_hblank) begin
		x_ok <= 1;
		wx   <= wx + 1'd1;
	end

	if (vblank) y_ok <= 0;
	else if (!hblank && hb_d) begin             // first pixel of a line
		if (!y_ok && !win_vblank) begin
			y_ok <= 1;
			wy   <= 0;
		end
		else wy <= wy + 1'd1;
	end
end

// Layout, in bitmap pixels (4 per dot across, 1 per line down; a pixel is
// close to square on screen). The panel is 20 lines high:
//   switch LEDs  x  32-95  8 LEDs of 6x6, bit 7 on the left
//   hex digits   x 112-123 and 128-139, 12x20 seven segment
//   Q LED        x 156-161
// with a dark backing box from x 26 to 167 when drawn over the bitmap.
wire [8:0] top = border_hide ? 9'd104 : 9'd138;
wire [8:0] py  = wy - top;
wire       in_rows = y_ok && x_ok && wy >= top && py < 9'd20;

// Seven segment digit in a 12x20 cell; segments are 2 pixels thick
function seg_on(input [3:0] v, input [8:0] dx, input [8:0] dy);
	reg [6:0] s;     // a b c d e f g
	begin
		case (v)
			4'h0: s = 7'b1111110;
			4'h1: s = 7'b0110000;
			4'h2: s = 7'b1101101;
			4'h3: s = 7'b1111001;
			4'h4: s = 7'b0110011;
			4'h5: s = 7'b1011011;
			4'h6: s = 7'b1011111;
			4'h7: s = 7'b1110000;
			4'h8: s = 7'b1111111;
			4'h9: s = 7'b1111011;
			4'hA: s = 7'b1110111;
			4'hB: s = 7'b0011111;
			4'hC: s = 7'b1001110;
			4'hD: s = 7'b0111101;
			4'hE: s = 7'b1001111;
			4'hF: s = 7'b1000111;
		endcase
		seg_on = (s[6] && dy <= 1            && dx >= 2 && dx <= 9) ||
		         (s[5] && dx >= 10           && dy >= 2 && dy <= 8) ||
		         (s[4] && dx >= 10           && dy >= 11 && dy <= 17) ||
		         (s[3] && dy >= 18           && dx >= 2 && dx <= 9) ||
		         (s[2] && dx <= 1            && dy >= 11 && dy <= 17) ||
		         (s[1] && dx <= 1            && dy >= 2 && dy <= 8) ||
		         (s[0] && dy >= 9 && dy <= 10 && dx >= 2 && dx <= 9);
	end
endfunction

// A segment's own shape, lit or not, so unlit segments show dimly
function seg_any(input [8:0] dx, input [8:0] dy);
	seg_any = seg_on(4'h8, dx, dy);
endfunction

wire [8:0] dx_hi = wx - 9'd112;
wire [8:0] dx_lo = wx - 9'd128;
wire       in_hi = wx >= 112 && wx < 124;
wire       in_lo = wx >= 128 && wx < 140;
wire       led_y = py >= 7 && py < 13;

wire [8:0] dx_sw  = wx - 9'd32;
wire       in_sw  = wx >= 32 && wx < 96 && dx_sw[2:0] < 3'd6 && led_y;
wire       sw_bit = sw[3'd7 - dx_sw[5:3]];
wire       in_q   = wx >= 156 && wx < 162 && led_y;

wire       box    = border_hide && wx >= 26 && wx < 168;

localparam [23:0] RED     = 24'hFF2010;
localparam [23:0] RED_DIM = 24'h3A0804;
localparam [23:0] AMBER   = 24'hFFB000;
localparam [23:0] OFF_LED = 24'h302810;
localparam [23:0] BACK    = 24'h101010;

reg        d;
reg [23:0] c;
always @(*) begin
	d = 0;
	c = BACK;
	if (enable && in_rows) begin
		if (in_hi && seg_any(dx_hi, py)) begin
			d = 1;
			c = seg_on(leds[7:4], dx_hi, py) ? RED : RED_DIM;
		end
		else if (in_lo && seg_any(dx_lo, py)) begin
			d = 1;
			c = seg_on(leds[3:0], dx_lo, py) ? RED : RED_DIM;
		end
		else if (in_sw) begin
			d = 1;
			c = sw_bit ? AMBER : OFF_LED;
		end
		else if (in_q) begin
			d = 1;
			c = q ? RED : RED_DIM;
		end
		else if (box) d = 1;
	end
end

assign draw = d;
assign rgb  = c;

endmodule
