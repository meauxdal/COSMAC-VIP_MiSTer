# COSMAC VIP for MiSTer

An RCA COSMAC VIP (1977) core for the MiSTer FPGA. The RTL is written from scratch and follows the VIP manual: a CDP1802 CPU, a CDP1861 video chip, the hex keypad, and the Q-line beeper. Expansion boards hang off the same expansion interface they use on a real VIP.

Tester build. Expect rough edges and report them.

## Status

- Working: CDP1802, CDP1861, 2K/4K RAM, hex keypad, beeper, VP-590 color board, CHIP-8 (`.ch8`) and binary (`.bin`) loading.
- Not yet: more than 4K RAM (VP-570), second keypad (VP-580), VP-595 sound, ASCII keyboard, cassette.

## Setup

1. Copy `releases/COSMAC-VIP_<date>.rbf` to your MiSTer (e.g. `_Computer/`).
2. Put the RCA firmware in `games/COSMAC-VIP/`:
   - `boot0.rom`: the 512-byte monitor ROM.
   - `boot1.rom`: the CHIP-8 interpreter, needed for `.ch8` files.

The firmware is RCA's and is not included. You need your own copies.

## Loading programs

- **Load CHIP-8**: loads a `.ch8` file at 0200, puts the interpreter at 0000, and starts the program.
- **Load Binary**: loads a `.bin` file at 0000 and runs it.
- **Reset to** (System page):
  - Auto: the monitor until you load a program, then the program.
  - Monitor: always the monitor.
  - Program in RAM: always the program.

## Controls

The PC keyboard maps to the VIP keypad in the same layout:

```
1 2 3 4      1 2 3 C
Q W E R  ->  4 5 6 D
A S D F      7 8 9 E
Z X C V      A 0 B F
```

Joystick 1 (OSD **Joystick**):

| Profile | Up/Down/Left/Right | Diagonals | Fire | Extra |
|---|---|---|---|---|
| 8-way | 2 / 8 / 4 / 6 | 1 3 7 9 | 5 | 0 |
| CHIP-8 | 5 / 8 / 7 / 9 | - | 6 | 4 |

The CHIP-8 profile follows the key layout most common in the [CHIP-8 database](https://github.com/chip-8/chip-8-database). Games with other layouts need the keyboard for now.

## Video

- **Aspect ratio**: Original is the shape of the picture on a real VIP (about 1.49:1 with borders, 1.74:1 without), not 4:3.
- **Scale**, **Borders**, **Vertical crop** (216p, 5x integer at 1080p) and **Crop offset**.
- **B/W palette**: White, Amber, Green or Inverted. It is unavailable while the VP-590 is on.
- **Color board** (System page): the VP-590. It also switches the CPU clock to the VP-590's 1.79 MHz, as on real hardware.

## License

GPL-2.0, see [LICENSE](LICENSE). The `sys/` framework is from [MiSTer-devel](https://github.com/MiSTer-devel/Template_MiSTer).
