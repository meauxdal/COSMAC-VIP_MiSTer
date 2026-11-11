// RCA VP-595 Simple Sound Board: CDP1863 programmable frequency generator.
// Per the VP-580/585/590/595 manual (MPM-233), section VI: a free-running RC
// oscillator of about 440 kHz (U2 inverters, factory trimmed) clocks the 1863,
// whose prescaler and /2 output stage give
//   f = 27535 / (N + 1) Hz      (N = OUT 3 latch, FF -> 107.56 Hz)
// independent of the CPU clock. U3/U4 decode N = 00 and inject 80 instead, so
// the power-on/reset value 00 still plays about 213 Hz and the monitor's key
// beep is heard. Q gates the output; the divider free-runs while Q is low.
//
// Here the oscillator is modelled at the tone-toggle rate 2 * 27535 Hz with a
// fractional accumulator on clk_sys (28.17024 MHz): 55070 / 28170240 =
// 5507 / 2817024.

module vp595
(
	input               clk,             // clk_sys, 28.17024 MHz
	input               ce,
	input               reset,

	// Expansion interface
	input               tpb,
	input               mrd_n,
	input         [7:0] bus,
	input         [2:0] n,

	input               q,
	output signed [7:0] audio         // +/-64, 0 while Q is low
);

localparam [21:0] OSC_MOD = 22'd2817024;
localparam [21:0] OSC_INC = 22'd5507;

reg  [7:0] latch = 0;
reg [21:0] osc_acc = 0;
reg  [7:0] div = 0;
reg        tone = 0;

wire [22:0] osc_next = osc_acc + OSC_INC;
wire  [7:0] n_eff    = latch == 8'h00 ? 8'h80 : latch;

always @(posedge clk) begin
	// The VIP output port latch clears on reset (manual: "the output port
	// latches 00 when the VIP is reset").
	if (reset) latch <= 0;
	else if (ce && tpb && n == 3'd3 && !mrd_n) latch <= bus;

	// RC oscillator and /(N + 1) divider: free-running, not reset.
	if (osc_next >= {1'b0, OSC_MOD}) begin
		osc_acc <= osc_acc - (OSC_MOD - OSC_INC);
		if (div == 0) begin
			div  <= n_eff;
			tone <= ~tone;
		end
		else div <= div - 1'd1;
	end
	else osc_acc <= osc_next[21:0];
end

assign audio = !q ? 8'sd0 : tone ? 8'sd64 : -8'sd64;

endmodule
