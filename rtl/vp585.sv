// RCA VP-585 keypad interface (the VP-590 carries the same circuit): two
// VP-580 keypad jacks sharing a key latch on OUT 2. Keypad A answers on EF3
// like the VIP's own keypad, which stands in for it here; keypad B answers on
// EF4.

module vp585
(
	input         clk,
	input         ce,

	// Expansion interface
	input         tpb,
	input         mrd_n,
	input   [7:0] bus,
	input   [2:0] n,

	input  [15:0] keypad_b,
	output        ef4_n
);

reg [3:0] key_latch;

always @(posedge clk) begin
	if (ce && tpb && n == 3'd2 && !mrd_n) key_latch <= bus[3:0];
end

assign ef4_n = ~keypad_b[key_latch];

endmodule
