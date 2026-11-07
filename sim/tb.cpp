// vip_core testbench: load ROM/program through ioctl, run frames, dump the last frame as PGM.
// Usage: tb <monitor.rom> [-i interp.bin] [-c prog.ch8] [-b prog.bin] [-k hexkeys] [-r release_frame] [-s frame:keys] [-f frames] [-2k] [-o out.pgm]

#include "Vvip_core.h"
#include "Vvip_core___024root.h"
#include <verilated.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <string>

static Vvip_core *top;
static uint64_t ticks;
static unsigned cediv = 2;           // env CEDIV: clocks per ce (hardware uses 16)

static void tick()
{
	top->clk = 0; top->eval();
	top->clk = 1; top->eval();
	ticks++;
	top->ce = (ticks % cediv) == 0;
}

static std::vector<uint8_t> load(const char *path)
{
	std::vector<uint8_t> v;
	FILE *f = fopen(path, "rb");
	if (!f) { fprintf(stderr, "cannot open %s\n", path); exit(1); }
	int c;
	while ((c = fgetc(f)) != EOF) v.push_back((uint8_t)c);
	fclose(f);
	return v;
}

static void download(uint8_t index, const std::vector<uint8_t> &data)
{
	top->ioctl_index = index;
	top->ioctl_download = 1;
	for (size_t a = 0; a < data.size(); a++) {
		top->ioctl_addr = a;
		top->ioctl_dout = data[a];
		top->ioctl_wr = 1; tick();
		top->ioctl_wr = 0; tick();
	}
	top->ioctl_download = 0;
	for (int i = 0; i < 1100; i++) tick();     // interpreter copy after .CH8
}

int main(int argc, char **argv)
{
	Verilated::commandArgs(argc, argv);
	top = new Vvip_core;
	if (getenv("CEDIV")) cediv = atoi(getenv("CEDIV"));

	const char *rom = nullptr, *interp = nullptr, *ch8 = nullptr, *bin = nullptr, *out = "frame.pgm";
	unsigned keys = 0;
	int frames = 30, release = -1, seq_start = 0;
	const char *seq = "";
	for (int i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "-i")) interp = argv[++i];
		else if (!strcmp(argv[i], "-c")) ch8 = argv[++i];
		else if (!strcmp(argv[i], "-b")) bin = argv[++i];
		else if (!strcmp(argv[i], "-k")) { for (char *k = argv[++i]; *k; k++) keys |= 1u << strtol((char[]){*k, 0}, nullptr, 16); }
		else if (!strcmp(argv[i], "-f")) frames = atoi(argv[++i]);
		else if (!strcmp(argv[i], "-r")) release = atoi(argv[++i]);
		else if (!strcmp(argv[i], "-s")) { seq_start = atoi(argv[++i]); seq = strchr(argv[i], ':') + 1; }
		else if (!strcmp(argv[i], "-2k")) top->ram_2k = 1;
		else if (!strcmp(argv[i], "-o")) out = argv[++i];
		else rom = argv[i];
	}
	if (!rom) { fprintf(stderr, "no monitor ROM\n"); return 1; }

	top->reset = 1;
	top->exp_bus_in = 0xFF;
	top->exp_int_n = top->exp_dma_in_n = top->exp_dma_out_n = 1;
	top->exp_ef_n = 0xF;
	for (int i = 0; i < 64; i++) tick();

	download(0x00, load(rom));
	if (interp) download(0x40, load(interp));
	if (bin) download(0x02, load(bin));
	if (ch8) download(0x01, load(ch8));

	top->keypad = keys;
	for (int i = 0; i < 64; i++) tick();
	top->reset = 0;

	const int W = 96, H = 224;
	std::vector<uint8_t> fb(W * H, 0);
	int x = 0, y = 0, frame = 0, lit = 0;
	bool hb_old = true, vs_old = false, ce_old = false;

	while (frame < frames) {
		tick();
		if (!top->ce || ce_old) { ce_old = top->ce; continue; }
		ce_old = top->ce;
		{
			auto *r = top->rootp;
			static int dline = -1, dfirst, dcount, dmark;
			int line = r->vip_core__DOT__pixie__DOT__line, cyc = r->vip_core__DOT__pixie__DOT__cyc;
			if (getenv("DMALOG") && frame == frames - 2) {
				if (r->vip_core__DOT__tpb && r->vip_core__DOT__sc == 2) {
					if (line != dline) { if (dline >= 0) printf("line %3d first cyc %2d count %d R0 %04X\n", dline, dfirst, dcount, dmark); dline = line; dfirst = cyc; dcount = 0; dmark = r->vip_core__DOT__cpu__DOT__r[0]; }
					dcount++;
				}
				if (r->vip_core__DOT__tpa && r->vip_core__DOT__cpu__DOT__state == 3) printf("S3 at line %d cyc %d\n", line, cyc);
			}
		}
		if (top->vsync && !vs_old) {
			frame++;
			if (frame == release) top->keypad = 0;
			// key sequence: each key held 6 frames, then 6 frames up
			int k = (frame - seq_start) / 12;
			if (frame >= seq_start && k < (int)strlen(seq))
				top->keypad = (frame - seq_start) % 12 < 6 ? 1u << strtol((char[]){seq[k], 0}, nullptr, 16) : 0;
			if (frame == frames - 1) lit = 0;
			y = 0;
		}
		vs_old = top->vsync;
		if (top->hblank && !hb_old && !top->vblank) y++;
		if (!top->hblank && hb_old) x = 0;
		hb_old = top->hblank;
		if (!top->hblank && !top->vblank) {
			if (x < W && y < H) {
				fb[y * W + x] = top->pixel ? 255 : 0;
				if (frame == frames - 1 && top->pixel) lit++;
			}
			x++;
		}
	}

	FILE *f = fopen(out, "wb");
	fprintf(f, "P5\n%d %d\n255\n", W, H);
	fwrite(fb.data(), 1, fb.size(), f);
	fclose(f);

	auto *r = top->rootp;
	printf("frames %d, lit pixels in last frame %d, Q %d\n", frames, lit, top->q);
	printf("P %X X %X D %02X DF %d IE %d\n", r->vip_core__DOT__cpu__DOT__p, r->vip_core__DOT__cpu__DOT__x,
	       r->vip_core__DOT__cpu__DOT__d, r->vip_core__DOT__cpu__DOT__df, r->vip_core__DOT__cpu__DOT__ie);
	for (int i = 0; i < 16; i++)
		printf("R%X %04X%s", i, r->vip_core__DOT__cpu__DOT__r[i], (i & 7) == 7 ? "\n" : "  ");

	if (getenv("PAGEDUMP")) {
		int pg = r->vip_core__DOT__cpu__DOT__r[0xB] & 0xF00;
		for (int row = 0; row < 32; row++) {
			for (int c = 0; c < 8; c++) {
				uint8_t v = r->vip_core__DOT__ram[pg + row * 8 + c];
				for (int bit = 7; bit >= 0; bit--) putchar(v >> bit & 1 ? '#' : '.');
			}
			putchar('\n');
		}
	}
	delete top;
	return 0;
}
