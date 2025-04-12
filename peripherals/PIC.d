module IBM_PIC;

import ibm_pc_com;
import std.stdio;
import simplelogger;
import cpu.x86.processor;

class PIC
{
	this(IBM_PC_COMPATIBLE param)
	{
		pc=param;
		pc.AddINOUTHandler(0x20, &PICControlPortInput); // I/O address 0x20 - 8-bit access!
		pc.AddINOUTHandler(0x21, &PICControlPortInput); // I/O address 0x21 - 8-bit access!
		pc.AddINOUTHandler(0x462, &PICControlPortInput); // I/O address 0x462 - 8-bit access!
		CPU=pc.GetCPU();
		base=0x08;
	}

	public void PICControlPortInput(ushort port, ref ushort value, bool infunc)
	{
		switch(port)
		{
		case 0x20: //command
			{
				if(!infunc)
				{
					switch(value)
					{
						case 0x20: // EOI
						{
							x86log.logf("End-of-transmission command");
							lastIRQnum=0; // Reset the IRQ priority register
							break;
						}
						default:
						{
							x86log.logf("Unknown PIC command: 0x%04X", value);
						}
					}
				}
				break;
			}
		case 0x21: //data
			{
				if(infunc)
				{
					value=IMR;
				}
				break;
			}
		case 0x462: //Software NMI
			{
				if(!infunc && value&7)
				{
					CPU.SignalNMI();
				}
				break;
			}
		default:
			{
				x86log.logf("Unknown PIC port 0x%04X", port);
				break;
			}
		}
	}

	public void AcknowledgeInterrupts()
	{
		if(CPU.InterruptsCanBeServiced())
		{
			for(ubyte i=0; i<7; i++)
			{
				if((IRR>>i)&0x1)
				{
					if(!pc.noExternIntFunc())
					{
						CPU.SignalInt(cast(ubyte)(base+i));
					}
					IRR&=~(1<<i);
					return;
				}
			}
		}
	}

	public void IRQ(ubyte num)
	{
		if(num>=8) //Everything within bounds
		{
			return;
		}
		IRR|=1<<num;
	}

	private IBM_PC_COMPATIBLE pc;
	private ProcessorX86 CPU;
	private ubyte base;
	private ubyte IMR;
	private ubyte IRR;
	private ubyte lastIRQnum;
}
