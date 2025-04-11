module ports;

import ibm_pc_com;
import std.stdio;
import simplelogger;
import memory.x86.memory;

class Port_Handler
{
	this(IBM_PC_COMPATIBLE param)
	{
		pc=param;
		memory=pc.GetCPU().ExposeRam();
		pc.AddINOUTHandler(0x0062, &PortIO);
		pc.AddINOUTHandler(0x0063, &PortIO);
		pc.AddINOUTHandler(0x0201, &PortIO);
	}

	public void PortIO(ushort port, ref ushort value, bool infunc)
	{
		switch(port)
		{
		//0063 PPI (XT only) command mode register  (read dipswitches)
		//Note: We also hook port 0062, because the Generic Super XT BIOS reads the data from this port(Bug?)
		//Also: It doesn't work as expected, lower 2 bits set the video mode...
		case 0x0062:
		case 0x0063:
			{
				if(infunc)
				{
					value=0b010;
				}
				break;
			}
		case 0x0201:
			{
				if(infunc)
				{
					value=0xFF;
				}
				break;
			}
		default:
			{
				x86log.logf("Unknown misc port 0x%04X", port);
				break;
			}
		}
	}

	private IBM_PC_COMPATIBLE pc;
	private MemoryX86 memory;
	private ubyte counter;
}
