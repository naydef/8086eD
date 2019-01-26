module init;

import ibm_pc_com;
import std.stdio;
import core.stdc.stdlib;
import std.conv;

immutable string program_version="0.3.0";


void main(string[] args)
{
	writefln("8086eD emulator - v%s", program_version);
	writefln("Specifications:\n* NEC v20 CPU\n* 640KB RAM\n* Booting from floppy image");
	writefln("Type \'help\' for list of usable commands");
	writefln("Type \'start\' to begin execution");
	
	
	auto machine =new IBM_PC_COMPATIBLE();
	if(!machine.ValidRomImage())
	{
		writefln("Error loading ROM image!");
		return;
	}
	if(args.length>=2)
	{
		machine.LoadFloppy(args[1]);
		writefln("Loading floppy image %s", args[1]);
	}
	if(machine.CommandWindow())
	{
		while(1)
		{
			machine.ProcedureFunc();
		}
	}
}
