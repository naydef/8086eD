# 8086eD
This is self-made x86 interpreter, written in D language. It's private currently, until I polish it more

Supported features:
  * ALL NEC v20 instructions(unless I missed an instruction(s))
  * 1MB RAM (640KB usable)
  * Text modes 7 and 3(now with colours)
  * VRI format for loading ROM images(the file format itself is extremely basic and very convenient to use)
  * Periodic timer(IRQ 8)
  * Keyboard
  * SFML window(720x400)
  * (A rather advanced) Debugger
  * Uses the Super PC/Turbo XT BIOS 3.1 with very small changes(added HLT instruction in keyboard loop for energy saving)
  * and fully working IVT, set up by the BIOS
