// RCA COSMAC VIP system: CPU, 1861, memory map, I/O.
// TODO: scaffold stub. Generates 1861-rate sync and outlines the 64x128 display window only.

module vip_core
(
	input         clk,
	input         ce,             // CPU clock enable, 1.76064 MHz
	input         reset,          // RUN switch down
	input         ram_2k,

	input         ioctl_download,
	input   [7:0] ioctl_index,
	input         ioctl_wr,
	input  [15:0] ioctl_addr,
	input   [7:0] ioctl_dout,

	input  [15:0] keypad,

	output        q,
	output  [7:0] audio,

	output        pixel,
	output        hsync,
	output        vsync,
	output        hblank,
	output        vblank
);

// 1861: 14 machine cycles (112 clocks) per line, 262 lines per frame
reg [6:0] hcnt = 0;
reg [8:0] vcnt = 0;

always @(posedge clk) begin
	if (ce) begin
		if (hcnt == 7'd111) begin
			hcnt <= 0;
			vcnt <= (vcnt == 9'd261) ? 9'd0 : vcnt + 1'd1;
		end
		else hcnt <= hcnt + 1'd1;
	end
end

assign hblank = hcnt >= 7'd96;
assign hsync  = hcnt >= 7'd100 && hcnt < 7'd108;
assign vblank = vcnt >= 9'd240;
assign vsync  = vcnt >= 9'd248 && vcnt < 9'd252;

wire in_window = hcnt >= 7'd16 && hcnt < 7'd80 && vcnt >= 9'd56 && vcnt < 9'd184;
wire on_edge   = hcnt == 7'd16 || hcnt == 7'd79 || vcnt == 9'd56 || vcnt == 9'd183;

assign pixel = in_window && on_edge;
assign q     = 1'b0;
assign audio = 8'd0;

endmodule
