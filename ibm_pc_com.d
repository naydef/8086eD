module ibm_pc_com;

import cpu.x86.processor;
import vriparser;
import std.stdio;
import std.experimental.logger;
import simplelogger;
import peripherals.video;
import peripherals.PIC;
//import pdcurses;
import peripherals.ports;
import peripherals.keyboard;
import core.sync.mutex;
import std.array;
import core.thread;
import std.conv;
import peripherals.PIT;
import peripherals.mischandler;
import std.file;
import sfml_interface;

immutable string rom_image="romimage.bin";

class IBM_PC_COMPATIBLE
{
	this()
	{
		writefln("Processor INIT");
		proc=new ProcessorX86(this);
		video=new Video_Controller(this);
		interrupt_controller=new PIC(this);
		porthandler=new Port_Handler(this);
		keyboard=new XT_Keyboard(this, interrupt_controller);
		pit=new PIT(this);
		misc=new Misc_Handler(this);
		proc.SetInOutFunc(&INOUTFunc);
		AddINOUTHandler(0x0080, &port80hout);

		ramlayoutfile=new VRI_FILE(rom_image);
		if(ramlayoutfile.Errno()!=LOAD_VRI_SUCCESS)
		{
			writefln("Error loading file %s\nError: %s", rom_image, ramlayoutfile.Errno());
			isvalidromimage=false;
			return;
		}
		for(int i=0; i<ramlayoutfile.GetNumberOfRegions; i++)
		{
			auto memlayoutregion=ramlayoutfile.GetRegion(i);
			proc.ExposeRam().LoadMemory(memlayoutregion.base, memlayoutregion.ramdata);
		}
		singlestep=false;
		singlesteponint1=false;
		isvalidromimage=true;
		//VideoModeText();
	}

	ref GetCPU()
	{
		return proc;
	}

	void AcknowledgeInterrupts() //Here we will send interrupts to the CPU
	{
		video.AcknowledgeInterrupts();
		keyboard.AcknowledgeInterrupts();
		pit.AcknowledgeInterrupts();
		interrupt_controller.AcknowledgeInterrupts();
	}

	public void AddINOUTHandler(ushort port, void delegate(ushort, ref ushort, bool) func)
	{
		if(func !is null)
		{
			inoutfunclist[port]=func;
		}
	}

	public void port80hout(ushort port, ref ushort value, bool infunc)
	{
		if(!infunc) x86log.logf("Port 80h out: %04X", value);
	}

	public void OnStartVM()
	{
		//video.InitLibrary();
		video_state.videoactive=true;
	}

	public bool ValidRomImage()
	{
		return isvalidromimage;
	}

	private void INOUTFunc(ushort port, ref ushort value, bool infunc)
	{
		auto func=(port in inoutfunclist);
		if(func !is null)
		{
			inoutfunclist[port](port, value, infunc);
		}
		else
		{
			if(infunc)
			{
				x86log.logf("Input from unknown port 0x%04X", port);
			}
			else
			{
				x86log.logf("Output to unknown port 0x%04X and value %04X", port, value);
			}
			if(infunc)
			{
				value=0x00;
			}
		}
	}

	ref VRI_FILE GetImageFile()
	{
		return ramlayoutfile;
	}

	/*
	void VideoModeText()
	{
		video.InitLibrary();
	}
	*/

	ref PIC GetPIC()
	{
		return interrupt_controller;
	}

	//true-execution | false-stop execution
	bool CommandWindow(string sig="") //Also debug window
	{
		x86instr.flush();
		//video.FreeLibrary();
		string input;
		if(sig.length>0)
		{
			writefln("Command prompt opened due to %s", sig);
		}
		bool singlestep=false;
		bool singlesteponint1=false;
		while(1)
		{
			void newlinepointer()
			{
				stderr.writef("\n-> ");
			}
			newlinepointer();
			input=readln();
			if(input is null)
			{
				continue;
			}
			auto command=input.split();
			if(command.length <=0)
			{
				continue;
			}

			if(command[0] == "start")
			{
				/*
				if(!this.GetCPU().GetLogState())
				{
					initscr();
					if(has_colors())
					{
						start_color();
					}
				}
				*/
				this.OnStartVM();
				return true;
			}
			else if(command[0] == "exit")
			{
				return false;
			}
			else if(command[0] == "imageinfo")
			{
				auto imagefile=this.GetImageFile();
				for(int i=0; i<imagefile.GetNumberOfRegions; i++)
				{
					auto memlayoutregion=imagefile.GetRegion(i);
					writefln("================================================
Region %d
Size: 0x%08X
Base: 0x%08X
Bitfield: 0x%08X", i, memlayoutregion.ramdata.length, memlayoutregion.base, memlayoutregion.bitfield);
				}
			}
			else if(command[0] == "singlestep")
			{
				//if()
				singlestep=!singlestep;
				(singlestep) ? writefln("Singlestep enabled!") : writefln("Singlestep disabled!");
			}
			else if(command[0] == "singlestep_on_int1")
			{
				writeln("Singlestep on int1 activated");
				singlesteponint1=true;
			}
			else if(command[0]=="loginstructions")
			{
				this.GetCPU().SetInstructionLog(true);
				writeln("Instruction logging on!");
			}
			else if(command[0]=="help")
			{
				writeln("Command list:");
				writeln("# help - This command list");
				writeln("# start - Start execution of instructions");
				writeln("# imageinfo - Shows a list of ROM images loaded into the machine memory");
				writeln("# singlestep - Enables singlestep mode");
				writeln("# singlestep_on_int1 - Same as \'singlestep\' command, but starts singlestep mode after trying to exec 0xF1");
				writeln("# loginstructions - All instructions executed will be logged to instructions.log file with detailed register and stack info");
				writeln("# R - Show content of all registers");
				writeln("# R <reg> <num16> - Set the content of a register");
				writeln("# S - Prints stack content relative to BP and SP +-4");
				writeln("# SetExecBreakpointL <CS num16> <IP num16> - Set one instruction breakpoint at segment:ofset");
				writeln("# LoadFloppyImage - Loads file of floppy image, from which the BIOS will try to boot");
				writeln("# LoadHardDiskImage - Loads file of floppy image, from which the BIOS will try to boot(not working, currently)");
				writeln("# noExternInt - Disables external processor interrupts(like CLI instruction executed)");
			}
			else if(command[0]=="R" || command[0]=="r")
			{
				if(command.length==1)
				{
					this.GetCPU().DumpCPUStateToScreen();
				}
				else if(command.length==3)
				{
					if(command[1]=="AX")
					{
						GetCPU().AX.word=std.conv.to!ushort(command[2], 16);
					}
					else if(command[1]=="BX")
					{
						GetCPU().BX.word=std.conv.to!ushort(command[2], 16);
					}
					else if(command[1]=="CX")
					{
						GetCPU().CX.word=std.conv.to!ushort(command[2], 16);
					}
					else if(command[1]=="DX")
					{
						GetCPU().DX.word=std.conv.to!ushort(command[2], 16);
					}
					else if(command[1]=="SI")
					{
						GetCPU().SI.word=std.conv.to!ushort(command[2], 16);
					}
					else if(command[1]=="DI")
					{
						GetCPU().DI.word=std.conv.to!ushort(command[2], 16);
					}
					else if(command[1]=="SP")
					{
						GetCPU().SP.word=std.conv.to!ushort(command[2], 16);
					}
					else if(command[1]=="BP")
					{
						GetCPU().BP.word=std.conv.to!ushort(command[2], 16);
					}
					else if(command[1]=="CS")
					{
						GetCPU().CS_reg.word=std.conv.to!ushort(command[2], 16);
					}
					else if(command[1]=="DS")
					{
						GetCPU().DS_reg.word=std.conv.to!ushort(command[2], 16);
					}
					else if(command[1]=="SS")
					{
						GetCPU().SS_reg.word=std.conv.to!ushort(command[2], 16);
					}
					else if(command[1]=="ES")
					{
						GetCPU().ES_reg.word=std.conv.to!ushort(command[2], 16);
					}
					else if(command[1]=="FLAGS")
					{
						GetCPU().FLAGS_reg.word=std.conv.to!ushort(command[2], 16);
					}
					else if(command[1]=="IP")
					{
						GetCPU().IP_reg.word=std.conv.to!ushort(command[2], 16);
					}
					else
					{
						writefln("Incorrect register...");
					}

				}
				else
				{
					writefln("%s: Bad usage of parameters!", command[0]);
				}
			}
			else if(command[0]=="S" || command[0]=="s")
			{
				if(command.length==1)
				{
					GetCPU().PrintStackToScreen();
				}
			}
			else if(command[0]=="SetExecBreakpointL")
			{
				if(command.length==3)
				{
					ushort CS=std.conv.to!ushort(command[1], 16);
					ushort IP=std.conv.to!ushort(command[2], 16);
					GetCPU.SetLinearBreakpoint(CS, IP);
					writefln("Setting execution breakpoint to CS=0x%04X | IP=0x%04X", CS, IP);
				}
				else
				{
					writefln("%s: Bad usage of parameters!", command[0]);
				}
			}
			else if(command[0]=="LoadFloppyImage")
			{
				if(command.length==2 && exists(command[1]))
				{
					misc.SetFloppyDriveImage(command[1]);
					writefln("Loaded file %s as floppy disk", command[1]);
				}
				else
				{
					writefln("Too little arguments or file doesn't exist!");
				}
			}
			else if(command[0]=="LoadHardDiskImage")
			{
				if(command.length==2 && exists(command[1]))
				{
					misc.SetHardDriveImage(command[1]);
					writefln("Loaded file %s as harddrive", command[1]);
				}
				else
				{
					writefln("Too little arguments or file doesn't exist!");
				}
			}
			else if(command[0]=="noExternInt")
			{
				noExternInt=!noExternInt;
				if(noExternInt)
				{
					writefln("No external interrupts!");
				}
				else
				{
					writefln("External interrupts active!");
				}
			}
			else
			{
				writefln("Bad command!");
			}

		}
	}

	public void LoadFloppy(string str)
	{
		misc.SetFloppyDriveImage(str);
	}

	void ProcedureFunc()
	{
		while(1)
		{
			ushort prevCS=this.GetCPU().GetCS();
			ushort prevIP=this.GetCPU().GetIP();
			if(!this.GetCPU().Halted())
			{
				this.AcknowledgeInterrupts();
				this.GetCPU().ExecuteInstruction();
			}
			else
			{
				this.AcknowledgeInterrupts();
				Thread.sleep(dur!("nsecs")(100));
			}

			if(singlesteponint1 && this.GetCPU().ExposeRam().ReadMemory8(prevCS, cast(ushort)(prevIP))==0xF1)
			{
				singlestep=true;
				singlesteponint1=false;
			}

			if(singlestep)
			{
				CommandWindow("singlestepping");
			}
		}
	}

	public Video_Controller GetVideo()
	{
		return video;
	}

	public bool noExternIntFunc()
	{
		return noExternInt;
	}

	private ProcessorX86 proc;
	private Video_Controller video;
	private PIC interrupt_controller;
	private VRI_FILE ramlayoutfile;
	private Port_Handler porthandler;
	private XT_Keyboard keyboard;
	private Misc_Handler misc;
	private bool singlestep;
	private bool singlesteponint1;
	private bool ncursesdraw;
	private bool isvalidromimage;
	private PIT pit;
	private bool noExternInt;
	private void delegate(ushort, ref ushort, bool)[ushort] inoutfunclist;
}
