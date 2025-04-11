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
		spawn(&Render_Keyboard_Thread, &keypress, cast(shared(ubyte*))memory.GetRamPointer());
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
		if(keypress!=-1)
		{
			auto scancode2=NCursesToScanCode(keypress);
			if(scancode2!=0)
			{
				scancode=scancode2;
				status|=1;
				intr_controller.IRQ(1);
				keypress=-1;
			}
		}
	}

	ubyte NCursesToScanCode(int ch)
	{
		/+
		switch(ch)
		{
		case Keyboard.Key.Escape:
			{
				return 0x01;
			}
		case Keyboard.Key.Num1:
			{
				return 0x02;
			}
		case Keyboard.Key.Num2:
			{
				return 0x03;
			}
		case Keyboard.Key.Num3:
			{
				return 0x04;
			}
		case Keyboard.Key.Num4:
			{
				return 0x05;
			}
		case Keyboard.Key.Num5:
			{
				return 0x06;
			}
		case Keyboard.Key.Num6:
			{
				return 0x07;
			}
		case Keyboard.Key.Num7:
			{
				return 0x08;
			}
		case Keyboard.Key.Num8:
			{
				return 0x09;
			}
		case Keyboard.Key.Num9:
			{
				return 0x0A;
			}
		case Keyboard.Key.Num0:
			{
				return 0x0B;
			}
			/*
			case X: // - _
			{
				return 0x0C;
			}
			case X: // =+
			{
				return 0x0D;
			}
			*/
		case Keyboard.Key.BackSpace:
			{
				return 0x0E;
			}
		case Keyboard.Key.Tab:
			{
				return 0x0F;
			}
		case Keyboard.Key.Q:
			{
				return 0x10;
			}
		case Keyboard.Key.W:
			{
				return 0x11;
			}
		case Keyboard.Key.E:
			{
				return 0x12;
			}
		case Keyboard.Key.R:
			{
				return 0x13;
			}
		case Keyboard.Key.T:
			{
				return 0x14;
			}
		case Keyboard.Key.Y:
			{
				return 0x15;
			}
		case Keyboard.Key.U:
			{
				return 0x16;
			}
		case Keyboard.Key.I:
			{
				return 0x17;
			}
		case Keyboard.Key.O:
			{
				return 0x18;
			}
		case Keyboard.Key.P:
			{
				return 0x19;
			}
		case Keyboard.Key.LBracket:
			{
				return 0x1A;
			}
		case Keyboard.Key.RBracket:
			{
				return 0x1B;
			}
		case Keyboard.Key.Return:
			{
				return 0x1C;
			}
		case Keyboard.Key.LControl: //NB
		case Keyboard.Key.RControl:
			{
				return 0x1D;
			}
		case Keyboard.Key.A:
			{
				return 0x1E;
			}
		case Keyboard.Key.S:
			{
				return 0x1F;
			}
		case Keyboard.Key.D:
			{
				return 0x20;
			}
		case Keyboard.Key.F:
			{
				return 0x21;
			}
		case Keyboard.Key.G:
			{
				return 0x22;
			}
		case Keyboard.Key.H:
			{
				return 0x23;
			}
		case Keyboard.Key.J:
			{
				return 0x24;
			}
		case Keyboard.Key.K:
			{
				return 0x25;
			}
		case Keyboard.Key.L:
			{
				return 0x26;
			}
		case Keyboard.Key.SemiColon:
			{
				return 0x27;
			}
		case Keyboard.Key.Quote:
			{
				return 0x28;
			}
		case Keyboard.Key.Tilde:
			{
				return 0x29;
			}
		case Keyboard.Key.LShift:
			{
				shiftFlip=!shiftFlip;
				if(shiftFlip)
				{
					return 0x2A;
				}
				else
				{
					return 0xAA;
				}
			}
		case Keyboard.Key.BackSlash:
			{
				return 0x2B;
			}
		case Keyboard.Key.Z:
			{
				return 0x2C;
			}
		case Keyboard.Key.X:
			{
				return 0x2D;
			}
		case Keyboard.Key.C:
			{
				return 0x2E;
			}
		case Keyboard.Key.V:
			{
				return 0x2F;
			}
		case Keyboard.Key.B:
			{
				return 0x30;
			}
		case Keyboard.Key.N:
			{
				return 0x31;
			}
		case Keyboard.Key.M:
			{
				return 0x32;
			}
		case Keyboard.Key.Comma:
			{
				return 0x33;
			}
		case Keyboard.Key.Period:
			{
				return 0x34;
			}
		case Keyboard.Key.Slash:
			{
				return 0x35;
			}
		case Keyboard.Key.RShift:
			{
				shiftFlip=!shiftFlip;
				if(!shiftFlip)
				{
					return 0x36;
				}
				else
				{
					return 0xB6;
				}
			}
			/*
			case X:
			{
				return 0x37;
			}
			*/
		case Keyboard.Key.LAlt:
		case Keyboard.Key.RAlt:
			{
				return 0x38;
			}
		case Keyboard.Key.Space:
			{
				return 0x39;
			}
			/*  Caps lock
			case X:
			{
				return 0x3A;
			}
			*/
		case Keyboard.Key.F1:
			{
				return 0x3B;
			}
		case Keyboard.Key.F2:
			{
				return 0x3C;
			}
		case Keyboard.Key.F3:
			{
				return 0x3D;
			}
		case Keyboard.Key.F4:
			{
				return 0x3E;
			}
		case Keyboard.Key.F5:
			{
				return 0x3F;
			}
		case Keyboard.Key.F6:
			{
				return 0x40;
			}
		case Keyboard.Key.F7:
			{
				return 0x41;
			}
		case Keyboard.Key.F8:
			{
				return 0x42;
			}
		case Keyboard.Key.F9:
			{
				return 0x43;
			}
		case Keyboard.Key.F10:
			{
				return 0x44;
			}
			/*
			case X: //Numlock
			{
				return 0x45;
			}
			*/
			/*
			case X: //Scroll lock
			{
				return 0x46;
			}
			*/
		case Keyboard.Key.Home:
			{
				return 0x47;
			}
		case Keyboard.Key.Up:
			{
				return 0x48;
			}
		case Keyboard.Key.PageUp:
			{
				return 0x49;
			}
		case Keyboard.Key.Subtract:
			{
				return 0x4A;
			}
		case Keyboard.Key.Left:
			{
				return 0x4B;
			}
			/*
			case Keyboard.Key.Left:
			{
				return 0x4C;
			}
			*/
		case Keyboard.Key.Right:
			{
				return 0x4D;
			}
		case Keyboard.Key.Add:
			{
				return 0x4E;
			}
		case Keyboard.Key.End:
			{
				return 0x4F;
			}
		case Keyboard.Key.Down:
			{
				return 0x50;
			}
		case Keyboard.Key.PageDown:
			{
				return 0x51;
			}
		case Keyboard.Key.Insert:
			{
				return 0x52;
			}
		case Keyboard.Key.Delete:
			{
				return 0x53;
			}
			/*
			case [0x54-0x84]
			{
				return sth;
			}
			*/
		case Keyboard.Key.F11:
			{
				return 0x85;
			}
		case Keyboard.Key.F12:
			{
				return 0x86;
			}
		default:
			{
				//assert(0, "Unknown keypress character!" ~ format!"0x%04X"(ch));
				return 0xFF;
			}
		}
		+/
		return 0xFF;
	}

	private IBM_PC_COMPATIBLE pc;
	private MemoryX86 memory;
	private PIC intr_controller;
	private bool shiftFlip;

	private ubyte port61reg;
	private ubyte scancode;
	private ubyte status;
	shared int keypress;
}
