module sfml_interface;

import core.thread;
import simplelogger;
import vgafonts;
import std.datetime;
import std.stdio;
import cpu.decl;
import arsd.color;
import arsd.minigui;

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
	uint properties;
	cga_color_reg color_reg;
};

union Pos
{
	ubyte[2] part;
	ushort data;
};

shared(VideoState) video_state;

void Render_Keyboard_Thread(shared(int)* keypresstopass, shared(ubyte*) RamPtr)
{
	/*
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
		case 0x04:
		case 0x05:
			{
				uint counter1=0;
				uint counter2=0;
				for(uint h=0; h<video_state.height; h++)
				{
					for(uint w=0; w<video_state.width; w+=4)
					{
						ubyte colour=0;
						if(h%2==0)
						{
							colour=RamPtr[video_state.baseRamAddress+counter1];
							counter1++;
						}
						else
						{
							colour=RamPtr[video_state.baseRamAddress+counter2+0x2000];
							counter2++;
						}
						//Unwinded loop
						cga_color_reg temp;
						temp.data=video_state.color_reg.data;
						drawscreen.setPixel(w, h, (colour>>6&0b11) ? cga_color_array_mode_4[temp.paletteSet][(colour>>6&0b11)|temp.brightForeground<<2] : GetColorFrom3or4B(temp.backgroundColour));

						drawscreen.setPixel(w+1, h, (colour>>4&0b11) ? cga_color_array_mode_4[temp.paletteSet][(colour>>4&0b11)|temp.brightForeground<<2] : GetColorFrom3or4B(temp.backgroundColour));

						drawscreen.setPixel(w+2, h, (colour>>2&0b11) ? cga_color_array_mode_4[temp.paletteSet][(colour>>2&0b11)|temp.brightForeground<<2] : GetColorFrom3or4B(temp.backgroundColour));

						drawscreen.setPixel(w+3, h, (colour&0b11) ? cga_color_array_mode_4[temp.paletteSet][(colour&0b11)|temp.brightForeground<<2] : GetColorFrom3or4B(temp.backgroundColour));


					}
				}
				break;
			}
		case 0x06:
			{
				uint counter1=0;
				uint counter2=0;
				for(uint h=0; h<video_state.height; h++)
				{
					for(uint w=0; w<video_state.width; w+=8)
					{
						ubyte colour=0;
						if(h%2==0)
						{
							colour=RamPtr[video_state.baseRamAddress+counter1];
							counter1++;
						}
						else
						{
							colour=RamPtr[video_state.baseRamAddress+counter2+0x2000];
							counter2++;
						}
						//Unwinded loop
						cga_color_reg temp;
						temp.data=video_state.color_reg.data;
						drawscreen.setPixel(w, h, (colour>>7&0b1) ? GetColorFrom3or4B(temp.backgroundColour) : cga_color_array_text_mode[0]);

						drawscreen.setPixel(w+1, h, (colour>>6&0b1) ? GetColorFrom3or4B(temp.backgroundColour) : cga_color_array_text_mode[0]);

						drawscreen.setPixel(w+2, h, (colour>>5&0b1) ? GetColorFrom3or4B(temp.backgroundColour) : cga_color_array_text_mode[0]);

						drawscreen.setPixel(w+3, h, (colour>>4&0b1) ? GetColorFrom3or4B(temp.backgroundColour) : cga_color_array_text_mode[0]);

						drawscreen.setPixel(w+4, h, (colour>>3&0b1) ? GetColorFrom3or4B(temp.backgroundColour) : cga_color_array_text_mode[0]);

						drawscreen.setPixel(w+5, h, (colour>>2&0b1) ? GetColorFrom3or4B(temp.backgroundColour) : cga_color_array_text_mode[0]);

						drawscreen.setPixel(w+6, h, (colour>>1&0b1) ? GetColorFrom3or4B(temp.backgroundColour) : cga_color_array_text_mode[0]);

						drawscreen.setPixel(w+7, h, (colour&0b1) ? GetColorFrom3or4B(temp.backgroundColour) : cga_color_array_text_mode[0]);

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
							DrawChar(drawscreen, character, w, h, cga_color_array_text_mode[15], cga_color_array_text_mode[0]);
						}
						else if(!attribute)
						{
							DrawChar(drawscreen, character, w, h, cga_color_array_text_mode[0], cga_color_array_text_mode[0]);
						}
						else
						{
							DrawChar(drawscreen, character, w, h, cga_color_array_text_mode[0], cga_color_array_text_mode[7]);
						}
					}
				}
				break;
			}
		default:
			{
				//To-do: What to do?
				writefln("Unsupported video mode: %s", video_state.vmode);
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
	*/
}

Color[][] cga_color_array_mode_4=[
[
	Color(0x00, 0x00, 0x00), //Dummy
	Color(0x00, 0xAA, 0x00),
	Color(0xAA, 0x00, 0x00),
	Color(0xAA, 0x55, 0x00),
	Color(0x00, 0x00, 0x00), //Dummy
	Color(0x00, 0xAA, 0xAA),
	Color(0xFF, 0x55, 0x55),
	Color(0xFF, 0xFF, 0x55),
],
[
	Color(0x00, 0x00, 0x00), //Dummy
	Color(0x00, 0xAA, 0xAA),
	Color(0xAA, 0x00, 0xAA),
	Color(0xAA, 0xAA, 0xAA),
	Color(0x00, 0x00, 0x00), //Dummy
	Color(0x55, 0xFF, 0xFF),
	Color(0xFF, 0x55, 0xFF),
	Color(0xFF, 0xFF, 0xFF),
]
];

Color[16] cga_color_array_text_mode=[
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
	return cga_color_array_text_mode[color&0b1111];
}

/*
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
*/
