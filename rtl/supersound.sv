// VIP Supersound card (Joe Weisbecker, "VIP Supersound System", July 1978,
// figures 1 and 2). Two CDP1863 tone channels with 16-step volume, a crossbar
// octave selector and a tempo oscillator that interrupts the 1802.
//
// Decoding (fig. 2): IC6 latches MA7 at TPA, i.e. A15. A CD4555 then decodes
// writes (MWR) with A15 high, one half on A1-A0 and the other on A5-A4, both
// halves enabled together. Nothing else is decoded, so the registers mirror
// all over 8000-FFFF and a write to 8011 hits A frequency and A volume.
//   8001  A frequency (IC1 CDP1863 latch)
//   8002  B frequency (IC2)
//   8003  octave crossbar (IC4 CD22100): bit 4 = close/open, bit 2 = channel
//         B/A, bits 1-0 = octave 2-5. Bit 3 picks two unused outputs.
//   8010  A volume, low nibble (IC3 CD4508 half B)
//   8020  B volume, low nibble (IC3 half A)
//   8030  bit 0 gates the tempo oscillator (IC9 4013, cleared by RUN low)
// The A15 latch also drives MINH (pad 19) through a diode.
//
// Octave clocks into the crossbar: octave 5 = CLOCK, 4 = CLOCK / 2 (IC6),
// 3 = TPA or TPB, 2 = TPB. Each CDP1863 divides by 16 (N + 1), so octave 2
// A = 1760640 / 8 / 16 / 125 = 110.04 Hz, matching the note table (fig. 3).
// A crossbar output with no switch closed is pulled high: no clock, no tone.
//
// IC3 latches each volume, and the CDP1863 square wave drives that half's
// output disable, so the R-2R ladder swings between the volume and 0 V; a
// 0.22 uF cap removes the DC. Here that is +/- volume. Q drives the CDP1863
// output enables, so with Q low both channels sit at DC: silence. RUN low
// clears the dividers. The volume latches and crossbar have no reset.
//
// Tempo: a gated NAND RC oscillator (IC10, 50-250 Hz on the 50K pot). Its
// rising edge sets IC9, whose /Q pulls INTERRUPT low. IC9 is reset while SC1
// is high (the interrupt cycle, and DMA cycles too) or RUN is low. With the
// gate low the oscillator output idles low, and opening the gate drives it
// high at once, so the first interrupt comes straight away.

module supersound
(
	input               clk,             // clk_sys, 28.17024 MHz
	input               ce,              // 1802 clock, 1.76064 MHz
	input               run,
	input         [2:0] tempo,           // OSD: 100 Hz at 0, see TEMPO

	// Expansion interface
	input         [7:0] ma,
	input               tpa,
	input               tpb,
	input               mwr_n,
	input         [7:0] bus,
	input         [1:0] sc,
	input               q,
	output              int_n,
	output              minh,

	output signed [7:0] audio            // A + B, +/-120 at full volume
);

///////////////////////   DECODE   ///////////////////////////////

reg a15 = 0;
always @(posedge clk) if (ce && tpa) a15 <= ma[7];

wire wr       = ce && tpb && !mwr_n && a15;
wire set_afrq = wr && ma[1:0] == 2'd1;
wire set_bfrq = wr && ma[1:0] == 2'd2;
wire set_oct  = wr && ma[1:0] == 2'd3;
wire set_avol = wr && ma[5:4] == 2'd1;
wire set_bvol = wr && ma[5:4] == 2'd2;
wire set_sync = wr && ma[5:4] == 2'd3;

assign minh = a15;

///////////////////////   REGISTERS   ////////////////////////////

reg [7:0] a_n = 0, b_n = 0;
reg [3:0] a_vol = 0, b_vol = 0;
reg [3:0] a_sw = 0, b_sw = 0;          // crossbar: bit k = octave k + 2
reg       sync_gate = 0;

always @(posedge clk) begin
	if (set_afrq) a_n <= bus;
	if (set_bfrq) b_n <= bus;
	if (set_avol) a_vol <= bus[3:0];
	if (set_bvol) b_vol <= bus[3:0];
	if (set_oct && !bus[3]) begin
		if (bus[2]) b_sw[bus[1:0]] <= bus[4];
		else        a_sw[bus[1:0]] <= bus[4];
	end

	if (!run)          sync_gate <= 0;
	else if (set_sync) sync_gate <= bus[0];
end

///////////////////////   TONE   /////////////////////////////////

reg  ck_half = 0;
always @(posedge clk) if (ce) ck_half <= ~ck_half;

// Clock edges per octave input, 2 to 5
wire [3:0] oct_tick = {ce, ce && ck_half, ce && (tpa || tpb), ce && tpb};

wire a_tick = |(a_sw & oct_tick);
wire b_tick = |(b_sw & oct_tick);

wire a_out, b_out;

ss_cdp1863 ic1 (.clk(clk), .clr(!run), .tick(a_tick), .n(a_n), .out(a_out));
ss_cdp1863 ic2 (.clk(clk), .clr(!run), .tick(b_tick), .n(b_n), .out(b_out));

wire signed [7:0] a_amp = {2'b00, a_vol, 2'b00};
wire signed [7:0] b_amp = {2'b00, b_vol, 2'b00};

assign audio = !q ? 8'sd0 :
               (a_out ? a_amp : -a_amp) + (b_out ? b_amp : -b_amp);

///////////////////////   TEMPO   ////////////////////////////////

localparam [24:0] OSC_MOD = 25'd28170240;   // clk_sys, one second

reg [7:0] rate;
always @(*) begin
	case (tempo)
		3'd0: rate = 8'd100;               // default, as Emma 02
		3'd1: rate = 8'd125;
		3'd2: rate = 8'd150;
		3'd3: rate = 8'd175;
		3'd4: rate = 8'd200;
		3'd5: rate = 8'd250;
		3'd6: rate = 8'd50;
		default: rate = 8'd75;
	endcase
end

reg [24:0] osc_acc = 0;
reg        int_ff = 0;
wire [25:0] osc_next = osc_acc + rate;
wire        osc_edge = sync_gate && osc_next >= {1'b0, OSC_MOD};

always @(posedge clk) begin
	// Gate closed: park just short of the edge, so opening it fires at once
	if (!sync_gate)    osc_acc <= OSC_MOD - rate;
	else if (osc_edge) osc_acc <= osc_next[24:0] - OSC_MOD;
	else               osc_acc <= osc_next[24:0];

	if (!run || sc[1]) int_ff <= 0;
	else if (osc_edge) int_ff <= 1;
end

assign int_n = !int_ff;

endmodule

// CDP1863 programmable frequency generator: the clock input is prescaled by
// 8, divided by N + 1 and toggles the output, so f = fclk / (16 (N + 1)).
// CLEAR resets the counters and the output; the N latch keeps its value.
module ss_cdp1863
(
	input       clk,
	input       clr,
	input       tick,
	input [7:0] n,
	output reg  out = 0
);

reg [2:0] pre = 0;
reg [7:0] div = 0;

always @(posedge clk) begin
	if (clr) begin
		pre <= 0;
		div <= 0;
		out <= 0;
	end
	else if (tick) begin
		pre <= pre + 1'd1;
		if (&pre) begin
			if (div == 0) begin
				div <= n;
				out <= ~out;
			end
			else div <= div - 1'd1;
		end
	end
end

endmodule
