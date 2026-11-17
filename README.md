# COSMAC VIP for MiSTer

An RCA COSMAC VIP (1977) core for the MiSTer FPGA. The RTL is written from scratch and follows the VIP manual: a CDP1802 CPU, a CDP1861 video chip, the hex keypad, and the Q-line beeper. Expansion boards hang off the same expansion interface they use on a real VIP.

Tester build. Expect rough edges and report them.

## Status

- Working: CDP1802, CDP1861, 2K to 32K RAM, hex keypad, beeper, CHIP-8 (`.ch8`), CHIP-8X (`.c8x`) and binary (`.bin`) loading, a 32K ROM socket (J-VIP / VIP-S ROMs).
- Expansion boards: VP-570 RAM, VP-580 second keypad (VP-585 interface), VP-590 color board, VP-595 sound board, VIP Supersound card, VP-601/611 ASCII keyboard.
- Not yet: the PAiA drum card for the Supersound, the 4-channel VP-551, printer, cassette, serial.

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
- **System**: RAM, Color board, Sound board, Tempo (Supersound only), Elf panel, Load ROM, Boot key, Reset.

## Boards

- **RAM**: 4K (default), 8K, 16K, 32K, or 2K (stock). The VIP shipped with 2K on the board; RCA's VP-44 kit filled it to 4K. 8K, 16K and 32K add one, three or seven VP-570 4K boards from 1000 up. Changing RAM resets the machine, since the monitor sizes RAM at reset and CHIP-8 puts its display at the top of on-board RAM (0700 on 2K, 0F00 otherwise).
- **Color board**: the VP-590. It also switches the CPU clock to the VP-590's 1.79 MHz, as on real hardware.
- **Sound board**: the VP-595, a CDP1863 tone generator that replaces the on-board beeper, or the Supersound.
- **Supersound**: Joe Weisbecker's VIP Supersound card (July 1978), built from his schematic. RCA's later VP-550 Super Sound board appears to be the same design, but this hasn't been checked against a VP-550 manual. Two CDP1863 tone channels, each with a four-octave crossbar and 16 volume steps, written as memory at 8001-8030. A tempo oscillator interrupts the 1802; **Tempo** stands in for the card's knob (50-250 Hz). The manual says to disconnect the VIP speaker, so the beeper is silent while the card is fitted. Weisbecker's Pin-8 player and its tunes load as `.bin`. The PAiA drum card that Pin-8 drives from the output port isn't emulated.
- **Auto** (Color board and Sound board): the board is fitted while the last program loaded was a `.c8x`, since CHIP-8X expects the VP-590 and VP-595, and removed after a `.ch8` or `.bin`.
- **Elf panel** (off by default, not part of a real VIP): adds the COSMAC Elf's port 4 so Elf programs that use the front panel can run. OUT 4 shows a byte on two hex displays, INP 4 reads the eight data switches, and the IN button is on EF4. Set the switches Elf II style: each hex keypad key shifts its digit in (3 then A gives 3A). Enter is IN. An overlay shows the switches, the hex displays and a Q LED below the picture, or over its bottom edge when the borders are hidden.

## Reset and boot keys

A real VIP enters its monitor only if key C is held when the RUN switch goes up. ROMs such as J-VIP pick other programs by other held keys.

- **F3** is the RUN switch: hold it for RESET, release it for RUN. Hold keypad keys through the release to pick the boot path, e.g. C for the monitor.
- **Boot key** (System page) is the key the core holds for a moment after an OSD reset, since the OSD swallows keys:
  - Auto: C until you load a program, then none.
  - None: never hold a key, so the program in RAM runs.
  - C (Monitor): always hold C, the stock VIP monitor.
  - The J-VIP entries only do something with a J-VIP ROM loaded: 3 (Life), 4 (Black Jack), E (copy CHIP-8 to RAM), F (CHIP-8 with Pinball), A (CHIP-8 with Animal Race), and D (serial monitor, which needs a serial port the core does not have yet).

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
