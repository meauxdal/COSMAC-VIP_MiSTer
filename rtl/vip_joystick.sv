// Gamepad -> VIP hex keypad. The result is ORed with the PC keyboard.
//
// MiSTer joystick bits, per the CONF_STR "J1,..." list in COSMAC-VIP.sv:
//   [0]=right [1]=left [2]=down [3]=up [4]=Fire [5]=Extra
//
// Profiles:
//   0 = 8-way (from StudioII_MiSTer MAP_8WAY): 2/8/4/6, diagonals 1/3/7/9,
//       Fire 5, Extra 0. A diagonal replaces its two directions, so games that
//       poll 2/8/4/6 one at a time still see a single key.
//   1 = CHIP-8 cluster: up 5, left 7, down 8, right 9, Fire 6, Extra 4.
//       Directions are the most common layout among the chip-8-database
//       programs that list keys (Snake, Space Racer, 3D VIP'r Maze, Danm8ku,
//       ...). Fire and Extra follow that database's a/b entries for the games
//       that use this cluster: a = 6 in Slippery Slope, Knight, Glitch Ghost
//       and Chicken Scratch; b = 4 in Knight and Chicken Scratch.

module vip_joystick
(
	input  [31:0] joy,
	input         profile,
	output [15:0] keys
);

wire right = joy[0];
wire left  = joy[1];
wire down  = joy[2];
wire up    = joy[3];
wire fire  = joy[4];
wire extra = joy[5];

reg [15:0] k;
always @* begin
	k = 16'd0;
	if (!profile) begin
		case ({up, down, left, right})
			4'b1010: k[4'h1] = 1'b1;
			4'b1001: k[4'h3] = 1'b1;
			4'b0110: k[4'h7] = 1'b1;
			4'b0101: k[4'h9] = 1'b1;
			default: begin
				k[4'h2] = up;
				k[4'h8] = down;
				k[4'h4] = left;
				k[4'h6] = right;
			end
		endcase
		k[4'h5] = fire;
		k[4'h0] = extra;
	end
	else begin
		k[4'h5] = up;
		k[4'h8] = down;
		k[4'h7] = left;
		k[4'h9] = right;
		k[4'h6] = fire;
		k[4'h4] = extra;
	end
end

assign keys = k;

endmodule
