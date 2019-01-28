module sfml_interfacing;

import core.thread;
import dsfml.graphics;
import simplelogger;
import vga_fonts;
import std.datetime;
import std.stdio;

struct VideoState
{
	ubyte vmode;
	ushort width;
	ushort height;
	bool textmode;
	uint baseRamAddress;
	bool videoactive;
	bool active_cursor;
	Pos position_cursor;
	
};

union Pos
{
	ubyte[2] part;
	ushort data;
};

shared(VideoState) video_state;

void Render_Keyboard_Thread(shared(int) *keypresstopass, shared(ubyte*) RamPtr, shared)
{
	auto view_window=new RenderWindow(VideoMode(640, 480), "Graphics - 8086eD");
	static ushort currwidth=640;
	static ushort currheight=480;
	Image drawscreen=new Image;
	Texture textur=new Texture;
	Sprite toappear=new Sprite;
	view_window.clear(Color.Black);
	view_window.display();
	view_window.setFramerateLimit(40);
	auto startTime=MonoTime.currTime;
	
	while(view_window.isOpen())
	{
		//I live!
		if((currwidth!=video_state.width || currheight!=video_state.height) && (video_state.width || video_state.height))
		{
			currwidth=video_state.width;
			currheight=video_state.height;
			view_window.create(VideoMode(currwidth, currheight), "Screen - 8086eD");
			view_window.clear(Color.Black);
			view_window.display();
		}
		Event event;
		//Add 200 to width, because SFML... (buffer zone?)
		drawscreen.create(currwidth+200, currheight+200, Color(0, 0, 0));
		while(view_window.pollEvent(event))
		{
			if(event.type==event.EventType.Closed)
			{
				view_window.close();
			}
			if(event.type==event.EventType.KeyPressed)
			{
				if(event.key.code!=Keyboard.Key.Unknown)
				{
					*keypresstopass=event.key.code;
				}
			}
		}
		if(!video_state.videoactive)
		{
			view_window.clear(Color.Black);
			continue;
		}
		
		
		switch(video_state.vmode)
		{
		case 0x0:
			{
				break;
			}
		case 0x3:
			{
				for(uint h=0; h<25; h++)
				{
					for(uint w=0; w<80; w++)
					{
						ubyte character=RamPtr[video_state.baseRamAddress+(h*160+w*2)];
						ubyte attribute=RamPtr[video_state.baseRamAddress+(h*160+w*2+1)];
						//To-do: Make bit 7 of attributes byte do 16 colors or blinking later...
						DrawChar(drawscreen, character, w, h, GetColorFrom3or4B(attribute>>4), GetColorFrom3or4B(attribute&0b1111));
					}
				}
				break;
			}
		case 0x7:
			{
				for(uint h=0; h<25; h++)
				{
					for(uint w=0; w<80; w++)
					{
						ubyte character=RamPtr[video_state.baseRamAddress+(h*160+w*2)];
						ubyte attribute=RamPtr[video_state.baseRamAddress+(h*160+w*2+1)];
						if(attribute&0x70)
						{
							DrawChar(drawscreen, character, w, h, color_array[15], color_array[0]);
						}
						else if(!attribute)
						{
							DrawChar(drawscreen, character, w, h, color_array[0], color_array[0]);
						}
						else
						{
							DrawChar(drawscreen, character, w, h, color_array[0], color_array[7]);
						}
					}
				}
				break;
			}
		default:
			{
				//To-do: What to do?
			}
		}
		if(video_state.textmode)
		{
			if(video_state.active_cursor)
			{
				static bool switchvar;
				if(MonoTime.currTime-startTime>=dur!"msecs"(533)) // 1000/1.875=533.3333
				{
					switchvar=!switchvar;
					startTime=MonoTime.currTime;
				}
				if(switchvar)
				{
					Pos local_pos;
					local_pos.data=video_state.position_cursor.data;
					DrawCursor(drawscreen, local_pos.data%80, local_pos.data/80, Color(0xAA, 0xAA, 0xAA));
				}
			}
		}
		textur.loadFromImage(drawscreen);
		toappear.setTexture(textur);
		view_window.draw(toappear);
		view_window.display();
		core.thread.Thread.sleep(dur!("msecs")(15));
	}
}

Color[16] color_array=[
Color(0x00, 0x00, 0x00),
Color(0x00, 0x00, 0xAA),
Color(0x00, 0xAA, 0x00),
Color(0x00, 0xAA, 0xAA),
Color(0xAA, 0x00, 0x00),
Color(0xAA, 0x00, 0xAA),
Color(0xAA, 0x55, 0x00),
Color(0xAA, 0xAA, 0xAA),
Color(0x55, 0x55, 0x55),
Color(0x55, 0x55, 0xFF),
Color(0x55, 0xFF, 0x55),
Color(0x55, 0xFF, 0xFF),
Color(0xFF, 0x55, 0x55),
Color(0xFF, 0x55, 0xFF),
Color(0xFF, 0xFF, 0x55),
Color(0xFF, 0xFF, 0xFF)
];

ref Color GetColorFrom3or4B(ubyte color)
{
	return color_array[color&0b1111];
}

void DrawChar(Image drawscreen, ubyte character, uint w, uint h, Color background, Color foreground)
{
	//https://wiki.osdev.org/VGA_Fonts
	int cx,cy;
	static int[8] mask=[1,2,4,8,16,32,64,128];

	for(cy=0;cy<16;cy++)
	{
		for(cx=0;cx<8;cx++)
		{
			if(vgafont16[character*16+cy]&mask[cx])
			{
				drawscreen.setPixel(w*9-cx+8, h*16+cy, foreground);
			}
			else
			{
				drawscreen.setPixel(w*9-cx+8, h*16+cy, background);
			}
		}
		drawscreen.setPixel(w*9, h*16+cy, background);
	}
}

void DrawCursor(Image drawscreen, uint w, uint h, Color foreground)
{
	//https://wiki.osdev.org/VGA_Fonts
	int cx,cy;
	static int[8] mask=[1,2,4,8,16,32,64,128];

	for(cy=0;cy<2;cy++)
	{
		for(cx=0;cx<8;cx++)
		{
			drawscreen.setPixel(w*9-cx+8, h*16+15+cy, foreground);
		}
	}
}