# 8086eD - x86 Emulator, written in D
This is self-made x86 interpreter, written in D language. It's private currently, until I polish it more. Expect it very soon

 ## Supported features:
  * All NEC v20 instructions(unless I missed an instruction(s))
  * 1MB RAM (640KB usable)
  * Text modes 7 and 3(now with colours)
  * VRI format for loading ROM images(the file format itself is extremely basic and very convenient to use)
  * Periodic timer(IRQ 8)
  * Keyboard
  * SFML window(720x400)
  * (A rather advanced) Debugger
  * Uses the Super PC/Turbo XT BIOS 3.1 with very small changes(added HLT instruction in keyboard loop for energy saving)
  * Fully working IVT
  
  The emulator is planned to support at least the 486 instruction set
  
  ## Instruction set implementation steps:
  
  - [x] Intel 8086 instructions set
  - [x] NEC v20 instruction set
  - [ ] Intel 286 Protected Mode
  - [ ] 32-bit Intel 386 instruction set(w/o Protected mode and Paging)
  - [ ] 32-bit Protected Mode with Paging
  - [ ] Intel 486 instructions set
  - [ ] Intel 486 instructions set with CPUID and CMPXCHG8B
  - [ ] Intel Pentium instruction set possibly?
  
  ## Incomplete features:
  * Fully implemented PIC
  * Fully implemented PIT
  * DMA and etc.
  * Graphics modes
  * Harddrive and booting from it
  * Full decoding of the instructions in the debugger
  
  I made this emulator, in order to learn more about x86 assembly, IBM-based computers. Also I have a computer with Intel 386SX processor, but it doesn't want to boot. So, the next thing to do is to mod its BIOS later and i pratice modifying BIOSes and understanding istructions with this
 
