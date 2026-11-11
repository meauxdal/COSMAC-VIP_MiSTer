// RCA VP-601 / VP-611 ASCII keyboard on the Table II I/O port.
// 7-bit ASCII on IN 0-6 (IN 7 low), strobed into U25 on key down. The status
// line is low while the key is held; data stays until the next key.
// Two-key rollover, no auto-repeat (PS/2 typematic is dropped).
// TODO: strobe/status timing and IN 7 are not confirmed against the VP-601
// manual.

module vip_ascii_kbd
#(
	parameter [7:0] BKSP = 8'h7F    // Backspace key code
)
(
	input         clk,
	input         reset,
	input  [10:0] ps2_key,          // hps_io: toggle, pressed, extended, code

	output  [7:0] data,             // to io_in
	output reg    strobe,           // to io_inst, one clk
	output        ef_n              // low while a key is down
);

localparam [7:0] NONE = 8'hFF;

// US layout, set 2: {shifted, unshifted}
function [15:0] lut(input [7:0] code);
	case (code)
		8'h1C: lut = "Aa";
		8'h32: lut = "Bb";
		8'h21: lut = "Cc";
		8'h23: lut = "Dd";
		8'h24: lut = "Ee";
		8'h2B: lut = "Ff";
		8'h34: lut = "Gg";
		8'h33: lut = "Hh";
		8'h43: lut = "Ii";
		8'h3B: lut = "Jj";
		8'h42: lut = "Kk";
		8'h4B: lut = "Ll";
		8'h3A: lut = "Mm";
		8'h31: lut = "Nn";
		8'h44: lut = "Oo";
		8'h4D: lut = "Pp";
		8'h15: lut = "Qq";
		8'h2D: lut = "Rr";
		8'h1B: lut = "Ss";
		8'h2C: lut = "Tt";
		8'h3C: lut = "Uu";
		8'h2A: lut = "Vv";
		8'h1D: lut = "Ww";
		8'h22: lut = "Xx";
		8'h35: lut = "Yy";
		8'h1A: lut = "Zz";

		8'h16: lut = "!1";
		8'h1E: lut = "@2";
		8'h26: lut = "#3";
		8'h25: lut = "$4";
		8'h2E: lut = "%5";
		8'h36: lut = "^6";
		8'h3D: lut = "&7";
		8'h3E: lut = "*8";
		8'h46: lut = "(9";
		8'h45: lut = ")0";

		8'h0E: lut = "~`";
		8'h4E: lut = "_-";
		8'h55: lut = "+=";
		8'h54: lut = "{[";
		8'h5B: lut = "}]";
		8'h5D: lut = {8'h7C, 8'h5C};    // | backslash
		8'h4C: lut = ":;";
		8'h52: lut = {8'h22, 8'h27};    // " '
		8'h41: lut = "<,";
		8'h49: lut = ">.";
		8'h4A: lut = "?/";

		8'h29: lut = "  ";
		8'h5A: lut = {2{8'h0D}};        // Enter
		8'h0D: lut = {2{8'h09}};        // Tab
		8'h76: lut = {2{8'h1B}};        // Esc
		8'h66: lut = {2{BKSP}};

		// VP-611 numeric pad
		8'h70: lut = "00";
		8'h69: lut = "11";
		8'h72: lut = "22";
		8'h7A: lut = "33";
		8'h6B: lut = "44";
		8'h73: lut = "55";
		8'h74: lut = "66";
		8'h6C: lut = "77";
		8'h75: lut = "88";
		8'h7D: lut = "99";
		8'h71: lut = "..";
		8'h79: lut = "++";
		8'h7B: lut = "--";
		8'h7C: lut = "**";

		default: lut = {2{NONE}};
	endcase
endfunction

wire       pressed = ps2_key[9];
wire       ext     = ps2_key[8];
wire [7:0] code    = ps2_key[7:0];

// Extended codes alias the numeric pad (arrows etc.); only these three count
wire [15:0] ext_lut = code == 8'h4A ? "//" :            // keypad /
                      code == 8'h5A ? {2{8'h0D}} :      // keypad Enter
                      code == 8'h71 ? {2{8'h7F}} :      // Delete
                                      {2{NONE}};
wire [15:0] pair    = ext ? ext_lut : lut(code);

reg lshift = 0, rshift = 0, lctrl = 0, rctrl = 0;
reg alpha_lock = 1;             // Caps Lock toggles; on = upper case only
wire shift = lshift | rshift;
wire ctrl  = lctrl | rctrl;

wire       letter = pair[7:0] >= "a" && pair[7:0] <= "z";
wire [7:0] plain  = (shift || (alpha_lock && letter)) ? pair[15:8] : pair[7:0];
// CTRL clears bits 6 and 5 of codes 40-7F
wire [6:0] ascii  = (ctrl && plain[6]) ? {2'b00, plain[4:0]} : plain[6:0];

reg       ps2_old = 0;
reg       down = 0;
reg [8:0] held;                 // {ext, code} of the key that is down
reg [6:0] latch = 0;

always @(posedge clk) begin
	strobe  <= 0;
	ps2_old <= ps2_key[10];

	if (ps2_old != ps2_key[10]) begin
		if (!ext && code == 8'h12) lshift <= pressed;   // E0 12 is a fake shift
		if (!ext && code == 8'h59) rshift <= pressed;
		if (code == 8'h14) begin
			if (ext) rctrl <= pressed;
			else     lctrl <= pressed;
		end
		if (!ext && code == 8'h58 && pressed) alpha_lock <= ~alpha_lock;

		if (pair[7:0] != NONE) begin
			if (pressed) begin
				if (!(down && held == {ext, code})) begin
					latch  <= ascii;
					strobe <= 1;
					down   <= 1;
					held   <= {ext, code};
				end
			end
			else if (held == {ext, code}) down <= 0;
		end
	end

	if (reset) down <= 0;
end

assign data = {1'b0, latch};
assign ef_n = ~down;

endmodule
