module XT_Keyboard;

import ibm_pc_com;
import std.stdio;
import simplelogger;
import x86_memory;
import IBM_PIC;
import std.format;
import std.concurrency;
import core.thread;
import core.sync.mutex;
import sfml_interface;
import peripherals.video;
import std.container.dlist;
import arsd.simpledisplay;

struct KeyCode
{
	Key code;
	bool pressed;
}

class XT_Keyboard
{
	this(IBM_PC_COMPATIBLE param, PIC param2)
	{
		pc=param;
		memory=pc.GetCPU().ExposeRam();
		pc.AddINOUTHandler(0x0060, &PortIO);
		pc.AddINOUTHandler(0x0064, &PortIO);
		pc.AddINOUTHandler(0x0061, &PortIO);
		intr_controller=param2;
		spawn(&Render_Keyboard_Thread, null, cast(shared(ubyte*))memory.GetRamPointer());
		if(!keyboardQueueMtx) keyboardQueueMtx = new Object();
	}


	public void PortIO(ushort port, ref ushort value, bool infunc)
	{
		switch(port)
		{
		case 0x60:
			{
				if(infunc)
				{
					value=scancode;
					x86log.logf("in from 0x60: 0x%04X 0x%04X", scancode, value);
				}
				break;
			}
		case 0x61:
			{
				if(infunc)
				{
					static ubyte counter;
					value=port61reg;
					if(counter%2)
					{
						value|=0b10000;
					}
					else
					{
						value&=0b11101111;
					}
					counter++;
				}
				else
				{
					port61reg=value&0xFF;
					if(port61reg&3)
					{
						//flash();
						//To-do:
					}
				}
				break;
			}
		case 0x64:
			{
				if(infunc)
				{
					value=status;
				}
				break;
			}
		default:
			{
				assert(0, "Keyboard controller port not handled!");
			}
		}
	}

	void AcknowledgeInterrupts()
	{
		KeyCode key;
		synchronized(XT_Keyboard.keyboardQueueMtx)
		{
			if(XT_Keyboard.kbEventQueue.empty()) return;
			key = XT_Keyboard.kbEventQueue.back();
			XT_Keyboard.kbEventQueue.removeBack();
		}
		auto scancode2=ArsdToScanCode(key.code);
		if(scancode2!=0)
		{
			scancode=scancode2;
			if(!key.pressed) scancode|=0x80;
			import std.stdio;writefln("Scancode: 0x%02X KeyCode: %s", scancode, key.code);
			status|=1;
			intr_controller.IRQ(1);
		}
	}

	ubyte ArsdToScanCode(Key key)
	{
		//https://aeb.win.tue.nl/linux/kbd/scancodes-1.html
		immutable ubyte[Key] scanToArsdMap = [
			Key.Escape: 0x01,
			Key.N1: 0x02,
			Key.N2: 0x03,
			Key.N3: 0x04,
			Key.N4: 0x05,
			Key.N5: 0x06,
			Key.N6: 0x07,
			Key.N7: 0x08,
			Key.N8: 0x09,
			Key.N9: 0x0A,
			Key.N0: 0x0B,
			Key.Minus: 0x0C,
			Key.Equals: 0x0D,
			Key.Backspace: 0x0E,
			Key.Tab: 0x0F,
			Key.Q: 0x10,
			Key.W: 0x11,
			Key.E: 0x12,
			Key.R: 0x13,
			Key.T: 0x14,
			Key.Y: 0x15,
			Key.U: 0x16,
			Key.I: 0x17,
			Key.O: 0x18,
			Key.P: 0x19,
			Key.LeftBracket: 0x1A,
			Key.RightBracket: 0x1B,
			Key.Enter: 0x1C,
			Key.Ctrl:0x1D,
			Key.A: 0x1E,
			Key.S: 0x1F,
			Key.D: 0x20,
			Key.F: 0x21,
			Key.G: 0x22,
			Key.H: 0x23,
			Key.J: 0x24,
			Key.K: 0x25,
			Key.L: 0x26,
			Key.Semicolon: 0x27,
			Key.Apostrophe: 0x28,
			Key.Grave: 0x29,
			Key.Shift: 0x2A,
			Key.Backslash: 0x2B,
			Key.Z: 0x2C,
			Key.X: 0x2D,
			Key.C: 0x2E,
			Key.V: 0x2F,
			Key.B: 0x30,
			Key.N: 0x31,
			Key.M: 0x32,
			Key.Comma: 0x33,
			Key.Period: 0x34,
			Key.Slash: 0x35,
			Key.Shift_r: 0x36,
			Key.Multiply: 0x37,
			Key.Alt: 0x38,
			Key.Space: 0x39,
			Key.CapsLock: 0x3A,
			Key.F1: 0x3B,
			Key.F2: 0x3C,
			Key.F3: 0x3D,
			Key.F4: 0x3E,
			Key.F5: 0x3F,
			Key.F6: 0x40,
			Key.F7: 0x41,
			Key.F8: 0x42,
			Key.F9: 0x43,
			Key.F10: 0x44,
			Key.NumLock: 0x45,
			Key.ScrollLock: 0x46,
			Key.Left: 0x47,
			Key.Up: 0x48,
			Key.PageUp: 0x49,
			//Key.? :0x4A,
			Key.Left : 0x4B,
			//Key.?: 0x4C,
			Key.Right: 0x4D,
			//Key.?: 0x4E,
			//Key.?: 0x4F,
			Key.Down: 0x50,
			Key.PageDown: 0x51,
			//Key.?: 0x52,
			Key.Delete: 0x53,
			//Key.?: 0x54,
			//Key.?: 0x55,
			//Key.?: 0x56,
			Key.F11: 0x57,
			Key.F12: 0x58,
		];

		if(auto val = key in scanToArsdMap)
		{
			return *val;
		}
		return 0xFF;
	}

	private IBM_PC_COMPATIBLE pc;
	private MemoryX86 memory;
	private PIC intr_controller;
	private bool shiftFlip;

	private ubyte port61reg;
	private ubyte scancode;
	private ubyte status;
	__gshared Object keyboardQueueMtx;
	__gshared DList!KeyCode kbEventQueue;
}
