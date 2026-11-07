// RCA CDP1802 COSMAC microprocessor.
// Clock-level: 8 clocks per machine cycle (9 for the initialization cycle after reset).
// Pin polarities follow the data sheet; pins named _n are active low.
//
// Clock (ph) within a machine cycle:
//   0-1  MA = high address byte, TPA at 1 (memory latches it on the trailing edge)
//   2-7  MA = low address byte
//   2    Q changes (SEQ/REQ)
//   5-6  MWR low in write cycles
//   6    TPB; read data latched
//   7    INTERRUPT/DMA sampled, registers updated, next state chosen
// EF1-4 are sampled at the start of every S1.

module cdp1802
(
	input            clk,
	input            ce,          // one pulse per 1802 clock

	input            clear_n,
	input            wait_n,

	input            int_n,
	input            dma_in_n,
	input            dma_out_n,
	input      [4:1] ef_n,

	input      [7:0] bus_in,
	output     [7:0] bus_out,
	output           bus_oe,      // CPU drives the data bus

	output     [7:0] ma,
	output           tpa,
	output           tpb,
	output           mrd_n,
	output           mwr_n,
	output     [1:0] sc,
	output     [2:0] n,
	output reg       q
);

localparam S0 = 2'd0, S1 = 2'd1, S2 = 2'd2, S3 = 2'd3;

reg [15:0] r[16];
reg  [3:0] i, nn, x, p;
reg  [7:0] d, t, b, dat;
reg        df, ie;
reg  [1:0] state;
reg        exec2;                 // second execute cycle of a long branch/skip
reg        dma_in_cyc;            // current S2 is DMA-in
reg  [3:0] ph;
reg        rst  = 1;              // reset held
reg        init = 0;              // initialization cycle
reg  [4:1] efs;

wire load_mode = !clear_n && !wait_n;
wire idle      = state == S1 && i == 4'h0 && nn == 4'h0;

///////////////////////   CYCLE DECODE   /////////////////////////

reg [15:0] a;
reg        rd, wr, drv;
reg  [7:0] wdat;
reg  [2:0] nout;

always @* begin
	a = r[p]; rd = 0; wr = 0; drv = 0; wdat = d; nout = 0;
	case (state)
		S0: rd = 1;
		S2: begin a = r[0]; rd = !dma_in_cyc; wr = dma_in_cyc; end
		S3: ;
		S1: case (i)
			4'h0: begin a = r[nn]; rd = nn != 0; end           // IDL, LDN
			4'h3, 4'hC: rd = 1;                                // branches: M(R(P))
			4'h4: begin a = r[nn]; rd = 1; end                 // LDA
			4'h5: begin a = r[nn]; wr = 1; drv = 1; end        // STR
			4'h6: begin                                        // OUT / INP (60 = IRX, 68 = INP 0)
				a = r[x]; nout = nn[2:0];
				rd = !nn[3]; wr = nn[3];
			end
			4'h7: case (nn)
				4'h0, 4'h1, 4'h2, 4'h4, 4'h5, 4'h7: begin a = r[x]; rd = 1; end
				4'h3: begin a = r[x]; wr = 1; drv = 1; end                     // STXD
				4'h8: begin a = r[x]; wr = 1; drv = 1; wdat = t; end           // SAV
				4'h9: begin a = r[2]; wr = 1; drv = 1; wdat = {x, p}; end      // MARK
				4'hC, 4'hD, 4'hF: rd = 1;                                      // immediates
				default: ;
			endcase
			4'hF: case (nn)
				4'h6, 4'hE: ;                                                  // SHR, SHL
				4'h8, 4'h9, 4'hA, 4'hB, 4'hC, 4'hD, 4'hF: rd = 1;              // immediates
				default: begin a = r[x]; rd = 1; end
			endcase
			default: a = r[nn];
		endcase
	endcase
end

wire running = !rst && !init;

assign ma      = (ph <= 1) ? a[15:8] : a[7:0];
assign tpa     = running && !load_mode && ph == 1;
assign tpb     = running && ph == 6;
assign mrd_n   = !(running && rd);
assign mwr_n   = !(running && wr && (ph == 5 || ph == 6));
assign sc      = state;
assign n       = running ? nout : 3'd0;
assign bus_out = rst ? 8'h00 : wdat;
assign bus_oe  = rst || (running && drv);

///////////////////////   ALU   //////////////////////////////////

// SD/SM subtract by adding the complement; DF = 1 means no borrow
wire       bin    = (i == 4'h7) ? df : 1'b1;                   // not-borrow for SD/SM/SDB/SMB
wire       cin     = i == 4'h7 && df;                           // ADC/ADCI
wire [8:0] add_res = {1'b0, dat} + {1'b0, d} + {8'd0, cin};
wire [8:0] sd_res  = {1'b0, dat} + {1'b0, ~d} + {8'd0, bin};
wire [8:0] sm_res  = {1'b0, d} + {1'b0, ~dat} + {8'd0, bin};

///////////////////////   BRANCH CONDITIONS   ////////////////////

reg  c3;
always @* case (nn[2:0])
	3'd0: c3 = 1;
	3'd1: c3 = q;
	3'd2: c3 = d == 0;
	3'd3: c3 = df;
	default: c3 = efs[nn[1:0] + 3'd1];
endcase
wire short_taken = nn[3] ? !c3 : c3;

reg  cl;
always @* case (nn[1:0])
	2'd0: cl = nn[2] ? ie : 1'b1;
	2'd1: cl = q;
	2'd2: cl = d == 0;
	2'd3: cl = df;
endcase
wire long_taken = nn[3] ? !cl : cl;                                       // C0-C3, C8-CB
wire long_skip  = nn[3] ? cl : (nn[1:0] != 0 && !cl);                     // C4-C7, CC-CF

///////////////////////   SEQUENCER   ////////////////////////////

wire dma_req = !dma_in_n || (!dma_out_n && !load_mode);
wire int_req = !int_n && ie && !load_mode;

task automatic next_after_exec;
	if (dma_req) begin state <= S2; dma_in_cyc <= !dma_in_n; end
	else if (int_req) state <= S3;
	else state <= load_mode ? S1 : S0;
endtask

always @(posedge clk) begin
	if (ce && (wait_n || !clear_n)) begin
		if (!clear_n && wait_n) begin
			// Reset: I, N, Q cleared, IE set, TPA/TPB suppressed, held in S1
			rst <= 1; init <= 0; ph <= 0;
			i <= 0; nn <= 0; q <= 0; ie <= 1;
			state <= S1; exec2 <= 0;
		end
		else if (rst) begin
			rst <= 0; init <= 1; ph <= 0;
		end
		else if (init) begin
			// Initialization cycle, 9 clocks: X, P, R0 cleared, no INTERRUPT
			if (ph == 8) begin
				ph <= 0; init <= 0;
				x <= 0; p <= 0; r[0] <= 0;
				if (dma_req) begin state <= S2; dma_in_cyc <= !dma_in_n; end
				else state <= load_mode ? S1 : S0;
			end
			else ph <= ph + 1'd1;
		end
		else begin
			ph <= (ph == 7) ? 4'd0 : ph + 1'd1;

			if (ph == 0 && state == S1) efs <= ~ef_n;
			if (ph == 6) dat <= bus_in;
			if (ph == 2 && state == S1 && i == 4'h7 && nn[3:1] == 3'b101) q <= nn[0];

			if (ph == 7) begin
				case (state)
					S0: begin
						i <= dat[7:4]; nn <= dat[3:0];
						r[p] <= r[p] + 1'd1;
						state <= S1; exec2 <= 0;
					end

					S2: begin
						r[0] <= r[0] + 1'd1;
						next_after_exec();
					end

					S3: begin
						t <= {x, p}; x <= 4'd2; p <= 4'd1; ie <= 0;
						if (dma_req) begin state <= S2; dma_in_cyc <= !dma_in_n; end
						else state <= S0;
					end

					S1: begin
						if (i == 4'hC && !exec2) begin
							exec2 <= 1;
							if (!nn[2]) begin b <= dat; r[p] <= r[p] + 1'd1; end
							else if (long_skip) r[p] <= r[p] + 1'd1;
						end
						else begin
							exec2 <= 0;
							case (i)
								4'h0: if (nn != 0) d <= dat;
								4'h1: r[nn] <= r[nn] + 1'd1;
								4'h2: r[nn] <= r[nn] - 1'd1;
								4'h3: if (short_taken) r[p][7:0] <= dat; else r[p] <= r[p] + 1'd1;
								4'h4: begin d <= dat; r[nn] <= r[nn] + 1'd1; end
								4'h5: ;
								4'h6: if (nn[3]) d <= dat; else r[x] <= r[x] + 1'd1;
								4'h7: case (nn)
									4'h0, 4'h1: begin {x, p} <= dat; r[x] <= r[x] + 1'd1; ie <= !nn[0]; end
									4'h2: begin d <= dat; r[x] <= r[x] + 1'd1; end
									4'h3: r[x] <= r[x] - 1'd1;
									4'h4, 4'hC: {df, d} <= add_res;
									4'h5, 4'hD: {df, d} <= sd_res;
									4'h6: {d, df} <= {df, d};
									4'h7, 4'hF: {df, d} <= sm_res;
									4'h8: ;
									4'h9: begin t <= {x, p}; x <= p; r[2] <= r[2] - 1'd1; end
									4'hA, 4'hB: ;
									4'hE: {df, d} <= {d, df};
								endcase
								4'h8: d <= r[nn][7:0];
								4'h9: d <= r[nn][15:8];
								4'hA: r[nn][7:0]  <= d;
								4'hB: r[nn][15:8] <= d;
								4'hC: if (!nn[2]) begin
									if (long_taken) r[p] <= {b, dat}; else r[p] <= r[p] + 1'd1;
								end
								else if (long_skip) r[p] <= r[p] + 1'd1;
								4'hD: p <= nn;
								4'hE: x <= nn;
								4'hF: case (nn)
									4'h0, 4'h8: d <= dat;
									4'h1, 4'h9: d <= d | dat;
									4'h2, 4'hA: d <= d & dat;
									4'h3, 4'hB: d <= d ^ dat;
									4'h4, 4'hC: {df, d} <= add_res;
									4'h5, 4'hD: {df, d} <= sd_res;
									4'h6: {d, df} <= {1'b0, d};
									4'h7, 4'hF: {df, d} <= sm_res;
									4'hE: {df, d} <= {d, 1'b0};
								endcase
							endcase

							// Immediate operands advance R(P)
							if (((i == 4'hF && nn[3]) || (i == 4'h7 && nn[3:2] == 2'b11)) && nn != 4'hE)
								r[p] <= r[p] + 1'd1;

							if (idle && !load_mode) begin
								if (dma_req) begin state <= S2; dma_in_cyc <= !dma_in_n; end
								else if (int_req) state <= S3;
							end
							else next_after_exec();
						end
					end
				endcase
			end
		end
	end
end

endmodule
