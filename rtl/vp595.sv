// RCA VP-595 Simple Sound Board: CDP1863 programmable frequency generator.
// OUT 3 latches the divisor N. TPA (CPU clock / 8) feeds the 1863's /4
// prescaler, then /(N + 1), then the /2 output stage:
// f = CPU clock / 64 / (N + 1). Q is the output enable; the dividers free-run
// while Q is low, so the phase at Q rising is arbitrary.
// TODO: confirm against the VP-595 manual/schematic: prescaler input (CLK1),
// free-run under Q low, latch state at power-on (taken as 00 here), and
// whether RESET reaches the 1863.

module vp595
(
	input               clk,
	input               ce,
	input               reset,

	// Expansion interface
	input               tpa,
	input               tpb,
	input               mrd_n,
	input         [7:0] bus,
	input         [2:0] n,

	input               q,
	output signed [7:0] audio         // +/-64, 0 while Q is low
);

reg [7:0] latch = 0;
reg [1:0] pre;
reg [7:0] div;
reg       tone;

always @(posedge clk) begin
	if (ce && tpb && n == 3'd3 && !mrd_n) latch <= bus;

	if (reset) begin
		pre  <= 0;
		div  <= 0;
		tone <= 0;
	end
	else if (ce && tpa) begin
		pre <= pre + 1'd1;
		if (pre == 2'd3) begin
			if (div == 0) begin
				div  <= latch;
				tone <= ~tone;
			end
			else div <= div - 1'd1;
		end
	end
end

assign audio = !q ? 8'sd0 : tone ? 8'sd64 : -8'sd64;

endmodule
