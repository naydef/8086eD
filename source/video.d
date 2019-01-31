module video_controller;

import ibm_pc_com;
import std.stdio;
//import pdcurses;
import simplelogger;
import x86_memory;
import std.concurrency;
import core.sync.mutex;
import sfml_interfacing;
import cpu.decl;



class Video_Controller
{
	this(IBM_PC_COMPATIBLE param)
	{
		pc=param;
		memory=pc.GetCPU().ExposeRam();
		pc.AddINOUTHandler(0xE301, &VideoControlPortInput); // I/O address 0xE301 is the video base address register - 16-bit access!
		pc.AddINOUTHandler(0x03DA, &VideoControlPortInput); // I/O address 0x03DA
		pc.AddINOUTHandler(0xA3D8, &VideoControlPortInput); // I/O address - CGA mode control register
		pc.AddINOUTHandler(0x03D9, &VideoControlPortInput); // I/O address - CGA mode colour register
		pc.AddINOUTHandler(0x03D4, &VideoControlPortInput); // I/O address - index port
		pc.AddINOUTHandler(0x03D5, &VideoControlPortInput); // I/O address - data port
		pc.AddINOUTHandler(0x03B4, &VideoControlPortInput); // I/O address - index port
		pc.AddINOUTHandler(0x03B5, &VideoControlPortInput); // I/O address - data port
		pc.AddINOUTHandler(0x03BA, &VideoControlPortInput); // I/O address - CRT status register
		register_2=0x0;
	}
	
	/* 
	Register 1:
	|text mode library enable bit|clear screen|res|res|res|res|res|res|
	
	Register 2:
	|16-bit video base|
	*/
	public void VideoControlPortInput(ushort port, ref ushort value, bool infunc)
	{
		switch(port)
		{
		case 0xE303:
			{
				//Nope
				break;
			}
		case 0x03DA:
			{
				if(infunc)
				{
					value=video_retrace_reg;
				}
				break;
			}
		case 0x03D4:
		case 0x03B4:
			{
				if(!infunc)
				{
					indextoaccess=value;
				}
				break;
			}
		case 0x03D5:
		case 0x03B5:
			{
				if(!infunc)
				{
					HandleOutputToVGAReg(indextoaccess, value);
				}
				break;
			}
		case 0x03BA:
			{
				if(infunc)
				{
					value=video_retrace_reg;
				}
				break;
			}
		case 0x03D9:
			{
				if(!infunc)
				{
					color_reg.data=value&0xFF;
				}
				break;
			}
		default:
			{
				x86log.logf("Unknown video port 0x%04X", port);
				break;
			}
		}
	}
	
	private void HandleOutputToVGAReg(ushort index, ushort val)
	{
		switch(index)
		{
		case 0xA: //Cursor enable register
			{
				if(val&0b100000)
				{
					//curs_set(0);
					video_state.active_cursor=false;
				}
				else
				{
					video_state.active_cursor=true;
					//curs_set(1);
				}
				break;
			}
		case 0xE:
			{
				//Ugly way to set shared array elements
				//To-do: Improve
				Pos local_pos;
				local_pos.data=video_state.position_cursor.data;
				local_pos.part[1]=val&0xFF;
				video_state.position_cursor.data=local_pos.data;
				cursorpos.part[1]=val&0xFF;
				break;
			}
		case 0xF:
			{
				//Ugly way to set shared array elements
				//To-do: Improve
				Pos local_pos;
				local_pos.data=video_state.position_cursor.data;
				local_pos.part[0]=val&0xFF;
				video_state.position_cursor.data=local_pos.data;
				cursorpos.part[0]=val&0xFF;
				video_state.color_reg.data=color_reg.data;
				break;
			}
		default:
			{
				x86log.logf("Unknown CGA/VGA/EGA/MDA register 0x%04X", index);
			}
		}
	}
	

	//We also "think" here
	public void AcknowledgeInterrupts()
	{
		video_state.vmode=memory.ReadMemory8(0x0040, 0x0049); // Hack: Read the video mode from 0040h:0049h
		if(counter%2000==0)
		{
			video_mode=video_state.vmode;
			if(video_mode==0x02 || video_mode==0x07)
			{
				video_state.baseRamAddress=0xb0000;
				if(video_mode==2)
				{
					video_state.baseRamAddress=0xb8000;
				}
				video_state.width=720;
				video_state.height=400;
				video_state.textmode=true;
			}
			else if(video_mode==0x03)
			{
				video_state.width=720;
				video_state.height=400;
				video_state.textmode=true;
				video_state.baseRamAddress=0xb8000;
			}
			else if(video_mode==0x04)
			{
				video_state.width=320;
				video_state.height=200;
				video_state.textmode=false;
				video_state.baseRamAddress=0xb8000;
			}
		}
		
		//Random stuff to make things work
		if(counter%16==0)
		{
			video_retrace_reg=0b1001;
		}
		if(counter%30==0)
		{
			video_retrace_reg=0b0000;
		}
		counter+=1;
	}

	private IBM_PC_COMPATIBLE pc;
	private MemoryX86 memory;
	private ubyte register_1;
	private ushort register_2;
	private ubyte video_mode;
	private ubyte video_retrace_reg;
	private ubyte[ubyte] colormatching;
	private ushort indextoaccess;
	private Pos cursorpos;
	private cga_color_reg color_reg;
	ulong counter;
}