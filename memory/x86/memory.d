module x86_memory;

import core.stdc.string;
import std.stdio;
import core.thread;
import core.stdc.stdint;
import core.stdc.string;
import simplelogger;
import std.format;
import std.conv;


final class MemoryX86
{
	this()
	{
		memset(&RAM, 0xF1, 0x100000); //int1 - breakpoint instruction
		writefln("Base RAM address: 0x%X", cast(int)&RAM);
		string output=format!"Base RAM address: 0x%X"(cast(int)&RAM);
		x86log.logf(output);
	}

	public ushort ReadMemory16(ushort seg, ushort off)
	{
		ushort toreturn=RAM.ptr[((seg<<4)+off) & maskbit]|RAM[((seg<<4)+off+1) & maskbit]<<8;
		return toreturn;
	}

	public ubyte ReadMemory8(ushort seg, ushort off)
	{
		ubyte toreturn=RAM.ptr[((seg<<4)+off) & maskbit];
		return toreturn;
	}

	public void WriteMemory(ushort seg, ushort off, ushort val)
	{
		RAM[((seg<<4)+off) & maskbit]=val & 0xFF;
		RAM[((seg<<4)+off+1) & maskbit]=(val >> 8) & 0xFF;
	}

	public void WriteMemory(ushort seg, ushort off, ubyte val)
	{
		RAM[((seg<<4)+off) & maskbit]=val;
	}

	public ubyte* GetAbsAddress8(uint addr)
	{
		return &RAM[addr];
	}

	public ubyte* GetAbsAddress8(ushort seg, ushort off)
	{
		return &RAM[((seg<<4)+off) & maskbit];
	}

	public ushort* GetAbsAddress16(uint addr)
	{
		return cast(ushort*)&RAM[addr];
	}

	public ushort* GetAbsAddress16(ushort seg, ushort off)
	{
		return cast(ushort*)&RAM[((seg<<4)+off) & maskbit];
	}

	public bool LoadMemory(uint32_t addr, ref ubyte[] bytes)
	{
		if(cast(uint64_t)bytes.length>=cast(uint64_t)0xFFFFFF || cast(uint64_t)0xFFFFFF<cast(uint64_t)addr+cast(uint64_t)bytes.length) //Overload!
		{
			return false;
		}
		memcpy(&RAM[addr], cast(void*)bytes, bytes.length);
		return true;
	}

	public bool GetA20GateState()
	{
		if(maskbit==0xEFFFFF)
		{
			return false;
		}
		else
		{
			return true;
		}
	}

	public void ToggleGateA20(bool val)
	{
		if(!val)
		{
			maskbit=0xEFFFFF;
		}
		else
		{
			maskbit=0xFFFFFF;
		}
	}

	public void MemSetB(const ushort seg, const ushort offs, const ushort length, const ubyte number)
	{
		if(offs+length>0xFFFF)
		{
			return;
		}
		void* ptr=GetAbsAddress8(seg, offs);
		if(ptr==null)
		{
			return;
		}
		memset(ptr, number, length);
	}

	public void MemSetW(const ushort seg, const ushort offs, const ushort length, const ushort number)
	{
		if(offs+length>0xFFFF)
		{
			return;
		}
		ushort* ptr=cast(ushort*)GetAbsAddress8(seg, offs);
		if(ptr==null)
		{
			return;
		}
		for(int i=0; i<length; i++)
		{
			ptr[i]=number;
		}
	}

	public __gshared ubyte* GetRamPointer()
	{
		return cast(ubyte*)&RAM;
	}

	private __gshared ubyte[0x100000] RAM; // 1MByte RAM - 186 size
	private uint maskbit=0xEFFFFF; //used in order to make a20 gate control easy
}
