module vriparser;

import std.stdio; 
import core.stdc.stdint;
import std.file;
import std.conv;
import std.container.array;
import core.stdc.string;
import core.memory;

const int currver=0x01;

struct VRI_Image
{
public:
	align(1):
	char[4] magic;
	uint16_t ver;
	uint8_t[256] additionalinfo;
	uint32_t mdtsize;
	uint32_t mdtabsoffset;
};

struct VRI_Entry
{
	align(1):
	uint32_t ramimagebeginoffset;
	uint32_t rsize;
	uint32_t relocateaddr;
	uint32_t bitfield;
};

enum
{
	LOAD_VRI_SUCCESS=0
}

class VRI_Container
{
    align(1):
    uint32_t base;
    uint32_t bitfield;
    ubyte[] ramdata;
	~this()
	{
		GC.free(cast(void*)ramdata);
	}
};

class VRI_FILE
{
	this(string filename)
	{
		errno=0;
		if(filename.length<=0)
		{
			//throw new StringException("File is null");
			errno=1;
			return;
		}
		try
		{
			filehndl=File(filename, "r");
		}
		catch(Exception e)
		{
			errno=1;
		}
		if(!filehndl.isOpen())
		{
			//throw new StringException("File %s does not exist", filename);
			errno=2;
			return;
		}
		auto header=filehndl.rawRead(new VRI_Image[1]);
		if(to!string(header[0].magic)!="VRI\0")
		{
			errno=3;
			//throw new StringException("The file %s is not an Virtual Ram Image");
			return;
		}
		if(header[0].ver>currver)
		{
			errno=4;
			return;
		}
		
		auto entry=new VRI_Entry[(header[0].mdtsize)/16];
		
		filehndl.seek(header[0].mdtabsoffset);
		filehndl.rawRead(entry);
		
		memcpy(cast(void*)addinfo, cast(void*)header[0].additionalinfo, 256);
		foreach(i;0 .. header[0].mdtsize/16)
		{
			if(!entry[i].rsize)
			{
				continue;
			}
			auto container=new VRI_Container();
			container.base=entry[i].relocateaddr;
			filehndl.seek(entry[i].ramimagebeginoffset);
			auto content=new ubyte[entry[i].rsize];
			try
			{
				filehndl.rawRead(content);
			}
			catch(Exception e)
			{
				errno=1;
			}
			container.ramdata=content;
			entries.insertBack(container);
		}
	}
	
	ushort Errno()
	{
		return errno;
	}
	
	uint GetNumberOfRegions()
	{
		return entries.length;
	}
	
	ref VRI_Container GetRegion(uint index)
	{
		return entries[index];
	}
	
	ubyte[256] GetAddInfo()
	{
		return addinfo;
	}
	
	~this()
	{
		foreach(ref i; entries)
		{
			GC.free(cast(void*)i);
		}
	}
	
	private File filehndl;
	private Array!VRI_Container entries;
	private ushort errno;
	private ushort filever;
	private ubyte[256] addinfo;
}
