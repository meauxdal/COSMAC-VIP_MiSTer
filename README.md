# COSMAC VIP for MiSTer

An RCA COSMAC VIP (1977) core for the MiSTer FPGA. The RTL is written from scratch and follows the VIP manual: a CDP1802 CPU, a CDP1861 video chip, the hex keypad, and the Q-line beeper. Expansion boards hang off the same expansion interface they use on a real VIP.

Tester build. Expect rough edges and report them.

## Status

- Working: CDP1802, CDP1861, 2K/4K/32K RAM, hex keypad, beeper, CHIP-8 (`.ch8`), CHIP-8X (`.c8x`) and binary (`.bin`) loading, a 32K ROM socket (J-VIP / VIP-S ROMs).
- Expansion boards: VP-570 RAM, VP-580 second keypad (VP-585 interface), VP-590 color board, VP-595 sound board, VP-601/611 ASCII keyboard.
- Not yet: VP-550/551 Super Sound, printer, cassette, serial.

## Setup

1. Copy `releases/COSMAC-VIP_<date>.rbf` to your MiSTer (e.g. `_Computer/`).
2. Put the RCA firmware in `games/COSMAC-VIP/`:
   - `boot0.rom`: the 512-byte monitor ROM.
   - `boot1.rom`: the CHIP-8 interpreter, needed for `.ch8` files.
   - `boot2.rom`: the CHIP-8X interpreter, needed for `.c8x` files.

The firmware is RCA's and is not included. You need your own copies.

## Loading programs

- **Load CHIP-8**: loads a `.ch8` file at 0200, puts the CHIP-8 interpreter at 0000, and starts the program.
- **Load CHIP-8X**: the same for a `.c8x` file, with the CHIP-8X interpreter.
- **Load Binary**: loads a `.bin` file at 0000 and runs it.
- **Load ROM (8000-FFFF)** (System page): replaces the monitor ROM with an image of up to 32K. A ROM larger than 512 bytes is treated as a J-VIP / VIP-S board, which needs the reset latch those boards add. Reloading the core restores `boot0.rom`.

## The OSD

- **Input**: Joystick profile, Keyboard (Hex keypads or ASCII).
- **Video**: aspect ratio, scale, borders, vertical crop, crop offset, B/W palette.
- **System**: RAM, Color board, Sound board, Load ROM, Reset key, Reset.

## Boards

- **RAM**: 4K, 2K, or 32K. 32K adds seven VP-570 4K boards at 1000-7FFF.
- **Color board**: the VP-590. It also switches the CPU clock to the VP-590's 1.79 MHz, as on real hardware.
- **Sound board**: the VP-595, a CDP1863 tone generator that replaces the on-board beeper.
- **Auto** (Color board and Sound board): the board is fitted while the last program loaded was a `.c8x`, since CHIP-8X expects the VP-590 and VP-595, and removed after a `.ch8` or `.bin`.

## Reset and boot keys

A real VIP enters its monitor only if key C is held when the RUN switch goes up. ROMs such as J-VIP pick other programs by other held keys.

- **F3** is the RUN switch: hold it for RESET, release it for RUN. Hold keypad keys through the release to pick the boot path, e.g. C for the monitor.
- **Reset key** (System page) is the key the core holds for a moment after an OSD reset, since the OSD swallows keys:
  - Auto: C until you load a program, then none.
  - None: never hold a key, so the program in RAM runs.
  - C (Monitor), 3 (Life), 4 (Black Jack), A, D, E, F: always hold that key. The named ones are the J-VIP boot paths. A, E and F copy CHIP-8 (with Pinball or Animal Race) to RAM, and D is the serial monitor, which this core does not support yet.

The reset at the end of a program load always starts the program, like a real VIP reset without C.

## Controls

The PC keyboard maps to the VIP keypad and the VP-580 second keypad in the same layout:

```
Keypad 1     Keypad 2     VIP
1 2 3 4      7 8 9 0      1 2 3 C
Q W E R      U I O P      4 5 6 D
A S D F      J K L ;      7 8 9 E
Z X C V      M , . /      A 0 B F
```

With **Keyboard** set to ASCII, the PC keyboard is a VP-601/611 ASCII keyboard on the I/O port instead, and both keypads are off. Caps Lock toggles upper case only (on by default). Backspace sends 08 and Delete sends 7F. Ctrl follows the VP-601 table. VP-700 BASIC (32K RAM, Load Binary) runs this way: Backspace erases, and Delete moves the cursor forward.

Joysticks 1 and 2 drive keypads 1 and 2 (OSD **Joystick**):

| Profile | Up/Down/Left/Right | Diagonals | Fire | Extra |
|---|---|---|---|---|
| 8-way | 2 / 8 / 4 / 6 | 1 3 7 9 | 5 | 0 |
| CHIP-8 | 5 / 8 / 7 / 9 | - | 6 | 4 |

The CHIP-8 profile follows the key layout most common in the [CHIP-8 database](https://github.com/chip-8/chip-8-database). Games with other layouts need the keyboard for now.

## Video

- **Aspect ratio**: Original is the shape of the picture on a real VIP (about 1.49:1 with borders, 1.74:1 without), not 4:3.
- **Scale**, **Borders**, **Vertical crop** (216p, 5x integer at 1080p) and **Crop offset** (up to 4 lines either way).
- **B/W palette**: White, Amber, Green or Inverted. It is unavailable while the VP-590 is on.

## Credits

The ROM socket and reset latch follow the J-VIP by Josh Bensadon and Walter Miraglia (2015), as documented in the [VIP-S Computer](https://github.com/cskordis/VIP-S-Computer) repository by Costas Skordis.

## License

GPL-2.0, see [LICENSE](LICENSE). The `sys/` framework is from [MiSTer-devel](https://github.com/MiSTer-devel/Template_MiSTer).
