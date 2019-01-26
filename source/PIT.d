module IBM_PIT;

import ibm_pc_com;
import std.stdio;
import simplelogger;
import x86_memory;
import IBM_PIC;
import std.datetime;
import x86_processor;


//the 8253 PIT Emulation module
//To-do: Actually implement the PIT
class PIT
{
	this(IBM_PC_COMPATIBLE param)
	{
		pc=param;
		memory=pc.GetCPU().ExposeRam();
		currtick=lasttick=MonoTime.currTime().ticks();
		pittick=MonoTime.ticksPerSecond()/18;
	}
	
	void AcknowledgeInterrupts()
	{
		if(MonoTime.currTime().ticks()>=lasttick+pittick)
		{
			pc.GetPIC().IRQ(0);
			lasttick=MonoTime.currTime().ticks();
		}
		currtick=MonoTime.currTime().ticks();
	}

	private IBM_PC_COMPATIBLE pc;
	private MemoryX86 memory;
	private PIC pic;
	private ulong pittick;
	private ulong currtick;
	private ulong lasttick;

}