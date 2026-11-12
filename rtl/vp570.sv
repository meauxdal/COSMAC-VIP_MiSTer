// RCA VP-570 memory expansion: 4K RAM boards on the expansion interface, each
// strapped to one 4K block. Seven of them at 1000-7FFF bring the VIP to 32K.
// A selected board raises INDIS, which stops the on-board RAM from answering
// at its mirrors.

module vp570
(
	input         clk,
	input         ce,
	input         enable,

	input         ioctl_download,
	input   [7:0] ioctl_index,
	input         ioctl_wr,
	input  [15:0] ioctl_addr,
	input   [7:0] ioctl_dout,

	// Expansion interface
	input   [7:0] ma,
	input         tpa,
	input         mrd_n,
	input         mwr_n,
	input   [7:0] bus,
	output  [7:0] bus_out,
	output        bus_oe,
	output        indis
);

// Loader, as in vip_core: 1 = .CH8 (RAM 0200), 2 = .BIN (RAM 0000)
wire        ld_ch8  = ioctl_index == 8'h01;
wire        ld_c8x  = ioctl_index == 8'h04;
wire        ld_bin  = ioctl_index == 8'h02;
wire [15:0] ld_addr = ld_ch8 ? ioctl_addr + 16'h200 :
                      ld_c8x ? ioctl_addr + 16'h300 : ioctl_addr;
wire        ld_wr   = ioctl_download && ioctl_wr && (ld_ch8 || ld_c8x || ld_bin) && !ld_addr[15];

reg  [7:0] a_hi;
always @(posedge clk) if (ce && tpa) a_hi <= ma;

wire [14:0] addr = {a_hi[6:0], ma};
wire        sel  = enable && !a_hi[7] && |a_hi[6:4];

// Block 0 stays unused: the on-board RAM holds 0000-0FFF
reg [7:0] ram[32768];
reg [7:0] ram_q;

always @(posedge clk) begin
	if (ld_wr)                     ram[ld_addr[14:0]] <= ioctl_dout;
	else if (ce && !mwr_n && sel)  ram[addr] <= bus;
	ram_q <= ram[addr];
end

assign bus_out = ram_q;
assign bus_oe  = sel && !mrd_n;
assign indis   = sel;

endmodule
