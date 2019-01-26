module simplelogger;

import std.experimental.logger;
import std.format;
import std.stdio;

final class FileLoggerAlt
{
	this(wstring str)
	{
		filename=str;
		filehndl=File(str, "w");
		//filehndl.setvbuf(8192);
	}
	
	void log(string str)
	{
		filehndl.write(str);
		//filehndl.flush();
		//filehndl.sync();
	}
	
	void logf(string str)
	{
		filehndl.write(str);
		//filehndl.flush();
		//filehndl.sync();
	}
	
	void flush()
	{
		filehndl.flush();
	}
	
	~this()
	{
		
	}
	
	private wstring filename;
	private File filehndl;
}

FileLogger x86log;
FileLoggerAlt x86instr;
static this()
{
	x86log=new FileLogger("turboD86.log");
	x86instr=new FileLoggerAlt("instructions.log");
}