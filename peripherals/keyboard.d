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
			import std.stdio;writefln("Scancode: 0x%02X", scancode);
			status|=1;
			intr_controller.IRQ(1);
		}
	}

	ubyte ArsdToScanCode(Key key)
	{
		import std.stdio;writefln("2. Keycode: %s", key);
		switch(key)
		{
			case Key.Backspace:
			{
				return 0x0e;
			}

			case Key.Space:
			{
				return 0x39;
			}

			case Key.G:
			{
				return 0x22;
			}

			default:
			{
				import std.conv : to;
				//assert(0, "Unhandled keycode" ~ to!string(key));
				import std.stdio;writefln("Unhandled keycode" ~ to!string(key));
				return 0xFF;
			}
		}
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
