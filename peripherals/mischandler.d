module x86_diskhandler;

import ibm_pc_com;
import std.stdio;
import simplelogger;
import memory.x86.memory;
import cpu.x86.processor;
import cpu.decl;
import core.stdc.string;
import std.exception;
import std.digest;
import std.format;


class Misc_Handler
{
	this(IBM_PC_COMPATIBLE param)
	{
		pc=param;
		memory=pc.GetCPU().ExposeRam();
		pc.GetCPU().SetVMHandler(&VmInvokeHandler);
	}

	void VmInvokeHandler(ProcessorX86 CPU)
	{
		void setFlagsCarryState(bool state)
		{
			FLAGSreg16 flags;
			flags.word=memory.ReadMemory16(pc.GetCPU().SS_reg.word, cast(ushort)(pc.GetCPU().SP.word+4));
			flags.CF=state;
			memory.WriteMemory(pc.GetCPU().SS_reg.word, cast(ushort)(pc.GetCPU().SP.word+4), flags.word);
		}
		x86log.logf("int13h with ah=0x%02X", CPU.AX.hfword[h]);
		switch(CPU.AX.hfword[h])
		{
			case 0x0:
			{
				setFlagsCarryState(false);
				break;
			}
			case 0x1:
			{
				setFlagsCarryState(false);
				break;
			}
			case 0x2:
			{
				ubyte[]* target=cast(ubyte[]*)memory.GetAbsAddress16(CPU.ES_reg.word, CPU.BX.word);
				if((CPU.ES_reg.word*0x10)+CPU.BX.word>0xFFFFF) //Limits!
				{
					setFlagsCarryState(true);
					return;
				}
				else
				{
					CPU.FLAGS_reg.CF=false;
				}
				ubyte* targetaddr=memory.GetAbsAddress8(CPU.ES_reg.word, CPU.BX.word);
				if(CPU.DX.hfword[l]<0x80)
				{
					if(!floppyLoaded)
					{
						x86log.logf("Floppy image not loaded!");
						setFlagsCarryState(true);
						return;
					}
					ubyte sectors_count=CPU.AX.hfword[l];
					ubyte head=CPU.DX.hfword[h];
					ubyte beginsector=CPU.CX.hfword[l];
					ubyte cyclinder=CPU.CX.hfword[h];

					ulong LBA=0;
					if(floppyimage.size()==1474560)
					{
						LBA=(cyclinder*2+head)*18+(beginsector-1);
					}
					else if(floppyimage.size()==737280)
					{
						LBA=(cyclinder*2+head)*9+(beginsector-1);
					}
					else if(floppyimage.size()==184320)
					{
						LBA=(cyclinder*1+head)*9+(beginsector-1);
					}
					else if(floppyimage.size()==368640)
					{
						LBA=(cyclinder*2+head)*9+(beginsector-1);

					}
					else if(floppyimage.size()==163840)
					{
						LBA=(cyclinder*1+head)*8+(beginsector-1);
					}
					else if(floppyimage.size()==512) // Testing boot sectors...
					{
						LBA=0;
					}
					else
					{
						x86log.logf("Unknown floppy image type | Size: %s", floppyimage.size());
					}
					x86log.logf("Size of image: %s", floppyimage.size());
					x86log.logf("LBA: %s | Beginsector: %s", LBA, beginsector);
					x86log.logf("Head: %s Cyclinder: %s Sectors to read: %s", head, cyclinder, sectors_count);
					x86log.logf("ES=0x%04X BX=0x%04X", CPU.ES_reg.word, CPU.BX.word);
					x86log.logf("Return to CS=0x%04X IP=0x%04X", *memory.GetAbsAddress16(CPU.SS_reg.word, cast(ushort)(CPU.SP.word+2)), *memory.GetAbsAddress16(CPU.SS_reg.word, CPU.SP.word));
					try
					{
						floppyimage.seek(LBA*512);
					}
					catch(Exception e)
					{
						x86log.logf("Error while trying to seek in file %s.\nFile not opened!", floppyimage.name);
						//To-do: Do something else rather than return...
						return;
					}
					ubyte[] data=new ubyte[sectors_count*512];

					//To-do: This throws exceptions way too often - Probably file is not allowed to be read?
					try
					{
						floppyimage.rawRead(data);
					}
					catch(Exception e)
					{
						//pc.GetVideo().FreeLibrary();
						x86log.logf("File %s: Exception %s", floppyfile, e.msg);
						//pc.GetVideo().InitLibrary();
						setFlagsCarryState(true);
						//To-do: Do something else rather than return...
						return;
					}
					x86log.logf("Data read from disc: ");
					string str;
					foreach(ubyte b; data)
					{
						str~=format!"%02X "(b);
					}
					x86log.logf(str);
					memcpy(targetaddr, data.ptr, sectors_count*512);
					setFlagsCarryState(false);
				}
				else
				{
					x86log.logf("Harddrive images not supported, yet!");
					setFlagsCarryState(true);
				}
				break;
			}
			default:
			{
				setFlagsCarryState(true);
				x86log.logf("Invalid int13h function 0x%02X", CPU.AX.hfword[h]);
				x86log.logf("Return to CS=0x%04X IP=0x%04X", *memory.GetAbsAddress16(CPU.SS_reg.word, cast(ushort)(CPU.SP.word+2)), *memory.GetAbsAddress16(CPU.SS_reg.word, CPU.SP.word));
			}
		}
	}

	void SetFloppyDriveImage(string str)
	{
		floppyLoaded=true;
		floppyimage=File(str, "r+b");
		floppyfile=str;
	}

	void SetHardDriveImage(string str)
	{
		harddiskimage=File(str, "r+b");
		diskfile=str;
	}

	private IBM_PC_COMPATIBLE pc;
	private MemoryX86 memory;
	private string diskfile;
	private string floppyfile;
	private ubyte status;

	bool floppyLoaded=false;
	File floppyimage;
	File harddiskimage;
}
