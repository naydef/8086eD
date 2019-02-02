module x86_processor;

import x86_memory;
import core.stdc.stdint;
import core.stdc.string;
import std.stdio;
import simplelogger;
import std.format;
import std.bitmanip;
import core.bitop;
import std.conv;
import std.format;
import cpu.decl;
import ibm_pc_com;
import std.string;

immutable int max_str_lenght=30;

struct Pointer8086_32bit
{
	align(1):
	int16_t lowpart;
	int16_t highpart;
}

class ProcessorX86
{
	this(IBM_PC_COMPATIBLE param)
	{
		machine=param;
		x86log.log("Initializing CPU");
		// Memory is exclusively a CPU resource - external access via DMA
		RAM=new MemoryX86();
		
		SignalReset();
		//Everything initialised!
	}
	
	
	private uint8_t RMF(uint8_t arg)
	{
		return arg & 0x07;
	}
	
	private uint8_t REG(uint8_t arg)
	{
		return arg>>3 & 0x07;
	}
	
	private uint8_t MOD(uint8_t arg)
	{
		return arg>>6 & 0x03;
	}
	
	private uint8_t DIREC(uint8_t arg)
	{
		return arg>>1 & 0x01;
	}

	private bool iswordset(uint8_t arg)
	{
		return ((arg>>0 & 0x01) == 1);
	}
	
	private bool GETBITFLAGS(uint8_t bit)
	{
		return FLAGS.word >> bit & 0x01;
	}
	
	private bool IsSignSet(uint8_t num)
	{
		return ((num>>7 & 0x01)==1);
	}
	
	private bool IsSignSet(uint16_t num)
	{
		return ((num>>15 & 0x01)==1);
	}
	
	private uint16_t SignExtendB(uint8_t num)
	{
		uint16_t number=num;
		number|=(number&0x80) ? 0xFF00 : 0x0000;
		return number;
	}
	
	//To-do: Make compliant with D integer promotion changes
	/*
	private void SETBITFLAGS(uint8_t bit, bool val)
	{
		FLAGS.word ^= (-cast(byte)val ^ FLAGS.word) & (1UL << bit);
	}
	*/
	
	public bool Halted()
	{
		return halted;
	}
	
	final private void AdjustIP(ref reg16 IP, uint8_t modrm)
	{
		switch(MOD(modrm))
		{
		case 0x00:
			{
				switch(RMF(modrm))
				{
				case 0x06: // Direct addressing
					{
						IP.word+=2;
						break;
					}
				default: //No adjust
					{
						IP.word+=0;
						break;
					}
				}
				break;
			}
		case 0x01:
			{
				IP.word+=1;
				break;
			}
		case 0x02:
			{
				IP.word+=2;
				break;
			}
		case 0x03: // No adjust
			{
				IP.word+=0;
				break;
			}
		default:
			{
				break;
			}
		}
	}
	
	final private ref reg16 SegIndexToSegReg(uint8_t index)
	{
		switch(index)
		{
		case CS_SEGMENT:
			{
				return CS;
			}
			
		case DS_SEGMENT:
			{
				return DS;
			}
			
		case SS_SEGMENT:
			{
				return SS;
			}
			
		case ES_SEGMENT:
			{
				return ES;
			}
			
		default: // By default refer to DS register
			{
				return DS;
			}
		}
	}
	
	final string RegWordIndexToString(int reg)
	{
		switch(reg)
		{
		case REG_AX:
			{
				return "AX";
			}
		case REG_CX:
			{
				return "CX";
			}
		case REG_DX:
			{
				return "DX";
			}
		case REG_BX:
			{
				return "BX";
			}
		case REG_SP:
			{
				return "SP";
			}
		case REG_BP:
			{
				return "BP";
			}
		case REG_SI:
			{
				return "SI";
			}
		case REG_DI:
			{
				return "DI";
			}
		default:
			{
				return "UNKNOWN";
			}
		}
	}
	
	final private void push16(uint16_t val)
	{
		regs[REG_SP].word-=2;
		RAM.WriteMemory(SS.word, regs[REG_SP].word, val);
	}
	
	final private void push8(uint8_t val)
	{
		regs[REG_SP].word-=2;
		RAM.WriteMemory(SS.word, regs[REG_SP].word, cast(uint16_t)val);
	}

	final private uint16_t pop16()
	{
		uint16_t data=RAM.ReadMemory16(SS.word, regs[REG_SP].word);
		regs[REG_SP].word+=2;
		return data;
	}
	
	final private void TestCF(uint8_t byte1,uint8_t byte2)
	{
		FLAGS.CF=(cast(uint16_t)byte1+cast(uint16_t)byte2)&0x8000 ? true : false;
	}
	
	
	//Special one for asm: lea
	final private uint16_t Lea16(uint8_t modrm, uint16_t bytes2afterinstruction)
	{
		switch(MOD(modrm))
		{
		case 0x00:
		case 0x01:
		case 0x02:
			{
				int16_t addrbase=cast(short)bytes2afterinstruction; //Inspect...
				if(MOD(modrm)==0x00)
				{
					addrbase=0;
				}
				else if(MOD(modrm)==0x01)
				{
					addrbase=cast(byte)((bytes2afterinstruction) & 0xFF);
				}
				else if(MOD(modrm)==0x02)
				{
					addrbase=bytes2afterinstruction;
				}
				switch(RMF(modrm))
				{
				case 0x00:
					{
						return cast(uint16_t)(addrbase+regs[REG_BX].word+regs[REG_SI].word);
					}
				case 0x01:
					{
						return cast(uint16_t)(addrbase+regs[REG_BX].word+regs[REG_DI].word);
					}
				case 0x02:
					{
						return cast(uint16_t)(addrbase+regs[REG_BP].word+regs[REG_SI].word);
					}
				case 0x03:
					{
						return cast(uint16_t)(addrbase+regs[REG_BP].word+regs[REG_DI].word);
					}
				case 0x04:
					{
						return cast(uint16_t)(addrbase+regs[REG_SI].word);
					}
				case 0x05:
					{
						return cast(uint16_t)(addrbase+regs[REG_DI].word);
					}
				case 0x06:
					{
						return (!MOD(modrm)) ? bytes2afterinstruction : cast(ushort)(addrbase+regs[REG_BP].word);
					}
				case 0x07:
					{
						return cast(ushort)(addrbase+regs[REG_BX].word);
					}
				default:
					{
						assert(0, "How this could happen?");
					}
				}
			}
		default:
			{
				assert(0, "lea with source register not expected");
			}
		}
		assert(0, "This code can't be reached, but somehow this did happen!");
	}
	
	void AdjustSegment(ubyte modrm, ref ubyte currsegment)
	{
		switch(MOD(modrm))
		{
		case 0x00:
		case 0x01:
		case 0x02:
			{
				switch(RMF(modrm))
				{
				case 0x00:
					{
						currsegment=(currsegment==NO_SEGMENT) ? DS_SEGMENT : currsegment;
						break;
					}
				case 0x01:
					{
						currsegment=(currsegment==NO_SEGMENT) ? DS_SEGMENT : currsegment;
						break;
					}
				case 0x02:
					{
						currsegment=(currsegment==NO_SEGMENT) ? SS_SEGMENT : currsegment;
						break;
					}
				case 0x03:
					{
						currsegment=(currsegment==NO_SEGMENT) ? SS_SEGMENT : currsegment;
						break;
					}
				case 0x04:
					{
						currsegment=(currsegment==NO_SEGMENT) ? DS_SEGMENT : currsegment;
						break;
					}
				case 0x05:
					{
						currsegment=(currsegment==NO_SEGMENT) ? DS_SEGMENT : currsegment;
						break;
					}
				case 0x06:
					{
						currsegment=(currsegment==NO_SEGMENT) ? DS_SEGMENT : currsegment;
						break;
					}
				case 0x07:
					{
						currsegment=(currsegment==NO_SEGMENT) ? DS_SEGMENT : currsegment;
						break;
					}
				default:
					{
						assert(0, "How this could happen?");
					}
				}
				break;
			}
		default:
			{
				assert(0, "lea with source register not expected");
			}
		}
		assert(0, "This code can't be reached, but somehow this did happen!");
	}
	
	//Note: oper1 is ALWAYS the DESTINATION, oper2 is ALWAYS the SOURCE! Pass address of the pointers!
	final private void SetupOperands(uint8_t modrm, uint8_t opcode, uint16_t bytes2afterinstruction, void** oper1, void** oper2, uint8_t seg=DS_SEGMENT)
	{
		switch(MOD(modrm))
		{
		case 0x00:
		case 0x01:
		case 0x02:
			{
				int16_t addrbase=cast(short)bytes2afterinstruction; //Inspect...
				if(MOD(modrm)==0x00)
				{
					addrbase=0;
				}
				else if(MOD(modrm)==0x01)
				{
					addrbase=cast(byte)((bytes2afterinstruction) & 0xFF);
				}
				else if(MOD(modrm)==0x02)
				{
					addrbase=bytes2afterinstruction;
				}
				//No displacement
				if(!DIREC(opcode))
				{
					if(!iswordset(opcode)) //8-bit
					{
						*oper2=&regs[(REG(modrm)>3) ? REG(modrm)-0x4 : REG(modrm)].hfword[(REG(modrm)<4) ? l : h];
					}
					else //16-bit
					{
						*oper2=&regs[REG(modrm)];
					}
					switch(RMF(modrm))
					{
					case 0x00:
						{
							*oper1=RAM.GetAbsAddress16((seg==NO_SEGMENT) ? DS.word : SegIndexToSegReg(seg).word, cast(ushort)(addrbase+regs[REG_BX].word+regs[REG_SI].word));
							break;
						}
					case 0x01:
						{
							*oper1=RAM.GetAbsAddress16((seg==NO_SEGMENT) ? DS.word : SegIndexToSegReg(seg).word, cast(ushort)(addrbase+regs[REG_BX].word+regs[REG_DI].word));
							break;
						}
					case 0x02: // Use SS segment register, because BP register is used!
						{
							*oper1=RAM.GetAbsAddress16((seg==NO_SEGMENT) ? SS.word : SegIndexToSegReg(seg).word, cast(ushort)(addrbase+regs[REG_BP].word+regs[REG_SI].word));
							break;
						}
					case 0x03: // Use SS segment register, because BP register is used!
						{
							*oper1=RAM.GetAbsAddress16((seg==NO_SEGMENT) ? SS.word : SegIndexToSegReg(seg).word, cast(ushort)(addrbase+regs[REG_BP].word+regs[REG_DI].word));
							break;
						}
					case 0x04:
						{
							*oper1=RAM.GetAbsAddress16((seg==NO_SEGMENT) ? DS.word : SegIndexToSegReg(seg).word, cast(ushort)(addrbase+regs[REG_SI].word));
							break;
						}
					case 0x05:
						{
							*oper1=RAM.GetAbsAddress16((seg==NO_SEGMENT) ? DS.word : SegIndexToSegReg(seg).word, cast(ushort)(addrbase+regs[REG_DI].word));
							break;
						}
					case 0x06:
						{
							*oper1=(!MOD(modrm)) ? RAM.GetAbsAddress16((seg==NO_SEGMENT) ? DS.word : SegIndexToSegReg(seg).word, bytes2afterinstruction) : RAM.GetAbsAddress16((seg==NO_SEGMENT) ? SS.word : SegIndexToSegReg(seg).word, cast(ushort)(addrbase+regs[REG_BP].word));
							break;
						}
					case 0x07:
						{
							*oper1=RAM.GetAbsAddress16((seg==NO_SEGMENT) ? DS.word : SegIndexToSegReg(seg).word, cast(ushort)(addrbase+regs[REG_BX].word));
							break;
						}
					default:
						{
							*oper1=null; //What to do?
							break;
						}
					}
				}
				else
				{
					if(!iswordset(opcode)) //8-bit
					{
						*oper1=&regs[(REG(modrm)>3) ? REG(modrm)-0x4 : REG(modrm)].hfword[(REG(modrm)<4) ? l : h];
					}
					else //16-bit
					{
						*oper1=&regs[REG(modrm)];
					}
					switch(RMF(modrm))
					{
					case 0x00:
						{
							*oper2=RAM.GetAbsAddress16((seg==NO_SEGMENT) ? DS.word : SegIndexToSegReg(seg).word, cast(ushort)(addrbase+regs[REG_BX].word+regs[REG_SI].word));
							break;
						}
					case 0x01:
						{
							*oper2=RAM.GetAbsAddress16((seg==NO_SEGMENT) ? DS.word : SegIndexToSegReg(seg).word, cast(ushort)(addrbase+regs[REG_BX].word+regs[REG_DI].word));
							break;
						}
					case 0x02: // Use SS segment register, because EBP register is used!
						{
							*oper2=RAM.GetAbsAddress16((seg==NO_SEGMENT) ? SS.word : SegIndexToSegReg(seg).word, cast(ushort)(addrbase+regs[REG_BP].word+regs[REG_SI].word));
							break;
						}
					case 0x03: // Use SS segment register, because EBP register is used!
						{
							*oper2=RAM.GetAbsAddress16((seg==NO_SEGMENT) ? SS.word : SegIndexToSegReg(seg).word, cast(ushort)(addrbase+regs[REG_BP].word+regs[REG_DI].word));
							break;
						}
					case 0x04:
						{
							*oper2=RAM.GetAbsAddress16((seg==NO_SEGMENT) ? DS.word : SegIndexToSegReg(seg).word, cast(ushort)(addrbase+regs[REG_SI].word));
							break;
						}
					case 0x05:
						{
							*oper2=RAM.GetAbsAddress16((seg==NO_SEGMENT) ? DS.word : SegIndexToSegReg(seg).word, cast(ushort)(addrbase+regs[REG_DI].word));
							break;
						}
					case 0x06:
						{
							*oper2= (!MOD(modrm)) ? RAM.GetAbsAddress16((seg==NO_SEGMENT) ? DS.word : SegIndexToSegReg(seg).word, bytes2afterinstruction) : RAM.GetAbsAddress16((seg==NO_SEGMENT) ? SS.word : SegIndexToSegReg(seg).word, cast(ushort)(addrbase+regs[REG_BP].word));
							break;
						}
					case 0x07:
						{
							*oper2=RAM.GetAbsAddress16(SegIndexToSegReg(seg).word, cast(ushort)(addrbase+regs[REG_BX].word));
							break;
						}
					default:
						{
							*oper2=null; //What to do?
							break;
						}
					}
				}
				break;
			}
		case 0x03:
			{
				//register operands
				if(!DIREC(opcode)) //
				{
					if(!iswordset(opcode)) //8-bit
					{
						*oper2=&regs[(REG(modrm)>3) ? REG(modrm)-0x4 : REG(modrm)].hfword[(REG(modrm)<4) ? l : h];
						*oper1=&regs[(RMF(modrm)>3) ? RMF(modrm)-0x4 : RMF(modrm)].hfword[(RMF(modrm)<4) ? l : h];
					}
					else //16-bit
					{
						*oper2=&regs[REG(modrm)];
						*oper1=&regs[RMF(modrm)];
					}
				}
				else
				{
					if(!iswordset(opcode)) //8-bit
					{
						*oper1=&regs[(REG(modrm)>3) ? REG(modrm)-0x4 : REG(modrm)].hfword[(REG(modrm)<4) ? l : h];
						*oper2=&regs[(RMF(modrm)>3) ? RMF(modrm)-0x4 : RMF(modrm)].hfword[(RMF(modrm)<4) ? l : h];
					}
					else //16-bit
					{
						*oper1=&regs[REG(modrm)];
						*oper2=&regs[RMF(modrm)];
					} 
				}
				break;
			}
		default:
			{
				// How this could happen?
				*oper1=null;
				*oper2=null;
				break;
			}
		}
	}
	
	final public void ExecuteInstruction()
	{
		uint8_t prefix=CodeFetchB(0);
		uint8_t currsegment=NO_SEGMENT;
		ubyte rep=REP_PREFIX_NONE;
		ubyte prefixescount=0;
		prevCS=GetCS();
		prevIP=GetIP();
		while(prefix==0x26 || prefix==0x36 || prefix==0x2E || prefix==0x3E || prefix==0xF0 || prefix==0xF2 || prefix==0xF3)
		{
			IP.word+=1;
			prefixescount++;
			switch(prefix)
			{
				//asm: ES:
			case 0x26:
				{
					currsegment=ES_SEGMENT;
					break;
				}
				
				//asm: SS:
			case 0x36:
				{
					currsegment=SS_SEGMENT;
					break;
				}
				
				//asm: CS:
			case 0x2E:
				{
					currsegment=CS_SEGMENT;
					break;
				}
				
				//asm: DS:
			case 0x3E:
				{
					currsegment=DS_SEGMENT;
					break;
				}
				
				//asm: LOCK:
			case 0xF0:
				{
					break;
				}
				
				//asm: REPNE:
			case 0xF2:
				{
					rep=REP_PREFIX_REPN;
					break;
				}
				
				//asm: REP/REPE:
			case 0xF3:
				{
					rep=REP_PREFIX_REP;
					break;
				}
				
			default:
				{
					currsegment=NO_SEGMENT;
				}
			}
			prefix=CodeFetchB(0);
		}

		uint8_t opcode=CodeFetchB(0);
		uint8_t modrm=CodeFetchB(1);
		
		if(isexecbreakpointactive)
		{
			if(CS.word==BP_CS && IP.word==BP_IP)
			{
				machine.CommandWindow("execution breakpoint");
				isexecbreakpointactive=false;
			}
		}
		
		INSTR_NAME("<unknown>");
		switch(opcode)
		{
			//asm: add <b>
		case 0x00:
		case 0x02:
			{
				//Instruction name
				INSTR_NAME("add r/m8, r8");
				
				//Retrieve operands
				uint8_t *dest;
				uint8_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);
				
				//The actual operation
				CheckAdd8(*dest, *source);
				*dest+=*source;
				
				//Set flags accordingly
				TestVal(*dest);
				
				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				break;
			}
			
			//asm: add <w>
		case 0x01:
		case 0x03:
			{
				//Instruction name
				INSTR_NAME("add r/m16, r16");
				
				//Retrieve operands
				uint16_t *dest;
				uint16_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);
				
				//The actual operation
				CheckAdd16(*dest, *source);
				*dest+=*source;
				
				//Set flags accordingly
				TestVal(*dest);
				
				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				break;
			}
			
			//asm: add al, imm8
		case 0x04:
			{
				//Instruction name
				uint8_t imm8=CodeFetchB(1);
				INSTR_NAME("add al, imm8");
				
				//The actual operation
				CheckAdd8(regs[REG_AX].hfword[l], imm8);
				regs[REG_AX].hfword[l]+=imm8;
				
				//Set flags accordingly
				TestVal(regs[REG_AX].hfword[l]);
				
				IP.word+=2;
				break;
			}
			
			//asm: add ax, imm16
		case 0x05:
			{
				//Instruction name
				INSTR_NAME("add ax, imm16");
				
				uint16_t imm16=CodeFetchW(1);
				
				//The actual operation
				CheckAdd16(regs[REG_AX].word, imm16);
				regs[REG_AX].word+=imm16;
				
				//Set flags accordingly
				TestVal(regs[REG_AX].word);
				
				IP.word+=3;
				break;
			}
			
			//asm: push es
		case 0x06:
			{
				//Instruction name
				INSTR_NAME("push es");
				
				//The actual operation
				push16(ES.word);
				
				//Move past the current instruction and set IP register to next instruction
				IP.word+=1;
				break;
			}
			
			//asm: pop es
		case 0x07:
			{
				//Instruction name
				INSTR_NAME("pop es");
				
				//The actual operation
				ES.word=pop16();
				
				//Move past the current instruction and set IP register to next instruction
				IP.word+=1;
				break;
			}
			
			//asm: or <b>
		case 0x08:
		case 0x0A:
			{
				//Instruction name
				INSTR_NAME("or r8, r/m8");
				
				//Retrieve operands
				uint8_t *dest;
				uint8_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);
				
				//The actual operation
				*dest|=*source;
				
				//Set flags accordingly
				TestVal(*dest);
				FLAGS.OF=false;
				FLAGS.CF=false;
				
				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				break;
			}
			
			//asm: or <w>
		case 0x09:
		case 0x0B:
			{
				//Instruction name
				INSTR_NAME("or r16, r/m16");
				
				//Retrieve operands
				uint16_t *dest;
				uint16_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);
				
				//The actual operation
				*dest|=*source;
				
				//Set flags accordingly
				TestVal(*dest);
				FLAGS.OF=false;
				FLAGS.CF=false;
				
				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				break;
			}
			
			//asm: or al, imm8
		case 0x0C:
			{
				//Instruction name
				INSTR_NAME("or al, imm8");
				
				uint8_t imm8=CodeFetchB(1);
				regs[REG_AX].hfword[l]|=imm8;
				
				//Set flags accordingly
				TestVal(regs[REG_AX].hfword[l]);
				FLAGS.OF=false;
				FLAGS.CF=false;
				
				IP.word+=2;
				break;
			}
			
			//asm: or ax, imm16
		case 0x0D:
			{
				//Instruction name
				INSTR_NAME("or ax, imm16");
				
				uint16_t imm16=CodeFetchW(1);
				regs[REG_AX].word|=imm16;
				
				//Set flags accordingly
				TestVal(regs[REG_AX].word);
				FLAGS.OF=false;
				FLAGS.CF=false;
				
				IP.word+=3; // Probably. Better check!
				break;
			}
			
			//asm: push cs
		case 0x0E:
			{
				//Instruction name
				INSTR_NAME("push cs");
				
				push16(CS.word);
				IP.word+=1;
				break;
			}
			
			version(PROC_8086)
			{
				//asm: pop cs
			case 0x0F:
				{
					//Instruction name
					INSTR_NAME("pop cs");
					
					CS.word=pop16();
					IP.word+=1;
					break;
				}
			}
			
			//asm: adc <b>
		case 0x10:
		case 0x12:
			{
				//Instruction name
				INSTR_NAME("adc r8, r/m8");
				
				//Retrieve operands
				uint8_t *dest;
				uint8_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);
				
				//The actual operation
				bool tempCF=FLAGS.CF;
				CheckAdd8(*dest, *source, FLAGS.CF);
				*dest+=*source+tempCF;
				
				//Set flags accordingly
				TestVal(*dest);
				
				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				break;
			}
			
			//asm: adc <w>
		case 0x11:
		case 0x13:
			{
				//Instruction name
				INSTR_NAME("adc r16, r/m16");
				
				//Retrieve operands
				uint16_t *dest;
				uint16_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);
				
				//The actual operation
				bool tempCF=FLAGS.CF;
				CheckAdd16(*dest, *source, FLAGS.CF);
				*dest+=*source+tempCF;
				
				//Set flags accordingly
				TestVal(*dest);
				
				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				break;
			}
			
			//asm: adc al, imm8
		case 0x14:
			{
				//Instruction name
				INSTR_NAME("adc al, imm8");
				
				uint8_t imm8=CodeFetchB(1);
				
				bool tempCF=FLAGS.CF;
				CheckAdd8(regs[REG_AX].hfword[l], imm8, FLAGS.CF);
				regs[REG_AX].hfword[l]+=imm8+tempCF;
				
				TestVal(regs[REG_AX].hfword[l]);
				
				IP.word+=2;
				break;
			}
			
			//asm: adc ax, imm16
		case 0x15:
			{
				//Instruction name
				INSTR_NAME("adc ax, imm16");
				
				uint16_t imm16=CodeFetchW(1);
				
				bool tempCF=FLAGS.CF;
				CheckAdd16(regs[REG_AX].word, imm16, FLAGS.CF);
				regs[REG_AX].word+=imm16+tempCF;
				
				TestVal(regs[REG_AX].word);
				
				IP.word+=3;
				break;
			}
			
			//asm: push ss
		case 0x16:
			{
				//Instruction name
				INSTR_NAME("push ss");
				
				push16(SS.word);
				IP.word+=1;
				break;
			}

			//asm: pop ss
		case 0x17:
			{
				//Instruction name
				INSTR_NAME("pop ss");
				
				SS.word=pop16();
				IP.word+=1;
				break;
			}
			
			//asm: sbb <b>
		case 0x18:
		case 0x1A:
			{
				//Instruction name
				INSTR_NAME("sbb r8, r/m8");
				
				//Retrieve operands
				uint8_t *dest;
				uint8_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);
				
				//The actual operation
				bool tempCF=FLAGS.CF;
				CheckSub8(*dest, *source, FLAGS.CF);
				*dest-=*source+tempCF;
				
				//Set flags accordingly
				TestVal(*dest);
				
				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				break;
			}
			//asm: sbb <w>
		case 0x19:
		case 0x1B:
			{
				//Instruction name
				INSTR_NAME("sbb r16, r/m16");
				
				//Retrieve operands
				uint16_t *dest;
				uint16_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);
				
				//The actual operation
				bool tempCF=FLAGS.CF;
				CheckSub16(*dest, *source, FLAGS.CF);
				*dest-=*source+tempCF;
				
				//Set flags accordingly
				TestVal(*dest);
				
				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				break;
			}
			
			//asm: sbb al, imm8
		case 0x1C:
			{
				//Instruction name
				INSTR_NAME("sbb al, imm8");
				
				uint8_t imm8=CodeFetchB(1);
				
				bool tempCF=FLAGS.CF;
				CheckSub8(regs[REG_AX].hfword[l], imm8, FLAGS.CF);
				regs[REG_AX].hfword[l]-=imm8+tempCF;
				
				TestVal(regs[REG_AX].hfword[l]);
				
				IP.word+=2;
				break;
			}
			
			//asm: sbb ax, imm16
		case 0x1D:
			{
				//Instruction name
				INSTR_NAME("sbb ax, imm16");
				
				uint16_t imm16=CodeFetchW(1);
				
				bool tempCF=FLAGS.CF;
				CheckSub16(regs[REG_AX].word, imm16, FLAGS.CF);
				regs[REG_AX].word-=imm16+tempCF;
				
				TestVal(regs[REG_AX].word);
				
				IP.word+=3;
				break;
			}
			
			//asm: push ds
		case 0x1E:
			{
				//Instruction name
				INSTR_NAME("push ds");
				
				push16(DS.word);
				IP.word+=1;
				break;
			}
			
			//asm: pop ds
		case 0x1F:
			{
				//Instruction name
				INSTR_NAME("pop ds");
				
				DS.word=pop16();
				IP.word+=1;
				break;
			}
			
			//asm: and <b>
		case 0x20:
		case 0x22:
			{
				//Instruction name
				INSTR_NAME("and r8, r/m8");
				
				//Retrieve operands
				uint8_t *dest;
				uint8_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);

				//The actual operation
				*dest&=*source;

				//Set flags accordingly
				TestVal(*dest);
				FLAGS.OF=false;
				FLAGS.CF=false;

				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				break;
			}
			
			//asm: and <w>
		case 0x21:
		case 0x23:
			{
				//Instruction name
				INSTR_NAME("and r16, r/m16");
				
				//Retrieve operands
				uint16_t *dest;
				uint16_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);

				//The actual operation
				*dest&=*source;

				//Set flags accordingly
				TestVal(*dest);
				FLAGS.OF=false;
				FLAGS.CF=false;

				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				break;
			}
			
			//asm: and al, imm8
		case 0x24:
			{
				//Instruction name
				INSTR_NAME("and al, imm8");
				
				uint8_t imm8=CodeFetchB(1);
				regs[REG_AX].hfword[l]&=imm8;
				
				TestVal(regs[REG_AX].hfword[l]);
				FLAGS.OF=false;
				FLAGS.CF=false;
				
				IP.word+=2;
				break;
			}
			
			//asm: and ax, imm16
		case 0x25:
			{
				//Instruction name
				INSTR_NAME("and ax, imm16");
				
				uint16_t imm16=CodeFetchW(1);
				regs[REG_AX].word&=imm16;
				
				TestVal(regs[REG_AX].word);
				FLAGS.OF=false;
				FLAGS.CF=false;
				
				IP.word+=3;
				break;
			}
			
			//asm: ES:
			//case 0x26:	
			
			//asm: daa
		case 0x27:
			{
				//Instruction name
				INSTR_NAME("daa");
				
				ubyte oldal=regs[REG_AX].hfword[l];
				bool oldCF=FLAGS.CF;
				FLAGS.CF=false;
				if((regs[REG_AX].hfword[l] & 0xF) > 9 || FLAGS.AF)
				{
					ushort temp=oldal+0x06;
					oldal+=0x6;
					regs[REG_AX].hfword[l]=oldal;
					FLAGS.CF=cast(bool)(oldCF || (temp&0x100)==0x100);
					FLAGS.AF=true;
				}
				else
				{
					FLAGS.AF=false;
				}

				if(oldal > 0x99 || oldCF)
				{
					regs[REG_AX].hfword[l]+=0x60;
					FLAGS.CF=true;
				}
				else
				{
					FLAGS.CF=false;
				}

				TestVal(regs[REG_AX].hfword[l]);
				IP.word+=1;
				break;
			}
			
			//asm: sub <b>
		case 0x28:
		case 0x2A:
			{
				//Instruction name
				INSTR_NAME("sub r8, r/m8");
				
				//Retrieve operands
				uint8_t *dest;
				uint8_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);
				
				//The actual operation
				CheckSub8(*dest, *source);
				*dest-=*source;
				
				//Set flags accordingly
				TestVal(*dest);
				
				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				break;
			}
			
			//asm: sub <w>
		case 0x29:
		case 0x2B:
			{
				//Instruction name
				INSTR_NAME("sub r16, r/m16");
				
				//Retrieve operands
				uint16_t *dest;
				uint16_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);

				//The actual operation
				CheckSub16(*dest, *source);
				*dest-=*source;

				//Set flags accordingly
				TestVal(*dest);

				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				break;
			}
			
			//asm: sub al, imm8
		case 0x2C:
			{
				//Instruction name
				INSTR_NAME("sub al, imm8");
				
				uint8_t imm8=CodeFetchB(1);
				
				CheckSub8(regs[REG_AX].hfword[l], imm8);
				regs[REG_AX].hfword[l]-=imm8;
				
				TestVal(regs[REG_AX].hfword[l]);
				
				IP.word+=2;
				break;
			}
			
			//asm: sub ax, imm16
		case 0x2D:
			{
				//Instruction name
				INSTR_NAME("sub ax, imm16");
				
				uint16_t imm16=CodeFetchW(1);
				
				CheckSub16(regs[REG_AX].word, imm16);
				regs[REG_AX].word-=imm16;
				
				TestVal(regs[REG_AX].word);
				
				IP.word+=3;
				break;
			}
			
			//asm: CS:
			//case 0x2E:
			
			//asm: das
		case 0x2F:
			{
				//Instruction name
				INSTR_NAME("das");
				
				uint8_t oldAL=regs[REG_AX].hfword[l];
				bool oldCF=FLAGS.CF;
				
				FLAGS.CF=false;
				
				if((oldAL & 0xF) > 9 || FLAGS.AF)
				{
					ushort result=cast(ushort)(regs[REG_AX].hfword[l]-6);
					bool borrow=(result&0xFF00) ? true : false;
					
					FLAGS.CF=borrow;
					regs[REG_AX].hfword[l]-=6;
					

					x86log.log("DAS instruction executed with incomplete implementation!");
				}
				else
				{
					FLAGS.AF=false;
				}
				
				if(oldAL > 0x99 || oldCF)
				{
					regs[REG_AX].hfword[l]-=0x60;
					FLAGS.CF=true;
				}
				else
				{
					FLAGS.CF=false;
				}
				
				IP.word+=1;
				break;
			}
			
			//asm: xor <b>
		case 0x30:
		case 0x32:
			{
				//Instruction name
				INSTR_NAME("xor r8, r/m8");
				
				//Retrieve operands
				uint8_t *dest;
				uint8_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);

				//The actual operation
				*dest^=*source;

				//Set flags accordingly
				TestVal(*dest);
				FLAGS.OF=false;
				FLAGS.CF=false;

				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				break;
			}

			//asm: xor <w>
		case 0x31:
		case 0x33:
			{
				//Instruction name
				INSTR_NAME("xor r16, r/m16");
				
				//Retrieve operands
				uint16_t *dest;
				uint16_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);

				//The actual operation
				*dest^=*source;

				//Set flags accordingly
				TestVal(*dest);
				FLAGS.OF=false;
				FLAGS.CF=false;

				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				break;
			}
			
			//asm: xor al, lb
		case 0x34:
			{
				//Instruction name
				INSTR_NAME("xor al, imm8");
				
				regs[REG_AX].hfword[l]^=CodeFetchB(1);
				TestVal(regs[REG_AX].hfword[l]);
				FLAGS.CF=false;
				FLAGS.OF=false;
				IP.word+=2;
				break;
			}
			
			//asm: xor ax, lv
		case 0x35:
			{
				//Instruction name
				INSTR_NAME("xor ax, imm16");
				
				regs[REG_AX].word^=CodeFetchW(1);
				TestVal(regs[REG_AX].word);
				FLAGS.CF=false;
				FLAGS.OF=false;
				IP.word+=3;
				break;
			}
			
			//asm: SS:
			//case 0x36:
			
			//asm: aaa
		case 0x37:
			{
				//Instruction name
				INSTR_NAME("aaa");
				
				if((regs[REG_AX].hfword[l] & 0xF)>9 || FLAGS.AF)
				{
					regs[REG_AX].hfword[l]+=6;
					regs[REG_AX].hfword[h]+=1;
					FLAGS.AF=true;
					FLAGS.CF=true;
				}
				else
				{
					FLAGS.AF=false;
					FLAGS.CF=false;
				}
				regs[REG_AX].hfword[l]&=0xF;
				IP.word+=1;
				break;
			}
			
			//asm: cmp <b>
		case 0x38:
		case 0x3A:
			{
				//Instruction name
				INSTR_NAME("cmp r8, r/m8");
				
				//Retrieve operands
				uint8_t *dest;
				uint8_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);
				
				//Set flags accordingly
				TestVal(cast(uint8_t)(*dest-*source));
				CheckSub8(*dest, *source);

				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				break;
			}

			//asm: cmp <w>
		case 0x39:
		case 0x3B:
			{
				//Instruction name
				INSTR_NAME("cmp r16, r/m16");
				
				//Retrieve operands
				uint16_t *dest;
				uint16_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);

				//Set flags accordingly
				TestVal(cast(uint16_t)(*dest-*source));
				CheckSub16(*dest, *source);

				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				break;
			}
			
			//asm: cmp al, imm8
		case 0x3C:
			{
				//Instruction name
				INSTR_NAME("cmp al, imm8");
				
				uint8_t imm8=CodeFetchB(1);
				uint8_t temp=cast(uint8_t)(regs[REG_AX].hfword[l]-imm8);
				
				TestVal(temp);
				CheckSub8(regs[REG_AX].hfword[l], imm8);
				
				IP.word+=2;
				break;
			}
			
			//asm: cmp ax, imm16
		case 0x3D:
			{
				//Instruction name
				INSTR_NAME("cmp ax, imm16");
				
				uint16_t imm16=CodeFetchW(1);
				
				TestVal(cast(uint16_t)(regs[REG_AX].word-imm16));
				CheckSub16(regs[REG_AX].word, imm16);
				
				IP.word+=3;
				break;
			}
			//asm: DS:
			//case 0x3E:
			
			//asm: aas
		case 0x3F:
			{
				//Instruction name
				INSTR_NAME("aas");
				
				if(((regs[REG_AX].hfword[l] & 0xF) > 9) || FLAGS.AF)
				{
					regs[REG_AX].hfword[l]-=6;
					regs[REG_AX].hfword[h]-=1;
					FLAGS.AF=true;
					FLAGS.CF=true;
				}
				else
				{
					FLAGS.AF=false;
					FLAGS.CF=false;
				}
				regs[REG_AX].hfword[l]&=0xF;
				IP.word+=1;
				break;
			}

			//asm: inc reg16
		case 0x40:
		case 0x41:
		case 0x42:
		case 0x43:
		case 0x44:
		case 0x45:
		case 0x46:
		case 0x47:
			{
				//Instruction name
				INSTR_NAME("inc " ~ RegWordIndexToString(opcode-0x40));
				
				bool flagCF=FLAGS.CF;
				CheckAdd16(regs[RMF(opcode)].word, 1);
				regs[RMF(opcode)].word+=1;
				TestVal(regs[RMF(opcode)].word);
				FLAGS.CF=flagCF;
				
				IP.word+=1;
				break;
			}
			
			//asm: dec reg16
		case 0x48:
		case 0x49:
		case 0x4A:
		case 0x4B:
		case 0x4C:
		case 0x4D:
		case 0x4E:
		case 0x4F:
			{
				//Instruction name
				INSTR_NAME("dec " ~ RegWordIndexToString(opcode-0x48));
				
				bool flagCF=FLAGS.CF;
				CheckSub16(regs[RMF(opcode)].word, 1);
				regs[RMF(opcode)].word-=1;
				TestVal(regs[RMF(opcode)].word);
				FLAGS.CF=flagCF;
				
				IP.word+=1;
				break;
			}
			
			//asm: push reg16
		case 0x50:
		case 0x51:
		case 0x52:
		case 0x53:
		case 0x54:
		case 0x55:
		case 0x56:
		case 0x57:
			{
				//Instruction name
				INSTR_NAME("push " ~ RegWordIndexToString((opcode-0x50)));
				
				push16(regs[RMF(opcode)].word);
				IP.word+=1;
				break;
			}
			
			//asm: pop reg16
		case 0x58:
		case 0x59:
		case 0x5A:
		case 0x5B:
		case 0x5C:
		case 0x5D:
		case 0x5E:
		case 0x5F:
			{
				//Instruction name
				INSTR_NAME("pop " ~ RegWordIndexToString(opcode-0x58));
				
				regs[RMF(opcode)].word=pop16();
				IP.word+=1;
				break;
			}
			
			//asm: pusha
		case 0x60:
			{
				//Instruction name
				INSTR_NAME("pusha");
				
				uint16_t esptemp=regs[REG_SP].word;
				push16(regs[REG_AX].word);
				push16(regs[REG_CX].word);
				push16(regs[REG_DX].word);
				push16(regs[REG_BX].word);
				push16(esptemp);
				push16(regs[REG_BP].word);
				push16(regs[REG_SI].word);
				push16(regs[REG_DI].word);
				IP.word+=1;
				break;
			}
			
			//asm: popa
		case 0x61:
			{
				//Instruction name
				INSTR_NAME("popa");
				
				regs[REG_DI].word=pop16();
				regs[REG_SI].word=pop16();
				regs[REG_BP].word=pop16();
				regs[REG_SP].word+=2;
				regs[REG_BX].word=pop16();
				regs[REG_DX].word=pop16();
				regs[REG_CX].word=pop16();
				regs[REG_AX].word=pop16();
				IP.word+=1;
				break;
			}
			
			//asm: bound
		case 0x62:
			{
				//Instruction name
				INSTR_NAME("bound");
				
				struct BoundArrayLimits
				{
					align(1):
					int16_t lowlimit;
					int16_t highlimit;
				}
				
				if(currsegment==NO_SEGMENT)
				{
					currsegment=DS_SEGMENT;
				}
				
				//Manually get register
				uint16_t* index=&regs[REG(modrm)].word;
				
				//Do the operation - todo: test
				BoundArrayLimits* arraylimit=cast(BoundArrayLimits*)(RAM.GetAbsAddress16(SegIndexToSegReg(currsegment).word, Lea16(modrm & 0xFFFE, CodeFetchW(2))));
				
				if(*index<arraylimit.lowlimit || *index>arraylimit.highlimit)
				{
					RaiseInt(EXCEPTION_BOUNDRAGEEXCEEEDED);
				}
				else
				{
					IP.word+=2;
					AdjustIP(IP, modrm);
				}
				break;
			}
			
			
			/*
				opcode 0x64-0x67 not supported by i80186
			*/
			
			//asm: push imm16
		case 0x68:
			{
				//Instruction name
				INSTR_NAME("push imm16");
				
				push16(RAM.ReadMemory16(CS.word, cast(ushort)(IP.word+1)));
				IP.word+=3;
				break;
			}
			
			//asm: imul
			//UNIMPLEMETED
	//	case 0x69:
			//{
				//Instruction name
			//	INSTR_NAME("imul");
				
			//	x86log.log("opcode 0x69: imul UNIMPLEMETED");
			//	break;
			//}
			
			//asm: push imm8
		case 0x6A:
			{
				//Instruction name
				INSTR_NAME("push imm8");
				
				push8(RAM.ReadMemory8(CS.word, cast(ushort)(IP.word+1)));
				IP.word+=2;
				break;
			}
			
			//asm: imul 
			//UNIMPLEMETED
		//case 0x6B:
		//	{
				//Instruction name
		//		INSTR_NAME("imul");
		//		
		//		x86log.log("opcode 0x6B: imul UNIMPLEMETED");
		//		break;
		//	}
			
			//asm: insb
		case 0x6C:
			{
				//Instruction name
				INSTR_NAME("insb");
				
				
				if(rep!=2) // We have REP prefix!
				{
					IP.word+=1;
				}
				else
				{
					if(!regs[REG_CX].word)
					{
						break;
					}
					regs[REG_CX].word-=1;
				}

				RAM.WriteMemory(ES.word, regs[REG_DI].word, InPort(regs[REG_DX].word) & 0x00FF);
				
				if(!GETBITFLAGS(DF))
				{
					regs[REG_DI].word+=1;
				}
				else
				{
					regs[REG_DI].word-=1;
				}
				
				IP.word+=1;
				break;
			}
			
			//asm: insw
		case 0x6D:
			{
				//Instruction name
				INSTR_NAME("insw");
				
				if(rep!=2) // We have REP prefix!
				{
					IP.word+=1;
				}
				else
				{
					if(!regs[REG_CX].word)
					{
						break;
					}
					regs[REG_CX].word-=1;
				}

				RAM.WriteMemory(ES.word, regs[REG_DI].word, InPort(regs[REG_DX].word));
				
				if(!GETBITFLAGS(DF))
				{
					regs[REG_DI].word+=2;
				}
				else
				{
					regs[REG_DI].word-=2;
				}
				
				IP.word+=1;
				break;
			}
			
			//asm: outsb
		case 0x6E:
			{
				//Instruction name
				INSTR_NAME("outsw");
				
				if(rep!=2) // We have REP prefix!
				{
					IP.word+=1;
				}
				else
				{
					if(!regs[REG_CX].word)
					{
						break;
					}
					regs[REG_CX].word-=1;
				}
				
				OutPort(regs[REG_DX].word, RAM.ReadMemory8(ES.word, regs[REG_DI].word) & 0x00FF);
				
				if(!GETBITFLAGS(DF))
				{
					regs[REG_DI].word+=1;
				}
				else
				{
					regs[REG_DI].word-=1;
				}
				
				IP.word+=1;
				break;
			}
			
			//asm: outsw
		case 0x6F:
			{
				//Instruction name
				INSTR_NAME("outsw");
				
				if(rep!=2) // We have REP prefix!
				{
					IP.word+=1;
				}
				else
				{
					if(!regs[REG_CX].word)
					{
						break;
					}
					regs[REG_CX].word-=1;
				}
				
				OutPort(regs[REG_DX].word, RAM.ReadMemory8(ES.word, regs[REG_DI].word));
				
				if(!GETBITFLAGS(DF))
				{
					regs[REG_DI].word+=1;
				}
				else
				{
					regs[REG_DI].word-=1;
				}
				
				IP.word+=1;
				break;
			}
			
			//asm: jo rel8
		case 0x70:
			{
				//Instruction name
				INSTR_NAME("jo rel8");
				
				if(FLAGS.OF)
				{
					IP.word+=cast(byte)CodeFetchB(1)+2;
				}
				else
				{
					IP.word+=2;
				}
				break;
			}
			
			//asm: jno rel8
		case 0x71:
			{
				//Instruction name
				INSTR_NAME("jno rel8");
				
				if(!FLAGS.OF)
				{
					IP.word+=cast(byte)CodeFetchB(1)+2;
				}
				else
				{
					IP.word+=2;
				}
				break;
			}
			
			//asm: jb/jnae/jc rel8
		case 0x72:
			{
				//Instruction name
				INSTR_NAME("jb/jnae/jc rel8");
				
				if(FLAGS.CF)
				{
					IP.word+=cast(byte)CodeFetchB(1)+2;
				}
				else
				{
					IP.word+=2;
				}
				break;
			}
			
			//asm: jnb/jae/jnc rel8
		case 0x73:
			{
				//Instruction name
				INSTR_NAME("jnb/jae/jnc rel8");
				
				if(!FLAGS.CF)
				{
					IP.word+=cast(byte)CodeFetchB(1)+2;
				}
				else
				{
					IP.word+=2;
				}
				break;
			}
			
			//asm: je/jz rel8
		case 0x74:
			{
				//Instruction name
				INSTR_NAME("je/jz rel8");
				
				if(FLAGS.ZF)
				{
					IP.word+=cast(byte)CodeFetchB(1)+2;
				}
				else
				{
					IP.word+=2;
				}
				break;
			}
			
			//asm: jne/jnz rel8
		case 0x75:
			{
				//Instruction name
				INSTR_NAME("jne/jnz rel8");
				
				if(!FLAGS.ZF)
				{
					IP.word+=cast(byte)CodeFetchB(1)+2;
				}
				else
				{
					IP.word+=2;
				}
				break;
			}
			
			//asm: jbe/jna rel8
		case 0x76:
			{
				//Instruction name
				INSTR_NAME("jbe/jna rel8");
				
				if(FLAGS.CF || FLAGS.ZF)
				{
					IP.word+=cast(byte)CodeFetchB(1)+2;
				}
				else
				{
					IP.word+=2;
				}
				break;
			}
			
			//asm: ja/jnbe rel8
		case 0x77:
			{
				//Instruction name
				INSTR_NAME("ja/jnbe rel8");
				
				if(!FLAGS.CF && !FLAGS.ZF)
				{
					IP.word+=cast(byte)CodeFetchB(1)+2;
				}
				else
				{
					IP.word+=2;
				}
				break;
			}
			
			//asm: js rel8
		case 0x78:
			{
				//Instruction name
				INSTR_NAME("js rel8");
				
				if(FLAGS.SF)
				{
					IP.word+=cast(byte)CodeFetchB(1)+2;
				}
				else
				{
					IP.word+=2;
				}
				break;
			}
			
			//asm: jns rel8
		case 0x79:
			{
				//Instruction name
				INSTR_NAME("jns rel8");
				
				if(!FLAGS.SF)
				{
					IP.word+=cast(byte)CodeFetchB(1)+2;
				}
				else
				{
					IP.word+=2;
				}
				break;
			}
			
			//asm: jp/jpe rel8
		case 0x7A:
			{
				//Instruction name
				INSTR_NAME("jp/jpe rel8");
				
				if(FLAGS.PF)
				{
					IP.word+=cast(byte)CodeFetchB(1)+2;
				}
				else
				{
					IP.word+=2;
				}
				break;
			}
			
			//asm: jnp/jpo rel8
		case 0x7B:
			{
				//Instruction name
				INSTR_NAME("jnp/jpo rel8");
				
				if(!FLAGS.PF)
				{
					IP.word+=cast(byte)CodeFetchB(1)+2;
				}
				else
				{
					IP.word+=2;
				}
				break;
			}
			
			//asm: jl/jnge rel8
		case 0x7C:
			{
				//Instruction name
				INSTR_NAME("jl/jnge rel8");
				
				if(FLAGS.SF!=FLAGS.OF)
				{
					IP.word+=cast(byte)CodeFetchB(1)+2;
				}
				else
				{
					IP.word+=2;
				}
				break;
			}
			
			//asm: jge/jnl rel8
		case 0x7D:
			{
				//Instruction name
				INSTR_NAME("jge/jnl rel8");
				
				if(FLAGS.SF==FLAGS.OF)
				{
					IP.word+=cast(byte)CodeFetchB(1)+2;
				}
				else
				{
					IP.word+=2;
				}
				break;
			}
			
			//asm: jle/jng rel8
		case 0x7E:
			{
				//Instruction name
				INSTR_NAME("jle/jng rel8");
				
				if(FLAGS.ZF || (FLAGS.SF!=FLAGS.OF))
				{
					IP.word+=cast(byte)CodeFetchB(1)+2;
				}
				else
				{
					IP.word+=2;
				}
				break;
			}
			
			//asm: jg/jnle rel8
		case 0x7F:
			{
				//Instruction name
				INSTR_NAME("jg/jnle rel8");
				
				if(!FLAGS.ZF && (FLAGS.SF==FLAGS.OF))
				{
					IP.word+=cast(byte)CodeFetchB(1)+2;
				}
				else
				{
					IP.word+=2;
				}
				break;
			}
			
		case 0x80:
		case 0x82:
			{
				//Retrieve operands
				uint8_t *dest;
				uint8_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);
				
				(DIREC(opcode)) ? (dest=source) : (source=dest); // Small code to fix opcode resolution
				
				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm); //Dispute!
				
				switch(REG(modrm))
				{
					//asm: add imm8
				case 0x00:
					{
						//Instruction name
						INSTR_NAME("add r/m8, imm8");
						
						//The actual operation
						CheckAdd8(*dest, CodeFetchB(0));
						*dest+=CodeFetchB(0);
						
						//Set flags accordingly
						TestVal(*dest);
						
						IP.word+=1;
						break;
					}
					//asm: or imm8
				case 0x01:
					{
						//Instruction name
						INSTR_NAME("or r/m8, imm8");
						
						//The actual operation
						*dest=CodeFetchB(0)|(*dest);
						
						//Set flags accordingly
						TestVal(*dest);
						FLAGS.CF=false;
						FLAGS.OF=false;
						
						IP.word+=1;
						break;
					}
					//asm: adc imm8
				case 0x02:
					{
						//Instruction name
						INSTR_NAME("adc r/m8, imm8");
						
						//The actual operation
						bool tempCF=FLAGS.CF;
						CheckAdd8(*dest, CodeFetchB(0), FLAGS.CF);
						*dest+=CodeFetchB(0)+tempCF;
						
						//Set flags accordingly
						TestVal(*dest);
						
						IP.word+=1;
						break;
					}
					
					//asm: sbb
				case 0x03:
					{
						//Instruction name
						INSTR_NAME("sbb r/m8, imm8");
						
						//The actual operation
						bool tempCF=FLAGS.CF;
						CheckSub8(*dest, CodeFetchB(0), FLAGS.CF);
						*dest-=CodeFetchB(0)+tempCF;

						//Set flags accordingly
						TestVal(*dest);
						
						IP.word+=1;
						break;
					}
					
					//asm: and
				case 0x04:
					{
						//Instruction name
						INSTR_NAME("and r/m8, imm8");
						
						//The actual operation
						*dest&=CodeFetchB(0);

						//Set flags accordingly
						TestVal(*dest);
						FLAGS.OF=false;
						FLAGS.CF=false;
						
						IP.word+=1;
						break;
					}
					
					//asm: sub
				case 0x05:
					{
						//Instruction name
						INSTR_NAME("sub r/m8, imm8");
						
						//The actual operation
						CheckSub8(*dest, CodeFetchB(0));
						*dest-=CodeFetchB(0);

						//Set flags accordingly
						TestVal(*dest);
						
						IP.word+=1;
						break;
					}
					
					//asm: xor
				case 0x06:
					{
						//Instruction name
						INSTR_NAME("xor r/m8, imm8");
						
						//The actual operation
						*dest^=CodeFetchB(0);

						//Set flags accordingly
						TestVal(*dest);
						
						IP.word+=1;
						break;
					}
					
					//asm: cmp
				case 0x07:
					{
						//Instruction name
						INSTR_NAME("cmp r/m8, imm8");
						
						//The actual operation
						//uint8_t temp=cast(uint8_t)(*source-CodeFetchB(0));
						uint8_t temp=cast(uint8_t)(*dest-CodeFetchB(0));

						//Set flags accordingly
						TestVal(temp);
						//CheckSub8(*source, CodeFetchB(0));
						CheckSub8(*dest, CodeFetchB(0));
						
						IP.word+=1;
						break;
					}
					
				default:
					{
						break;
					}
				}
				break;
			}
			
		case 0x81:
			{
				//Retrieve operands
				uint16_t *dest;
				uint16_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);
				
				(DIREC(opcode)) ? (dest=source) : (source=dest); // Small code to fix opcode resolution
				
				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				
				uint16_t imm16=CodeFetchW(0);
				switch(REG(modrm))
				{
					//asm: add
				case 0x00:
					{
						//Instruction name
						INSTR_NAME("add r/m16, imm16");

						//The actual operation
						CheckAdd16(*dest, imm16);
						*dest+=imm16;
						
						//Set flags accordingly
						TestVal(*dest);
						
						break;
					}
					//asm: or
				case 0x01:
					{
						//Instruction name
						INSTR_NAME("or r/m16, imm16");
						
						//The actual operation
						*dest=imm16|*dest;
						
						//Set flags accordingly
						TestVal(*dest);
						
						break;
					}
					//asm: adc
				case 0x02:
					{
						//Instruction name
						INSTR_NAME("adc r/m16, imm16");

						
						//The actual operation
						bool tempCF=FLAGS.CF;
						CheckAdd16(*dest, imm16, FLAGS.CF);
						*dest+=imm16+tempCF;

						//Set flags accordingly
						TestVal(*dest);

						break;
					}
					//asm: sbb
				case 0x03:
					{
						//Instruction name
						INSTR_NAME("sbb r/m16, imm16");

						
						//The actual operation
						bool tempCF=FLAGS.CF;
						CheckSub16(*dest, imm16, FLAGS.CF);
						*dest-=imm16+tempCF;

						//Set flags accordingly
						TestVal(*dest);

						break;
					}
					//asm: and
				case 0x04:
					{
						//Instruction name
						INSTR_NAME("and r/m16, imm16");

						//The actual operation
						*dest&=imm16;

						//Set flags accordingly
						TestVal(*dest);
						FLAGS.CF=false;
						FLAGS.OF=false;

						break;
					}
					//asm: sub
				case 0x05:
					{
						//Instruction name
						INSTR_NAME("sub r/m16, imm16");
						
						//The actual operation
						CheckSub16(*dest, imm16);
						*dest-=imm16;

						//Set flags accordingly
						TestVal(*dest);

						break;
					}
					//asm: xor
				case 0x06:
					{
						//Instruction name
						INSTR_NAME("xor r/m16, imm16");
						
						//The actual operation
						*dest^=imm16;

						//Set flags accordingly
						TestVal(*dest);

						break;
					}
					//asm: cmp
				case 0x07:
					{
						//Instruction name
						INSTR_NAME("cmp r/m16, imm16");
						
						//The actual operation
						//uint16_t temp=cast(uint16_t)(*source-CodeFetchW(0));
						uint16_t temp=cast(uint16_t)(*dest-CodeFetchW(0));
						
						//Set flags accordingly
						TestVal(temp);
						//CheckSub16(*source, CodeFetchW(0));
						CheckSub16(*dest, CodeFetchW(0));

						break;
					}
				default:
					{
						assert(0, "How this could happen? Byte with all bits tested!");
					}
				}
				IP.word+=2;
				break;
			}
			
			//asm: sub imm8
			//THIS IS GROUP OF INSTRUCTIONS-FIX THIS THING
			//To-do: Inspect futher
			/*
		case 0x82:
			{
				//Instruction name
				INSTR_NAME("sub r/m8, imm8");
				
				//Retrieve operands
				uint8_t *dest;
				uint8_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);
				
				(DIREC(opcode)) ? (dest=source) : (source=dest); // Small code to fix opcode resolution
				
				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				
				//The actual operation
				CheckSub8(*dest, CodeFetchB(0));
				*dest-=CodeFetchB(0);
				
				//Set flags accordingly
				TestVal(*dest);
				
				IP.word+=1;
				x86log.log("sub imm8 called with incomplete implementation");
				break;
			}
			*/
			
			//asm <instruction> imm16
		case 0x83:
			{
				//Retrieve operands
				uint16_t *dest;
				uint16_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);
				
				(DIREC(opcode)) ? (dest=source) : (source=dest); // Small code to fix opcode resolution
				
				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				
				uint16_t imm16=SignExtendB(CodeFetchB(0));

				switch(REG(modrm))
				{
					//asm: add
				case 0x00:
					{
						//Instruction name
						INSTR_NAME("add r/m16, imm16");
						
						//The actual operation
						CheckAdd16(*dest, imm16);
						*dest+=imm16;
						
						//Set flags accordingly
						TestVal(*dest);
						
						IP.word+=1;
						break;
					}
					//asm: or
				case 0x01:
					{
						//Instruction name
						INSTR_NAME("or r/m16, imm16");
						
						//The actual operation
						*dest=imm16|*dest;
						
						//Set flags accordingly
						TestVal(*dest);
						
						IP.word+=1;
						break;
					}
					//asm: adc
				case 0x02:
					{
						//Instruction name
						INSTR_NAME("adc r/m16, imm16");

						//The actual operation
						bool tempCF=FLAGS.CF;
						CheckAdd16(*dest, imm16, FLAGS.CF);
						*dest+=imm16+tempCF;
						
						//Set flags accordingly
						TestVal(*dest);

						IP.word+=1;
						break;
					}
					//asm: sbb
				case 0x03:
					{
						//Instruction name
						INSTR_NAME("sbb r/m16, imm16");

						//The actual operation
						bool tempCF=FLAGS.CF;
						CheckSub16(*dest, imm16, FLAGS.CF);
						*dest-=imm16+tempCF;

						//Set flags accordingly
						TestVal(*dest);

						IP.word+=1;
						break;
					}
					//asm: and
				case 0x04:
					{
						//Instruction name
						INSTR_NAME("and r/m16, imm16");
						
						//The actual operation
						*dest&=imm16;

						//Set flags accordingly
						TestVal(*dest);
						FLAGS.CF=false;
						FLAGS.OF=false;

						IP.word+=1;
						break;
					}
					//asm: sub
				case 0x05:
					{
						//Instruction name
						INSTR_NAME("sub r/m16, imm16");
						
						//The actual operation
						CheckSub16(*dest, cast(ushort)(imm16+FLAGS.CF));
						*dest-=imm16;

						//Set flags accordingly
						TestVal(*dest);

						IP.word+=1;
						break;
					}
					//asm: xor
				case 0x06:
					{
						//Instruction name
						INSTR_NAME("xor r/m16, imm16");
						
						//The actual operation
						*dest^=imm16;

						//Set flags accordingly
						TestVal(*dest);

						IP.word+=1;
						break;
					}
					//asm: cmp
				case 0x07:
					{
						//Instruction name
						INSTR_NAME("cmp r/m16, imm16");

						//The actual operation
						//uint16_t temp=cast(uint16_t)(*source-imm16);
						uint16_t temp=cast(uint16_t)(*dest-imm16);
						
						//Set flags accordingly
						TestVal(temp);
						//CheckSub16(*source, imm16);
						CheckSub16(*dest, imm16);

						IP.word+=1;
						break;
					}
				default:
					{
						assert(0, "How this could happen? Byte with all of the bits tested!");
					}
				}
				break;
			}
			
			//asm: TEST <b>
		case 0x84:
			{
				//Instruction name
				INSTR_NAME("test r/m8, r8");
				
				//Retrieve operands
				uint8_t *dest;
				uint8_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);
				
				//The actual operation
				uint8_t temp=*dest&*source;
				
				//Set flags accordingly
				TestVal(temp);
				FLAGS.CF=false;
				FLAGS.OF=false;

				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);

				break;
			}

			//asm: TEST <v>
		case 0x85:
			{
				//Instruction name
				INSTR_NAME("test r/m16, r16");
				
				//Retrieve operands
				uint16_t *dest;
				uint16_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);
				
				//The actual operation
				uint16_t temp=*dest&*source;
				
				//Set flags accordingly
				TestVal(temp);
				FLAGS.CF=false;
				FLAGS.OF=false;

				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				
				break;
			}

			//asm: xchg, reg8, reg8
		case 0x86:
			{
				//Instruction name
				INSTR_NAME("xchg, r/m8, r8");
				
				//Retrieve operands
				uint8_t *dest;
				uint8_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);

				//The actual operation
				uint8_t temp;
				temp=*dest;
				*dest=*source;
				*source=temp;

				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				break;
			}
			
			//asm: xchg, reg16, reg16
		case 0x87:
			{
				//Instruction name
				INSTR_NAME("xchg, r/m16, r16");
				
				//Retrieve operands
				uint16_t *dest;
				uint16_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);

				//The actual operation
				uint16_t temp;
				temp=*dest;
				*dest=*source;
				*source=temp;

				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				break;
			}

			//asm: mov Eb Gb
		case 0x88:
		case 0x8A:
			{
				//Instruction name
				INSTR_NAME("mov Eb Gb");
				
				//Retrieve operands
				uint8_t *dest;
				uint8_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);

				//The actual operation
				*dest=*source;

				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				break;
			}
			
			//asm: mov Ev Gv
		case 0x89:
		case 0x8B:
			{
				//Instruction name
				INSTR_NAME("mov Ev Gv");
				
				//Retrieve operands
				uint16_t *dest;
				uint16_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);

				//The actual operation
				*dest=*source;

				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				break;
			}
			
			// Seperate two segment register load/store opcodes
			//asm: mov sreg
		case 0x8C:
			{
				//Instruction name
				INSTR_NAME("mov sreg");
				
				//Retrieve operands
				uint16_t *dest;
				uint16_t *source;
				SetupOperands(modrm, opcode|1, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);
				
				//We're dealing with segment registers
				source=&SegIndexToSegReg(REG(modrm)).word;
				
				//The actual operation
				*dest=*source;

				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				break;
			}
			
			//asm: lea r16, m
			//Note: This instruction requires special handling
			//INCOMPLETE IMPLEMENTATION - exception when source operand is not memory
		case 0x8D:
			{
				//Instruction name
				INSTR_NAME("lea");
				
				//Manually get register
				uint16_t* regdest=&regs[REG(modrm)].word;
				
				//Do the operation
				*regdest=Lea16(modrm, CodeFetchW(2));
				
				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				break;
			}
			
			//asm: mov sreg
		case 0x8E:
			{
				//Instruction name
				INSTR_NAME("mov sreg");
				
				//Retrieve operands
				uint16_t *dest;
				uint16_t *source;
				SetupOperands(modrm, opcode|1, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);

				//We're dealing with segment registers
				dest=&SegIndexToSegReg(REG(modrm)).word;
				
				//The actual operation
				*dest=*source;

				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				break;
			}
			
			//asm: pop r/m16
		case 0x8F:
			{
				//Instruction name
				INSTR_NAME("pop r/m16");
				
				//Retrieve operands
				uint16_t *dest;
				uint16_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);

				//We're dealing with segment registers
				//dest=&SegIndexToSegReg(REG(modrm)).word;
				
				//The actual operation
				//*source=pop16();
				*source=pop16();

				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				break;
			}

			//asm: xchg ax, reg16
			//asm: nop
		case 0x90:
		case 0x91:
		case 0x92:
		case 0x93:
		case 0x94:
		case 0x95:
		case 0x96:
		case 0x97:
			{
				//Instruction name
				INSTR_NAME("xchg AX, " ~ RegWordIndexToString(opcode-0x90));
				
				if(opcode==0x90)
				{
					INSTR_NAME("nop");
					IP.word+=1;
					break;
				}
				uint16_t temp;
				temp=regs[REG_AX].word;
				regs[REG_AX].word=regs[opcode-0x90].word;
				regs[opcode-0x90].word=temp;
				IP.word+=1;
				break;
			}
			
			//asm: cbw
		case 0x98:
			{
				//Instruction name
				INSTR_NAME("cbw");
				
				(IsSignSet(regs[REG_AX].hfword[l])) ? (regs[REG_AX].hfword[h]=0xFF) : (regs[REG_AX].hfword[h]=0x00);
				IP.word+=1;
				break;
			}
			
			//asm: cwd
		case 0x99:
			{
				//Instruction name
				INSTR_NAME("cwd");
				
				(IsSignSet(regs[REG_AX].word)) ? (regs[REG_DX].word=0xFFFF) : (regs[REG_DX].word=0x0000);
				IP.word+=1;
				break;
			}
			
			//asm call Ap
		case 0x9A:
			{
				//Instruction name
				INSTR_NAME("call far");
				
				ushort jumpCS=CodeFetchW(3);
				ushort jumpIP=CodeFetchW(1);
				
				push16(CS.word);
				push16(cast(uint16_t)(IP.word+5));
				CS.word=jumpCS;
				IP.word=jumpIP;
				break;
			}
			
			//asm: fwait
		case 0x9B:
			{
				//Instruction name
				INSTR_NAME("fwait");
				
				IP.word+=1;
				break;
			}
			
			//asm: pushf
		case 0x9C:
			{
				//Instruction name
				INSTR_NAME("pushf");
				
				//FLAGS.word|=0b1111000000000010; // Set some bits in FLAGS to 8086/80186 compatible
				FLAGS.word|=0b0000000000000010; // Set some bits in FLAGS to 8086/80186 compatible
				push16(FLAGS.word);
				IP.word+=1;
				break;
			}
			
			//asm: popf
			//To-do: IMPROVE
		case 0x9D: 
			{
				//Instruction name
				INSTR_NAME("popf");
				
				FLAGS.word=pop16();
				FLAGS.hfword[l]= FLAGS.hfword[l] & 0b11010111;
				FLAGS.hfword[l]= FLAGS.hfword[l] | 0b00000010;
				IP.word+=1;
				break;
			}
			
			//asm: sahf
		case 0x9E:
			{
				//Instruction name
				INSTR_NAME("sahf");
				
				uint8_t templflags=regs[REG_AX].hfword[h];
				templflags= templflags & 0b11010111;
				templflags= templflags | 0b00000010;
				FLAGS.hfword[l]=templflags;
				IP.word+=1;
				break;
			}
			
			//asm: lahf
		case 0x9F:
			{
				//Instruction name
				INSTR_NAME("lahf");
				
				uint8_t templflags=FLAGS.hfword[l];
				templflags= templflags & 0b11010111;
				templflags= templflags | 0b00000010;
				regs[REG_AX].hfword[h]=templflags;
				IP.word+=1;
				break;
			}
			
			//asm: mov al, moffs8
		case 0xA0:
			{
				//Instruction name
				//INSTR_NAME("mov al, moffs8");
				
				if(currsegment==NO_SEGMENT)
				{
					currsegment=DS_SEGMENT;
				}
				regs[REG_AX].hfword[l]=RAM.ReadMemory8(SegIndexToSegReg(currsegment).word, RAM.ReadMemory16(CS.word, cast(ushort)(IP.word+1)));
				//Instruction name
				INSTR_NAME(format!"mov al, [0x%04X]"(RAM.ReadMemory16(CS.word, cast(ushort)(IP.word+1))));
				IP.word+=3;
				break;
			}
			
			//asm: mov ax, moffs16
		case 0xA1:
			{
				if(currsegment==NO_SEGMENT)
				{
					currsegment=DS_SEGMENT;
				}
				regs[REG_AX].word=RAM.ReadMemory16(SegIndexToSegReg(currsegment).word, RAM.ReadMemory16(CS.word, cast(ushort)(IP.word+1)));
				
				//Instruction name
				INSTR_NAME(format!"mov ax, [0x%04X]"(RAM.ReadMemory16(CS.word, cast(ushort)(IP.word+1))));
				IP.word+=3;
				break;
			}
			
			//asm: mov moffs8, al
		case 0xA2:
			{
				//Instruction name
				INSTR_NAME("mov moffs8, al");
				
				if(currsegment==NO_SEGMENT)
				{
					currsegment=DS_SEGMENT;
				}
				
				RAM.WriteMemory(SegIndexToSegReg(currsegment).word, RAM.ReadMemory16(CS.word, cast(ushort)(IP.word+1)), regs[REG_AX].hfword[l]);
				IP.word+=3;
				break;
			}
			
			//asm: mov moffs16, ax
		case 0xA3:
			{
				//Instruction name
				INSTR_NAME("mov moffs16, ax");
				
				if(currsegment==NO_SEGMENT)
				{
					currsegment=DS_SEGMENT;
				}
				
				RAM.WriteMemory(SegIndexToSegReg(currsegment).word, RAM.ReadMemory16(CS.word, cast(ushort)(IP.word+1)), regs[REG_AX].word);
				IP.word+=3;
				break;
			}
			
			//To-do: Make movsb and movsw use memset and make them uninterruptible
			//asm: movsb
		case 0xA4:
			{
				//Instruction name
				INSTR_NAME("movsb");
				
				if(rep!=REP_PREFIX_REP && rep!=REP_PREFIX_REPN) // We have REP prefix!
				{
					IP.word+=1;
				}
				else
				{
					if(!regs[REG_CX].word)
					{
						IP.word+=1;
						break;
					}
					regs[REG_CX].word-=1;
				}

				if(currsegment==NO_SEGMENT)
				{
					currsegment=DS_SEGMENT;
				}
				
				uint8_t content1=RAM.ReadMemory8(SegIndexToSegReg(currsegment).word, regs[REG_SI].word);
				RAM.WriteMemory(ES.word, regs[REG_DI].word, content1);
				
				if(!GETBITFLAGS(DF))
				{
					regs[REG_SI].word+=1;
					regs[REG_DI].word+=1;
				}
				else
				{
					regs[REG_SI].word-=1;
					regs[REG_DI].word-=1;
				}
				
				IP.word-=prefixescount;
				break;
			}
			
			//asm: movsw
		case 0xA5:
			{
				//Instruction name
				INSTR_NAME("movsw");
				
				if(rep!=REP_PREFIX_REP && rep!=REP_PREFIX_REPN) // We have REP prefix!
				{
					IP.word+=1;
				}
				else
				{
					if(!regs[REG_CX].word)
					{
						IP.word+=1;
						break;
					}
					regs[REG_CX].word-=1;
				}

				if(currsegment==NO_SEGMENT)
				{
					currsegment=DS_SEGMENT;
				}
				
				uint16_t content1=RAM.ReadMemory16(SegIndexToSegReg(currsegment).word, regs[REG_SI].word);
				RAM.WriteMemory(ES.word, regs[REG_DI].word, content1);
				
				if(!GETBITFLAGS(DF))
				{
					regs[REG_SI].word+=2;
					regs[REG_DI].word+=2;
				}
				else
				{
					regs[REG_SI].word-=2;
					regs[REG_DI].word-=2;
				}
				
				IP.word-=prefixescount;
				break;
			}
			
			//asm: cmpsb
			//To-do: Fix this *thing* -  TOP PRIORITY
		case 0xA6:
			{
				//Instruction name
				INSTR_NAME("cmpsb");
				if(rep!=REP_PREFIX_REPE && rep!=REP_PREFIX_REPN) // We have REP prefix!
				{
					uint8_t content1=RAM.ReadMemory8(SegIndexToSegReg(currsegment).word, regs[REG_SI].word);
					uint8_t content2=RAM.ReadMemory8(ES.word, regs[REG_DI].word);

					
					//Set flags accordingly
					uint8_t temp=cast(uint8_t)(content1-content2);
					TestVal(temp);
					CheckSub8(content1, content2);
					
					if(!GETBITFLAGS(DF))
					{
						regs[REG_SI].word+=1;
						regs[REG_DI].word+=1;
					}
					else
					{
						regs[REG_SI].word-=1;
						regs[REG_DI].word-=1;
					}
					IP.word+=1;
					break;
				}
				else
				{
					if(!regs[REG_CX].word)
					{
						IP.word+=1;
						break;
					}
					ushort counter=regs[REG_CX].word;
					for(int i=0; i<counter; i++)
					{
						int tempval=i;
						if(FLAGS.DF)
						{
							tempval=-i;
						}
						
						uint8_t content1=RAM.ReadMemory8(SegIndexToSegReg(currsegment).word, cast(ushort)(regs[REG_SI].word+tempval));
						uint8_t content2=RAM.ReadMemory8(ES.word, cast(ushort)(regs[REG_DI].word+tempval));
						
						
						//Set flags accordingly
						uint8_t temp=cast(uint8_t)(content1-content2);
						TestVal(temp);
						CheckSub8(content1, content2);

						regs[REG_CX].word-=1;
						if(rep==REP_PREFIX_REPE && !FLAGS.ZF)
						{
							break;
						}
						if(rep==REP_PREFIX_REPN && FLAGS.ZF)
						{
							break;
						}
					}
					
					if(!FLAGS.DF)
					{
						regs[REG_SI].word+=(counter-regs[REG_CX].word);
						regs[REG_DI].word+=(counter-regs[REG_CX].word);
					}
					else
					{
						regs[REG_SI].word-=(counter-regs[REG_CX].word);
						regs[REG_DI].word-=(counter-regs[REG_CX].word);
					}
					
					IP.word+=1;
				}
				break;
			}
			
			//asm: cmpsw
		case 0xA7:
			{
				//Instruction name
				INSTR_NAME("cmpsw");
				if(rep!=REP_PREFIX_REPE && rep!=REP_PREFIX_REPN) // We have REP prefix!
				{
					uint16_t content1=RAM.ReadMemory16(SegIndexToSegReg(currsegment).word, regs[REG_SI].word);
					uint16_t content2=RAM.ReadMemory16(ES.word, regs[REG_DI].word);

					
					//Set flags accordingly
					uint16_t temp=cast(uint16_t)(content1-content2);
					TestVal(temp);
					CheckSub16(content1, content2);
					
					if(!FLAGS.DF)
					{
						regs[REG_SI].word+=2;
						regs[REG_DI].word+=2;
					}
					else
					{
						regs[REG_SI].word-=2;
						regs[REG_DI].word-=2;
					}
					IP.word+=1;
					break;
				}
				else
				{
					if(!regs[REG_CX].word)
					{
						IP.word+=1;
						break;
					}
					ushort counter=regs[REG_CX].word;
					for(int i=0; i<counter; i++)
					{
						int tempval=i;
						if(FLAGS.DF)
						{
							tempval=-i;
						}
						uint16_t content1=RAM.ReadMemory16(SegIndexToSegReg(currsegment).word, cast(ushort)(regs[REG_SI].word+tempval*2));
						uint16_t content2=RAM.ReadMemory16(ES.word, cast(ushort)(regs[REG_DI].word+tempval*2));
						
						
						//Set flags accordingly
						uint16_t temp=cast(uint16_t)(content1-content2);
						TestVal(temp);
						CheckSub16(content1, content2);

						regs[REG_CX].word-=1;
						if(rep==REP_PREFIX_REPE && !FLAGS.ZF)
						{
							x86instr.logf("INSIDE BREAK1b!");
							break;
						}
						if(rep==REP_PREFIX_REPN && FLAGS.ZF)
						{
							x86instr.logf("INSIDE BREAK2b!");
							break;
						}
					}
					x86instr.logf("OUTSIDE 2!");
					
					if(!FLAGS.DF)
					{
						regs[REG_SI].word+=(counter-regs[REG_CX].word)*2;
						regs[REG_DI].word+=(counter-regs[REG_CX].word)*2;
					}
					else
					{
						regs[REG_SI].word-=(counter-regs[REG_CX].word)*2;
						regs[REG_DI].word-=(counter-regs[REG_CX].word)*2;
					}
					
					IP.word+=1;
				}
				break;
			}
			
			//asm: test al, lb
		case 0xA8:
			{
				//Instruction name
				INSTR_NAME("test al, imm8");
				
				IP.word+=1;
				ubyte imm8=CodeFetchB(0);
				ubyte temp=regs[REG_AX].hfword[l] & imm8;
				TestVal(temp);
				
				FLAGS.CF=false;
				FLAGS.OF=false;

				IP.word+=1;
				break;
			}
			
			//asm: test ax, lv
		case 0xA9:
			{
				//Instruction name
				INSTR_NAME("test ax, imm16");
				
				IP.word+=1;
				uint16_t imm16=CodeFetchB(0);
				uint16_t temp=regs[REG_AX].word & imm16;
				TestVal(temp);
				
				FLAGS.CF=false;
				FLAGS.OF=false;

				IP.word+=2;
				break;
			}
			
			//asm: stosb
		case 0xAA:
			{
				//Instruction name
				INSTR_NAME("stosb");
				
				if((rep==REP_PREFIX_REP || rep==REP_PREFIX_REPN) && !regs[REG_CX].word)
				{
					IP.word+=1;
					break;
				}
				
				if(rep==REP_PREFIX_REP || rep==REP_PREFIX_REPN)
				{
					if(regs[REG_DI].word+regs[REG_CX].word>0xFFFF)
					{
						x86instr.logf("Warning: stosb instruction writing out of bounds! Fix this!");
					}
					RAM.MemSetB(SegIndexToSegReg(ES_SEGMENT).word, regs[REG_DI].word, regs[REG_CX].word, regs[REG_AX].hfword[l]);
				}
				else
				{
					RAM.WriteMemory(SegIndexToSegReg(ES_SEGMENT).word, regs[REG_DI].word, regs[REG_AX].hfword[l]);
				}
				
				if(!FLAGS.DF)
				{
					(rep==REP_PREFIX_REP || rep==REP_PREFIX_REPN) ?  (regs[REG_DI].word+=regs[REG_CX].word) : (regs[REG_DI].word+=1);
					//Investigate: (rep==REP_PREFIX_REP || rep==REP_PREFIX_REPN) ?  regs[REG_DI].word+=regs[REG_CX].word : regs[REG_DI].word+=1;
				}
				else
				{
					(rep==REP_PREFIX_REP || rep==REP_PREFIX_REPN) ?  (regs[REG_DI].word-=regs[REG_CX].word) : (regs[REG_DI].word-=1);
				}
				
				if(rep==REP_PREFIX_REP || rep==REP_PREFIX_REPN) regs[REG_CX].word=0;
				IP.word+=1;
				break;
			}
			
			//asm: stosw
		case 0xAB:
			{
				//Instruction name
				INSTR_NAME("stosw");
				
				if((rep==REP_PREFIX_REP || rep==REP_PREFIX_REPN) && !regs[REG_CX].word)
				{
					IP.word+=1;
					break;
				}
				
				if(rep==REP_PREFIX_REP || rep==REP_PREFIX_REPN)
				{
					if(regs[REG_DI].word+regs[REG_CX].word*2>0xFFFF)
					{
						x86instr.logf("Warning: stosw instruction writing out of bounds! Fix this!");
					}
					RAM.MemSetW(SegIndexToSegReg(ES_SEGMENT).word, regs[REG_DI].word, regs[REG_CX].word, regs[REG_AX].word);
				}
				else
				{
					RAM.WriteMemory(SegIndexToSegReg(ES_SEGMENT).word, regs[REG_DI].word, regs[REG_AX].word);
				}
				
				if(!GETBITFLAGS(DF))
				{
					(rep==REP_PREFIX_REP || rep==REP_PREFIX_REPN) ?  (regs[REG_DI].word+=regs[REG_CX].word*2) : (regs[REG_DI].word+=2);
				}
				else
				{
					(rep==REP_PREFIX_REP || rep==REP_PREFIX_REPN) ?  (regs[REG_DI].word-=regs[REG_CX].word*2) : (regs[REG_DI].word-=2);
				}
				
				if(rep==REP_PREFIX_REP || rep==REP_PREFIX_REPN) regs[REG_CX].word=0;
				IP.word+=1;
				
				break;
			}
			
			//asm: lodsb
		case 0xAC:
			{
				//Instruction name
				INSTR_NAME("lodsb");
				 
				if(rep!=REP_PREFIX_REP && rep!=REP_PREFIX_REPN) // We have REP prefix!
				{
					IP.word+=1;
				}
				else
				{
					if(!regs[REG_CX].word)
					{
						IP.word+=1;
						break;
					}
					regs[REG_CX].word-=1;
				}
				
				if(currsegment==NO_SEGMENT)
				{
					currsegment=DS_SEGMENT;
				}

				regs[REG_AX].hfword[l]=RAM.ReadMemory8(SegIndexToSegReg(currsegment).word, regs[REG_SI].word);
				
				if(!FLAGS.DF)
				{
					regs[REG_SI].word+=1;
				}
				else
				{
					regs[REG_SI].word-=1;
				}
				
				if(rep==REP_PREFIX_REP || rep==REP_PREFIX_REPN)
				{
					IP.word-=prefixescount;
				}
				break;
			}
			
			//asm: lodsw
		case 0xAD:
			{
				//Instruction name
				INSTR_NAME("lodsw");
				
				if(rep!=REP_PREFIX_REP && rep!=REP_PREFIX_REPN) // We have REP prefix!
				{
					IP.word+=1;
				}
				else
				{
					if(!regs[REG_CX].word)
					{
						IP.word+=1;
						break;
					}
					regs[REG_CX].word-=1;
				}
				
				if(currsegment==NO_SEGMENT)
				{
					currsegment=DS_SEGMENT;
				}

				regs[REG_AX].word=RAM.ReadMemory16(SegIndexToSegReg(currsegment).word, regs[REG_SI].word);
				
				if(!GETBITFLAGS(DF))
				{
					regs[REG_SI].word+=2;
				}
				else
				{
					regs[REG_SI].word-=2;
				}

				if(rep==REP_PREFIX_REP || rep==REP_PREFIX_REPN)
				{
					IP.word-=prefixescount;
				}
				break;
			}
			
			//asm: scasb
		case 0xAE:
			{
				//Instruction name
				INSTR_NAME("scasb");
				
				if(rep!=REP_PREFIX_REPE && rep!=REP_PREFIX_REPN) // We have REP prefix!
				{
					uint8_t content2=RAM.ReadMemory8(ES.word, regs[REG_DI].word);
				
					//Set flags accordingly
					TestVal(cast(uint8_t)(regs[REG_AX].hfword[l]-content2));
					CheckSub8(regs[REG_AX].hfword[l], content2);
				
					if(!FLAGS.DF)
					{
						regs[REG_DI].word+=1;
					}
					else
					{
						regs[REG_DI].word-=1;
					}
					IP.word+=1;
				}
				else
				{
					if(!regs[REG_CX].word)
					{
						IP.word+=1;
						break;
					}
					uint8_t content2=RAM.ReadMemory8(ES.word, regs[REG_DI].word);
				
					//Set flags accordingly
					TestVal(cast(uint8_t)(regs[REG_AX].hfword[l]-content2));
					CheckSub8(regs[REG_AX].hfword[l], content2);
				
					if(!FLAGS.DF)
					{
						regs[REG_DI].word+=1;
					}
					else
					{
						regs[REG_DI].word-=1;
					}
					regs[REG_CX].word-=1;
					if(rep==REP_PREFIX_REPE && !FLAGS.ZF)
					{
						IP.word+=1;
						break;
					}
					if(rep==REP_PREFIX_REPN && FLAGS.ZF)
					{
						IP.word+=1;
						break;
					}
					IP.word-=prefixescount;
				}
				
				break;
			}
			
			//asm: scasw
		case 0xAF:
			{
				//Instruction name
				INSTR_NAME("scasw");
				
				if(rep!=REP_PREFIX_REPE && rep!=REP_PREFIX_REPN) // We have REP prefix!
				{
					uint16_t content2=RAM.ReadMemory16(ES.word, regs[REG_DI].word);
				
					//Set flags accordingly
					TestVal(cast(uint16_t)(regs[REG_AX].word-content2));
					CheckSub16(regs[REG_AX].word, content2);
				
					if(!FLAGS.DF)
					{
						regs[REG_DI].word+=2;
					}
					else
					{
						regs[REG_DI].word-=2;
					}
					IP.word+=1;
				}
				else
				{
					if(!regs[REG_CX].word)
					{
						IP.word+=1;
						break;
					}
					uint16_t content2=RAM.ReadMemory16(ES.word, regs[REG_DI].word);
				
					//Set flags accordingly
					TestVal(cast(uint16_t)(regs[REG_AX].word-content2));
					CheckSub16(regs[REG_AX].word, content2);
				
					if(!FLAGS.DF)
					{
						regs[REG_DI].word+=2;
					}
					else
					{
						regs[REG_DI].word-=2;
					}
					regs[REG_CX].word-=1;
					if(rep==REP_PREFIX_REPE && !FLAGS.ZF)
					{
						IP.word+=1;
						break;
					}
					if(rep==REP_PREFIX_REPN && FLAGS.ZF)
					{
						IP.word+=1;
						break;
					}
					IP.word-=prefixescount;
				}
				break;
			}
			
			//asm: mov al, imm8
		case 0xB0:
			{
				//Instruction name
				INSTR_NAME("mov al, imm8");
				
				regs[REG_AX].hfword[l]=CodeFetchB(1);
				IP.word+=2;
				break;
			}
			
			//asm: mov cl, imm8
		case 0xB1:
			{
				//Instruction name
				INSTR_NAME("mov cl, imm8");
				
				regs[REG_CX].hfword[l]=CodeFetchB(1);
				IP.word+=2;
				break;
			}
			
			//asm: mov dl, imm8
		case 0xB2:
			{
				//Instruction name
				INSTR_NAME("mov dl, imm8");
				
				regs[REG_DX].hfword[l]=CodeFetchB(1);
				IP.word+=2;
				break;
			}
			
			//asm: mov bl, imm8
		case 0xB3:
			{
				//Instruction name
				INSTR_NAME("mov bl, imm8");
				
				regs[REG_BX].hfword[l]=CodeFetchB(1);
				IP.word+=2;
				break;
			}
			
			//asm: mov ah, imm8
		case 0xB4:
			{
				//Instruction name
				INSTR_NAME("mov ah, imm8");
				
				regs[REG_AX].hfword[h]=CodeFetchB(1);
				IP.word+=2;
				break;
			}
			
			//asm: mov ch, imm8
		case 0xB5:
			{
				//Instruction name
				INSTR_NAME("mov ch, imm8");
				
				regs[REG_CX].hfword[h]=CodeFetchB(1);
				IP.word+=2;
				break;
			}
			
			//asm: mov dh, imm8
		case 0xB6:
			{
				//Instruction name
				INSTR_NAME("mov dh, imm8");
				
				regs[REG_DX].hfword[h]=CodeFetchB(1);
				IP.word+=2;
				break;
			}
			
			//asm: mov bh, imm8
		case 0xB7:
			{
				//Instruction name
				INSTR_NAME("mov bh, imm8");
				
				regs[REG_BX].hfword[h]=CodeFetchB(1);
				IP.word+=2;
				break;
			}
			
			//asm: mov <reg>, imm16
		case 0xB8:
		case 0xB9:
		case 0xBA:
		case 0xBB:
		case 0xBC:
		case 0xBD:
		case 0xBE:
		case 0xBF:
			{
				//Instruction name
				INSTR_NAME("mov " ~ RegWordIndexToString(opcode-0xB8) ~ ", " ~ to!string(CodeFetchW(1)));
				
				regs[opcode-0xB8].word=CodeFetchW(1);
				IP.word+=3;
				break;
			}
			
			//asm: retn imm16
			//To-do: Check whether the fix is working
		case 0xC2:
			{
				//Instruction name
				INSTR_NAME("retn imm16");
				
				ushort stackAdd=CodeFetchW(1);
				IP.word=pop16();
				regs[REG_SP].word+=stackAdd;
				break;
			}
			
			//asm: retn
		case 0xC3:
			{
				//Instruction name
				INSTR_NAME("retn");
				
				IP.word=pop16();
				break;
			}
			
			//asm: les
		case 0xC4:
			{
				//Instruction name
				INSTR_NAME("les");
				
				//Retrieve operands
				void *dest;
				void *source;
				SetupOperands(modrm, 0b11, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);
				Pointer8086_32bit* arraylimit=cast(Pointer8086_32bit*)source;
				
				//Manually get register
				uint16_t* regdest=&regs[REG(modrm)].word;
				
				//Do the operation
				ES.word=arraylimit.highpart;
				*regdest=arraylimit.lowpart;
				
				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				break;
			}
			
			//asm: lds
		case 0xC5:
			{
				//Instruction name
				INSTR_NAME("lds");
				
				//Retrieve operands
				void *dest;
				void *source;
				SetupOperands(modrm, 0b11, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);
				Pointer8086_32bit* arraylimit=cast(Pointer8086_32bit*)source;
				
				//Manually get register
				uint16_t* regdest=&regs[REG(modrm)].word;
				
				//Do the operation
				DS.word=arraylimit.highpart;
				*regdest=arraylimit.lowpart;
				
				//Move past the current instruction and set IP register to next instruction
				IP.word+=2;
				AdjustIP(IP, modrm);
				break;
			}
			
			//asm: mov Eb Ib
		case 0xC6:
			{
				//Instruction name
				INSTR_NAME("mov Eb Ib");
				
				//Retrieve operands
				uint8_t *dest;
				uint8_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);
				
				AdjustIP(IP, modrm);
				*source=CodeFetchB(2);
				IP.word+=3;
				break;
			}
			
			//asm: mov Ev Iv
		case 0xC7:
			{
				//Instruction name
				INSTR_NAME("mov Ev Iv");
				
				//Retrieve operands
				uint16_t *dest;
				uint16_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);
				
				AdjustIP(IP, modrm);
				*source=CodeFetchW(2);
				IP.word+=4;	
				break;
			}
			
			//asm: enter
			//INCOMPLETE - probably incomplete
		case 0xC8:
			{
				//Instruction name
				INSTR_NAME("enter");
				
				uint16_t imm16=CodeFetchW(1);
				uint8_t imm8=RAM.ReadMemory8(CS.word, cast(ushort)(IP.word+3));
				
				imm8=imm8%32;
				
				push16(regs[REG_BP].word);
				uint16_t tempframeptr=regs[REG_SP].word;
				if(imm8!=0)
				{
					for(int i=1; i<imm8; i++)
					{
						regs[REG_BP].word-=4;
						push16(regs[REG_BP].word);
					}
				}
				regs[REG_BP].word=tempframeptr;
				regs[REG_SP].word-=imm16;
				
				
				
				IP.word+=4;
				break;
			}
			
			//asm: leave
		case 0xC9:
			{
				//Instruction name
				INSTR_NAME("leave");
				
				regs[REG_SP].word=regs[REG_BP].word;
				regs[REG_BP].word=pop16();
				IP.word+=1;
				break;
			}
			
			//asm: retf imm16
		case 0xCA:
			{
				//Instruction name
				INSTR_NAME("retf imm16");
				
				uint16_t freestack=CodeFetchW(1);
				IP.word=pop16();
				CS.word=pop16();
				regs[REG_SP].word+=freestack;
				break;
			}
			
			//asm: retf
		case 0xCB:
			{
				//Instruction name
				INSTR_NAME("retf");
				
				IP.word=pop16();
				CS.word=pop16();
				break;
			}
			
			//asm: int3
		case 0xCC:
			{
				//Instruction name
				INSTR_NAME("int3");
				
				IP.word+=1;
				RaiseInt(EXCEPTION_BREAKPOINT);
				break;
			}
			
			//asm: int imm8
		case 0xCD:
			{
				//Instruction name
				INSTR_NAME("int " ~ to!string(CodeFetchB(1)));
				
				uint8_t vectornumber=CodeFetchB(1);
				IP.word+=2;
				RaiseInt(vectornumber);
				break;
			}
			
			//asm: into
		case 0xCE:
			{
				//Instruction name
				INSTR_NAME("into");
				
				if(FLAGS.OF)
				{
					RaiseInt(EXCEPTION_OVERFLOW);
				}
				else
				{
					IP.word+=1;
				}
				break;
			}
			
			//asm: iret
		case 0xCF:
			{
				//Instruction name
				INSTR_NAME("iret");
				
				IP.word=pop16();
				CS.word=pop16();
				FLAGS.word=pop16();
				NMIretawaiting=false;
				break;
			}
			
			//asm: GRP2b
			//INCOMPLETE
		case 0xD0:
		case 0xD2:
		case 0xC0:
			{
				switch(REG(modrm))
				{
				//asm: ROL r/m8 , CL/1
				case 0x00:
					{
						//Instruction name
						INSTR_NAME("ROL r/m8 , CL/1");
						
						uint8_t shiftcount=1;
						if(opcode==0xD2)
						{
							shiftcount=regs[REG_CX].hfword[l];
							shiftcount= shiftcount & 0x1F;
						}
						//Retrieve operands
						uint8_t *dest; //Not used here
						uint8_t *source;

						SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);

						(DIREC(opcode)) ? (dest=source) : (source=dest); // Small code to fix opcode resolution
						
						//Set IP
						IP.word+=2;
						AdjustIP(IP, modrm);
						
						if(opcode==0xC0)
						{
							shiftcount=CodeFetchB(0);
							shiftcount= shiftcount & 0x1F;
							IP.word+=1;
						}
						
						while(shiftcount)
						{
							bool CFstat= *source>>7;
							
							*dest=cast(ubyte)((*dest<<1)+CFstat);
							shiftcount--;
						}
						FLAGS.CF=*dest&0x1;

						break;
					}
					//asm: ROR r/m8 , CL/1
				case 0x01:
					{
						//Instruction name
						INSTR_NAME("ROR r/m8 , CL/1");
						
						uint8_t shiftcount=1;
						if(opcode==0xD2)
						{
							shiftcount=regs[REG_CX].hfword[l];
							shiftcount= shiftcount & 0x1F;
						}
						//Retrieve operands
						uint8_t *dest; //Not used here
						uint8_t *source;

						SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);

						(DIREC(opcode)) ? (dest=source) : (source=dest); // Small code to fix opcode resolution
						
						//Set IP
						IP.word+=2;
						AdjustIP(IP, modrm);
						
						if(opcode==0xC0)
						{
							shiftcount=CodeFetchB(0);
							shiftcount= shiftcount & 0x1F;
							IP.word+=1;
						}
						
						while(shiftcount)
						{
							bool CFstat= *source & 0x1;
							
							*dest=cast(ubyte)((*dest>>1)+(CFstat<<7));
							shiftcount--;
						}
						FLAGS.CF=*dest>>7;
						
						break;
					}
					
				//asm: RCL r/m8 , CL/1
				case 0x02:
					{
						//Instruction name
						INSTR_NAME("RCL r/m8 , CL/1");
						
						uint8_t shiftcount=1;
						if(opcode==0xD2)
						{
							shiftcount=regs[REG_CX].hfword[l];
							shiftcount= shiftcount & 0x1F;
						}
						//Retrieve operands
						uint8_t *dest; //Not used here
						uint8_t *source;

						SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);

						(DIREC(opcode)) ? (dest=source) : (source=dest); // Small code to fix opcode resolution
						
						//Set IP
						IP.word+=2;
						AdjustIP(IP, modrm);
						
						if(opcode==0xC0)
						{
							shiftcount=CodeFetchB(0);
							shiftcount= shiftcount & 0x1F;
							IP.word+=1;
						}
						
						while(shiftcount)
						{
							bool CFstat= *source>>7;
							
							*dest=cast(ubyte)((*dest<<1)+FLAGS.CF);
							FLAGS.CF=CFstat;
							shiftcount--;
						}
						if(shiftcount==1)
						{
							FLAGS.OF=*source>>7 ^ FLAGS.CF;
						}

						break;
					}
					
				//asm: RCR r/m8 , CL/1
				case 0x03:
					{
						//Instruction name
						INSTR_NAME("RCR r/m8 , CL/1");
						
						uint8_t shiftcount=1;
						if(opcode==0xD2)
						{
							shiftcount=regs[REG_CX].hfword[l];
							shiftcount= shiftcount & 0x1F;
						}
						//Retrieve operands
						uint8_t *dest; //Not used here
						uint8_t *source;

						SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);

						(DIREC(opcode)) ? (dest=source) : (source=dest); // Small code to fix opcode resolution
						
						//Set IP
						IP.word+=2;
						AdjustIP(IP, modrm);
						
						if(opcode==0xC0)
						{
							shiftcount=CodeFetchB(0);
							shiftcount= shiftcount & 0x1F;
							IP.word+=1;
						}
						
						if(shiftcount==1)
						{
							FLAGS.OF=*source>>7 ^ FLAGS.CF;
						}
						
						while(shiftcount)
						{
							bool CFstat= *source&0x1;
							
							*dest=cast(ubyte)((*dest>>1)|FLAGS.CF<<7);
							FLAGS.CF=CFstat;
							shiftcount--;
						}

						break;
					}
					
					//asm: SAL/SHL r/m8 , CL/1
				case 0x04:
				case 0x06:
					{
						//Instruction name
						INSTR_NAME("SAL/SHL r/m8 , CL/1");
						
						uint8_t shiftcount=1;
						if(opcode==0xD2)
						{
							shiftcount=regs[REG_CX].hfword[l];
							shiftcount= shiftcount & 0x1F;
						}
						//Retrieve operands
						uint8_t *dest; //Not used here
						uint8_t *source;

						SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);

						(DIREC(opcode)) ? (dest=source) : (source=dest); // Small code to fix opcode resolution
						
						//Set IP
						IP.word+=2;
						AdjustIP(IP, modrm);
						
						if(opcode==0xC0)
						{
							shiftcount=CodeFetchB(0);
							shiftcount= shiftcount & 0x1F;
							IP.word+=1;
						}
						
						uint8_t shiftcounttemp=shiftcount;
						while(shiftcount)
						{
							bool CFstat= *source >> 7;
							FLAGS.CF=CFstat;
							
							*source = cast(uint8_t)(*source << 1);
							shiftcount--;
						}
						
						if(shiftcounttemp==1)
						{
							FLAGS.OF=(*source >> 7) ^ FLAGS.CF;
						}
						
						break;
					}
					
					//asm: SHR r/m8 , CL/1
				case 0x05:
					{
						//Instruction name
						INSTR_NAME("SHR r/m8 , CL/1");
						
						uint8_t shiftcount=1;
						if(opcode==0xD2)
						{
							shiftcount=regs[REG_CX].hfword[l];
							shiftcount= shiftcount & 0x1F;
						}
						//Retrieve operands
						uint8_t *dest; //Not used here
						uint8_t *source;

						SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);

						(DIREC(opcode)) ? (dest=source) : (source=dest); // Small code to fix opcode resolution
						
						//Set IP
						IP.word+=2;
						AdjustIP(IP, modrm);
						
						if(opcode==0xC0)
						{
							shiftcount=CodeFetchB(0);
							shiftcount= shiftcount & 0x1F;
							IP.word+=1;
						}
						
						while(shiftcount)
						{
							bool CFstat= *source & 0x1;
							FLAGS.CF=CFstat;
							
							*source=*source>>>1;
							shiftcount--;
						}

						break;
					}
					
					//asm: SAR r/m8 , CL/1
				case 0x07:
					{
						//Instruction name
						INSTR_NAME("SAR r/m8 , CL/1");
						
						uint8_t shiftcount=1;
						if(opcode==0xD2)
						{
							shiftcount=regs[REG_CX].hfword[l];
							shiftcount= shiftcount & 0x1F;
						}
						//Retrieve operands
						uint8_t *dest; //Not used here
						uint8_t *source;

						SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);

						(DIREC(opcode)) ? (dest=source) : (source=dest); // Small code to fix opcode resolution
						
						//Set IP
						IP.word+=2;
						AdjustIP(IP, modrm);
						
						if(opcode==0xC0)
						{
							shiftcount=CodeFetchB(0);
							shiftcount= shiftcount & 0x1F;
							IP.word+=1;
						}
						
						
						//To-do: Improve even more...
						while(shiftcount)
						{
							bool CFstat= *source&0x1;
							ubyte bit7=(*source&0x80);
							FLAGS.CF=CFstat;
							
							*source=(*source>>1)|bit7;
							shiftcount--;
						}
						FLAGS.OF=false;
						
						break;
					}
				default:
					{
						x86instr.logf(format!"\nINVALID OPCODE GRP2b: 0x%04X! Opcode: 0x%02X!\n"(REG(modrm), opcode));
						x86instr.logf(format!"CS=0x%04X | IP=0x%04X\n"(CS.word, IP.word));
						RaiseInt(EXCEPTION_INVALIDOPCODE);
						break;
					}
				}
				break;
			}
			
			//asm: GRP2b
			//INCOMPLETE
		case 0xD1:
		case 0xD3:
		case 0xC1:
			{
				switch(REG(modrm))
				{
				//asm: ROL r/m16 , CL/1
				case 0x00:
					{
						//Instruction name
						INSTR_NAME("ROL r/m16 , CL/1");
						
						uint8_t shiftcount=1;
						if(opcode==0xD3)
						{
							shiftcount=regs[REG_CX].hfword[l];
							shiftcount= shiftcount & 0x1F;
						}
						//Retrieve operands
						uint16_t *dest; //Not used here
						uint16_t *source;

						SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);

						(DIREC(opcode)) ? (dest=source) : (source=dest); // Small code to fix opcode resolution
						
						//Set IP
						IP.word+=2;
						AdjustIP(IP, modrm);
						
						if(opcode==0xC1)
						{
							shiftcount=CodeFetchB(0);
							shiftcount= shiftcount & 0x1F;
							IP.word+=1;
						}
						
						while(shiftcount)
						{
							bool CFstat= *source>>15;
							
							*dest=cast(ushort)((*dest<<1)+CFstat);
							shiftcount--;
						}
						FLAGS.CF=*dest&0x1;

						break;
					}
					//asm: ROR r/m16 , CL/1
				case 0x01:
					{
						//Instruction name
						INSTR_NAME("ROR r/m16 , CL/1");
						
						uint8_t shiftcount=1;
						if(opcode==0xD3)
						{
							shiftcount=regs[REG_CX].hfword[l];
							shiftcount= shiftcount & 0x1F;
						}
						//Retrieve operands
						uint16_t *dest; //Not used here
						uint16_t *source;

						SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);

						(DIREC(opcode)) ? (dest=source) : (source=dest); // Small code to fix opcode resolution
						
						//Set IP
						IP.word+=2;
						AdjustIP(IP, modrm);
						
						if(opcode==0xC1)
						{
							shiftcount=CodeFetchB(0);
							shiftcount= shiftcount & 0x1F;
							IP.word+=1;
						}
						
						while(shiftcount)
						{
							bool CFstat= *source & 0x1;
							
							*dest=cast(ushort)((*dest>>1)+(CFstat<<15));
							shiftcount--;
						}
						FLAGS.CF=*dest>>15;
						
						break;
					}
					
					//asm: RCL r/m16 , CL/1
				case 0x02:
					{
						//Instruction name
						INSTR_NAME("RCL r/m16 , CL/1");
						
						uint8_t shiftcount=1;
						if(opcode==0xD3)
						{
							shiftcount=regs[REG_CX].hfword[l];
							shiftcount= shiftcount & 0x1F;
						}
						//Retrieve operands
						uint16_t *dest; //Not used here
						uint16_t *source;

						SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);

						(DIREC(opcode)) ? (dest=source) : (source=dest); // Small code to fix opcode resolution
						
						//Set IP
						IP.word+=2;
						AdjustIP(IP, modrm);
						
						if(opcode==0xC1)
						{
							shiftcount=CodeFetchB(0);
							shiftcount= shiftcount & 0x1F;
							IP.word+=1;
						}
						
						while(shiftcount)
						{
							bool CFstat= *source>>15;
							
							*dest=cast(ushort)((*dest<<1)+FLAGS.CF);
							FLAGS.CF=CFstat;
							shiftcount--;
						}
						if(shiftcount==1)
						{
							FLAGS.OF=*source>>15 ^ FLAGS.CF;
						}

						break;
					}
					
				//asm: RCR r/m16 , CL/1
				case 0x03:
					{
						//Instruction name
						INSTR_NAME("RCR r/m16 , CL/1");
						
						uint8_t shiftcount=1;
						if(opcode==0xD3)
						{
							shiftcount=regs[REG_CX].hfword[l];
							shiftcount= shiftcount & 0x1F;
						}
						//Retrieve operands
						uint16_t *dest; //Not used here
						uint16_t *source;

						SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);

						(DIREC(opcode)) ? (dest=source) : (source=dest); // Small code to fix opcode resolution
						
						//Set IP
						IP.word+=2;
						AdjustIP(IP, modrm);
						
						if(opcode==0xC1)
						{
							shiftcount=CodeFetchB(0);
							shiftcount= shiftcount & 0x1F;
							IP.word+=1;
						}
						
						if(shiftcount==1)
						{
							FLAGS.OF=*source>>15 ^ FLAGS.CF;
						}
						
						while(shiftcount)
						{
							bool CFstat= *source&0x1;
							
							*dest=cast(ushort)((*dest>>1)|FLAGS.CF<<15);
							FLAGS.CF=CFstat;
							shiftcount--;
						}

						break;
					}
					
					//asm: SAL/SHL r/m16 , CL/1
				case 0x04:
				case 0x06:
					{
						//Instruction name
						INSTR_NAME("SAL/SHL r/m16 , CL/1");
						
						uint8_t shiftcount=1;
						if(opcode==0xD3)
						{
							shiftcount=regs[REG_CX].hfword[l];
							shiftcount= shiftcount & 0x1F;
						}

						//Retrieve operands
						uint16_t *dest; //Not used here
						uint16_t *source;
						SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);
						
						(DIREC(opcode)) ? (dest=source) : (source=dest); // Small code to fix opcode resolution
						//Set IP
						IP.word+=2;
						AdjustIP(IP, modrm);
						
						if(opcode==0xC1)
						{
							shiftcount=CodeFetchB(0);
							shiftcount= shiftcount & 0x1F;
							IP.word+=1;
						}
						
						uint16_t shiftcounttemp=shiftcount;
						while(shiftcount)
						{
							bool CFstat= cast(ushort)(*source >> 15);
							FLAGS.CF=CFstat;
							
							*source = cast(ushort)(*source << 1);
							shiftcount--;
						}
						
						if(shiftcounttemp==1)
						{
							FLAGS.OF=(*source >> 15) ^ FLAGS.CF;
						}
						
						TestVal(*source);
						
						break;
					}
					
					//asm: SHR r/m16 , CL/1
				case 0x05:
					{
						//Instruction name
						INSTR_NAME("SHR r/m16 , CL/1");
						
						uint8_t shiftcount=1;
						if(opcode==0xD3)
						{
							shiftcount=regs[REG_CX].hfword[l];
							shiftcount= shiftcount & 0x1F;
						}

						//Retrieve operands
						uint16_t *dest; //Not used here
						uint16_t *source;
						SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);
						
						(DIREC(opcode)) ? (dest=source) : (source=dest); // Small code to fix opcode resolution
						//Set IP
						IP.word+=2;
						AdjustIP(IP, modrm);
						
						if(opcode==0xC1)
						{
							shiftcount=CodeFetchB(0);
							shiftcount= shiftcount & 0x1F;
							IP.word+=1;
						}

						
						uint16_t tempdest=*source;
						while(shiftcount)
						{
							bool CFstat= *source & 0x1;
							FLAGS.CF=CFstat;
							
							*source=*source>>>1;
							shiftcount--;
						}
						
						FLAGS.OF=(tempdest>>15);
						
						TestVal(*source);
						
						break;
					}
					
					//asm: SAR r/m16 , CL/1
				case 0x07:
					{
						//Instruction name
						INSTR_NAME("SAR r/m16 , CL/1");
						
						uint8_t shiftcount=1;
						if(opcode==0xD3)
						{
							shiftcount=regs[REG_CX].hfword[l];
							shiftcount= shiftcount & 0x1F;
						}

						//Retrieve operands
						uint16_t *dest; //Not used here
						uint16_t *source;
						SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);
						
						(DIREC(opcode)) ? (dest=source) : (source=dest); // Small code to fix opcode resolution
						
						//Set IP
						IP.word+=2;
						AdjustIP(IP, modrm);
						
						if(opcode==0xC1)
						{
							shiftcount=CodeFetchB(0);
							shiftcount= shiftcount & 0x1F;
							IP.word+=1;
						}
						
						while(shiftcount)
						{
							bool CFstat= *source&0x1;
							ushort bit15=(*source&0x8000);
							FLAGS.CF=CFstat;
							
							*source=(*source>>1)|bit15;
							shiftcount--;
						}
						
						FLAGS.OF=false;
						break;
					}
				default:
					{
						x86instr.logf(format!"\nINVALID OPCODE GRP2b: %s! IMPROVE IT!\n"(REG(modrm)));
						RaiseInt(EXCEPTION_INVALIDOPCODE);
						break;
					}
				}
				break;
			}
			
			//asm: AAM
			//INCOMPLETE - flags
		case 0xD4:
			{
				//Instruction name
				INSTR_NAME("aam");
				
				uint8_t imm8=CodeFetchB(1);
				
				regs[REG_AX].hfword[h]=regs[REG_AX].hfword[l]/imm8;
				regs[REG_AX].hfword[l]=regs[REG_AX].hfword[l]%imm8;
				
				IP.word+=2;
				break;
			}
			
			//asm: AAD
		case 0xD5:
			{
				//Instruction name
				INSTR_NAME("aad");
				
				uint8_t imm8=CodeFetchB(1);
				
				uint8_t tempAL=regs[REG_AX].hfword[l];
				uint8_t tempAH=regs[REG_AX].hfword[h];
				
				regs[REG_AX].hfword[l]=tempAL+(tempAH*imm8) & 0xFF;
				TestVal(regs[REG_AX].hfword[l]);
				
				regs[REG_AX].hfword[l]=0;
				
				IP.word+=2;
				break;
			}
			
			//asm: SALC
		case 0xD6:
			{
				//Instruction name
				INSTR_NAME("salc");

				FLAGS.CF ? (IP.hfword[l]=0xFF) : (IP.hfword[l]=0x00);
				IP.word+=1;
				break;
			}
			
			//asm: XLATB/XLAT
		case 0xD7:
			{
				//Instruction name
				INSTR_NAME("xlat");
				
				if(currsegment==NO_SEGMENT)
				{
					currsegment=DS_SEGMENT;
				}
				regs[REG_AX].hfword[l]=RAM.ReadMemory8(SegIndexToSegReg(currsegment).word, cast(ushort)(regs[REG_BX].word+regs[REG_AX].hfword[l]));
				IP.word+=1;
				break;
			}
			
			//FPU instructions
		case 0xD8:
		case 0xD9:
		case 0xDA:
		case 0xDB:
		case 0xDC:
		case 0xDD:
		case 0xDE:
		case 0xDF:
			{
				//We handle FPU opcodes seperately
				INSTR_NAME("INVOKE FPU");
				FPU_Instruction_Handler(opcode);
				break;
			}
			
			//asm: LOOPNE/LOOPNZ rel8
		case 0xE0:
			{
				//Instruction name
				INSTR_NAME("LOOPNE rel8");
				
				regs[REG_CX].word-=1;
				if(regs[REG_CX].word && !GETBITFLAGS(ZF))
				{
					IP.word+=cast(int8_t)(RAM.ReadMemory8(CS.word, cast(ushort)(IP.word+1)))+2;
				}
				else
				{
					IP.word+=2;
				}
				break;
			}
			
			//asm: LOOPE/LOOPZ rel8
		case 0xE1:
			{
				//Instruction name
				INSTR_NAME("LOOPE rel8");
				
				regs[REG_CX].word-=1;
				if(regs[REG_CX].word && GETBITFLAGS(ZF))
				{
					IP.word+=cast(int8_t)(RAM.ReadMemory8(CS.word, cast(ushort)(IP.word+1)))+2;
				}
				else
				{
					IP.word+=2;
				}
				break;
			}
			
			//asm: LOOP rel8
		case 0xE2:
			{
				//Instruction name
				INSTR_NAME("LOOP rel8");
				
				regs[REG_CX].word-=1;
				if(regs[REG_CX].word)
				{
					IP.word+=cast(int8_t)(RAM.ReadMemory8(CS.word, cast(ushort)(IP.word+1)))+2;
				}
				else
				{
					IP.word+=2;
				}
				break;
			}
			
			//asm: JCXZ rel8
		case 0xE3:
			{
				//Instruction name
				INSTR_NAME("JCXZ rel8");
				
				if(!regs[REG_CX].word)
				{
					IP.word+=cast(int8_t)(CodeFetchB(1))+2;
				}
				else
				{
					IP.word+=2;
				}
				break;
			}
			
			//asm: in al, imm8
		case 0xE4:
			{
				//Instruction name
				INSTR_NAME("in al, imm8");
				
				regs[REG_AX].hfword[l]=InPort(RAM.ReadMemory8(CS.word, cast(ushort)(IP.word+1))) & 0x00FF;
				IP.word+=2;
				break;
			}
			
			//asm: in ax, imm8
		case 0xE5:
			{
				//Instruction name
				INSTR_NAME("in ax, imm8");
				
				regs[REG_AX].word=InPort(RAM.ReadMemory8(CS.word, cast(ushort)(IP.word+1)));
				IP.word+=2;
				break;
			}
			
			//asm: out imm8, al
		case 0xE6:
			{
				//Instruction name
				INSTR_NAME("out imm8, al");
				
				OutPort(RAM.ReadMemory8(CS.word, cast(ushort)(IP.word+1)), regs[REG_AX].hfword[l]);
				IP.word+=2;
				break;
			}
			
			//asm: out imm8, ax
		case 0xE7:
			{
				//Instruction name
				INSTR_NAME("out imm8, ax");
				
				OutPort(RAM.ReadMemory8(CS.word, cast(ushort)(IP.word+1)), regs[REG_AX].word);
				IP.word+=2;
				break;
			}
			
			//asm: call Jv
		case 0xE8:
			{
				//Instruction name
				INSTR_NAME("call Jv");
				
				push16(cast(ushort)(IP.word+3));
				IP.word+=cast(short)CodeFetchW(1);
				IP.word+=3;
				break;
			}
			
			//asm: jmp Jv
		case 0xE9:
			{
				//Instruction name
				INSTR_NAME("jmp Jv");
				
				IP.word+=cast(short)CodeFetchW(1);
				IP.word+=3;
				break;
			}
			
			//asm: jmp far
		case 0xEA:
			{
				//Instruction name
				INSTR_NAME("jmp far");
				
				uint16_t offset=CodeFetchW(1);
				uint16_t segment=CodeFetchW(3);
				
				CS.word=segment;
				IP.word=offset;
				break;
			}
			
			//asm: jmp short $+x
		case 0xEB:
			{
				//Instruction name
				INSTR_NAME("jmp short $+x");
				
				IP.word+=cast(int8_t)CodeFetchB(1);
				IP.word+=2;
				break;
			}
			
			//asm: in al, dx
		case 0xEC:
			{
				//Instruction name
				INSTR_NAME("in al, dx");
				
				regs[REG_AX].hfword[l]=InPort(regs[REG_DX].word)&0x00FF;
				IP.word+=1;
				break;
			}
			
			//asm: in ax, dx
		case 0xED:
			{
				//Instruction name
				INSTR_NAME("in ax, dx");
				
				regs[REG_AX].word=InPort(regs[REG_DX].word);
				IP.word+=1;
				break;
			}
			
			//asm out DX, al
		case 0xEE:
			{
				//Instruction name
				INSTR_NAME("out DX, al");
				
				OutPort(regs[REG_DX].word, regs[REG_AX].hfword[l]);
				IP.word+=1;
				break;
			}
			
			//asm out DX, ax
		case 0xEF:
			{
				//Instruction name
				INSTR_NAME("out DX, ax");
				
				OutPort(regs[REG_DX].word, regs[REG_AX].word);
				IP.word+=1;
				break;
			}
			
			//asm: LOCK:
			//case 0xF0:	
			
			//asm: int1/icebp
			//Note: When the instructions has REP prefix, then the program will service request from the VM
		case 0xF1:
			{
				//Instruction name
				INSTR_NAME("icebp/int1");
				if(rep!=REP_PREFIX_REP)
				{
					machine.CommandWindow("icebp");
				}
				else
				{
					VMInvokeHandler(this);
				}
				IP.word+=1;
				break;
			}
			
			//asm: REPNE:
			//case 0xF2:
			
			//asm: REP:
			//case 0xF3:

			//asm: HLT
		case 0xF4:
			{
				//Instruction name
				INSTR_NAME("hlt");
				
				halted=true;
				x86instr.flush();
				x86log.logf("HLT instruction called! CS=0x%04X | IP=0x%04X", CS.word, IP.word);
				x86instr.logf(format!"HLT instruction called! CS=0x%04X | IP=0x%04X"(CS.word, IP.word));
				if(!FLAGS.IF)
				{
					x86log.log("Warning! FLAGS.IF=0 and HLT executed. Hanging the machine");
				}
				IP.word+=1;
				break;
			}

			//asm: cmc
		case 0xF5:
			{
				//Instruction name
				INSTR_NAME("cmc");
				
				FLAGS.CF=!FLAGS.CF;
				IP.word+=1;
				break;
			}
			
			//asm: GRP3a
		case 0xF6:
			{
				//Retrieve operands
				uint8_t *dest; //Not used here
				uint8_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);

				uint8_t regfld=REG(modrm);
				switch(regfld)
				{
					//asm: test Eb Ib
				case 0x00:
				case 0x01: //http://ref.x86asm.net/coder32.html#gen_note_TEST_F6_1_F7_1
					{
						//Instruction name
						INSTR_NAME("test Eb Ib");
						
						IP.word+=2;
						AdjustIP(IP, modrm);
						ubyte imm8=CodeFetchB(0);
						ubyte temp=*source & imm8;
						TestVal(temp);
						
						FLAGS.CF=false;
						FLAGS.OF=false;
						IP.word+=1;
						
						break;
					}

					//asm: not 
				case 0x02:
					{
						//Instruction name
						INSTR_NAME("not Eb");
	
						//*source=~*source;
						*source=cast(ubyte)(~cast(int)*source);
						IP.word+=2;
						AdjustIP(IP, modrm);
						break;
					}
					
					//asm: neg
				case 0x03:
					{
						//Instruction name
						INSTR_NAME("neg Eb");
						
						*source=cast(ubyte)(-cast(int)*source);
						TestVal(*source);
						FLAGS.CF=(*source) ? true : false;

						IP.word+=2;
						AdjustIP(IP, modrm);
						break;
					}
					
					//asm: mul
				case 0x04:
					{
						//Instruction name
						INSTR_NAME("mul Eb");
						
						regs[REG_AX].word=regs[REG_AX].hfword[l]*(*source);
						
						bool ZFpre=FLAGS.ZF;
						TestVal(regs[REG_AX].word);
						FLAGS.ZF=ZFpre;
						if(!regs[REG_AX].hfword[h])
						{
							FLAGS.OF=false;
							FLAGS.CF=false;
						}
						else
						{
							FLAGS.OF=true;
							FLAGS.CF=true;
						}
						
						IP.word+=2;
						AdjustIP(IP, modrm);
						break;
					}
					
					//asm: imul
				case 0x05:
					{
						
						//Instruction name
						INSTR_NAME("imul Eb");
						int8_t imm8=cast(int8_t)CodeFetchB(0); // VERY TEST NEEDED 1/0
						
						regs[REG_AX].hfword[l]=cast(int8_t)(cast(uint8_t)regs[REG_AX].hfword[l]*imm8);
						if(regs[REG_AX].hfword[l]==regs[REG_AX].word)
						{
							FLAGS.CF=false;
							FLAGS.OF=false;
						}
						else
						{
							FLAGS.CF=true;
							FLAGS.OF=true;
						}
						
						IP.word+=2;
						AdjustIP(IP, modrm);
						break;
					}
					
					//asm: div
				case 0x06:
					{
						//Instruction name
						INSTR_NAME("div Eb");
						
						if(*source==0)
						{
							x86log.log("Divide exception!");
							RaiseInt(EXCEPTION_DIVIDE, prefixescount);
						}
						else
						{
							ubyte temp=*source;
							ushort tempax=regs[REG_AX].word;
							regs[REG_AX].hfword[l]=cast(ubyte)(tempax/temp);
							regs[REG_AX].hfword[h]=cast(ubyte)(tempax%temp);
							IP.word+=2;
							AdjustIP(IP, modrm);
						}
						break;
					}
					
					//asm: idiv
					//To-do: Test!
				case 0x07:
					{
						//Instruction name
						INSTR_NAME("idiv Eb");
						
						if(*source==0)
						{
							x86log.log("Divide exception!");
							RaiseInt(EXCEPTION_DIVIDE, prefixescount);
						}
						else
						{
							byte temp=cast(byte)(*source);
							short tempax=cast(short)(regs[REG_AX].word);
							regs[REG_AX].hfword[l]=cast(byte)(tempax/temp);
							regs[REG_AX].hfword[h]=cast(byte)(tempax%temp);
							IP.word+=2;
							AdjustIP(IP, modrm);
						}
						break;
					}
					// INVALID OPCODE!
				default:
					{
						x86instr.logf(format!"\nINVALID OPCODE!! OP:%02X GRP3a: %02X\n"(opcode, regfld));
						x86instr.logf(format!"CS=0x%04X IP=0x%04X\n"(CS.word, IP.word));
						RaiseInt(EXCEPTION_INVALIDOPCODE);
						break;
					}
				}
				break;
			}
			
			//asm: GRP3b
		case 0xF7:
			{
				//Retrieve operands
				uint16_t *dest; //Not used here
				uint16_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);

				uint8_t regfld=REG(modrm);
				switch(regfld)
				{
					//asm: test Eb Ib
				case 0x00:
				case 0x01: //http://ref.x86asm.net/coder32.html#gen_note_TEST_F6_1_F7_1
					{
						//Instruction name
						INSTR_NAME("test Eb Ib");
						
						IP.word+=2;
						AdjustIP(IP, modrm);
						ushort imm16=CodeFetchW(0);
						ushort temp=*source & imm16;
						TestVal(temp);
						
						FLAGS.CF=false;
						FLAGS.OF=false;
						IP.word+=2;
						
						break;
					}

					//asm: not 
				case 0x02:
					{
						//Instruction name
						INSTR_NAME("not Eb");
						
						//*source=~*source;
						*source=cast(ushort)(~cast(int)*source);
						IP.word+=2;
						AdjustIP(IP, modrm);
						break;
					}
					
					//asm: neg
				case 0x03:
					{
						//Instruction name
						INSTR_NAME("neg Eb");
						
						FLAGS.CF=(!*source) ? false : true;
						//*source=-*source;
						*source=cast(ushort)(-cast(int)*source);
						TestVal(*source);

						IP.word+=2;
						AdjustIP(IP, modrm);
						break;
					}
					
					//asm: mul
				case 0x04:
					{
						//Instruction name
						INSTR_NAME("mul Eb");
						
						uint32_t result=regs[REG_AX].word*(*source);
						
						regs[REG_AX].word=result&0xFFFF;
						regs[REG_DX].word=result>>16&0xFFFF;
						
						bool ZFpre=FLAGS.ZF;
						TestVal(cast(ushort)result);
						FLAGS.ZF=ZFpre;
						if(!regs[REG_DX].word)
						{
							FLAGS.OF=false;
							FLAGS.CF=false;
						}
						else
						{
							FLAGS.OF=true;
							FLAGS.CF=true;
						}
						
						IP.word+=2;
						AdjustIP(IP, modrm);
						break;
					}
					
					//asm: imul
				case 0x05:
					{
						
						//Instruction name
						INSTR_NAME("imul Eb");
						int8_t imm8=cast(int8_t)CodeFetchB(1);
						
						regs[REG_AX].hfword[l]=cast(int8_t)(cast(uint8_t)regs[REG_AX].hfword[l]*imm8);
						if(regs[REG_AX].hfword[l]==regs[REG_AX].word)
						{
							FLAGS.CF=false;
							FLAGS.OF=false;
						}
						else
						{
							FLAGS.CF=true;
							FLAGS.OF=true;
						}
						
						IP.word+=2;
						AdjustIP(IP, modrm);
						break;
					}
					
					//asm: div
				case 0x06:
					{
						//Instruction name
						INSTR_NAME("div Eb");
						
						uint32_t dx_ax=(regs[REG_DX].word<<16)+regs[REG_AX].word;

						if(*source==0)
						{
							RaiseInt(EXCEPTION_DIVIDE, prefixescount);
						}
						else
						{
							ushort temp=*source;
							regs[REG_AX].word=cast(ushort)(dx_ax/temp);
							regs[REG_DX].word=cast(ushort)(dx_ax%temp);
							IP.word+=2;
							AdjustIP(IP, modrm);
						}
						break;
					}
					
					//asm: idiv
					//To-do: Test!
				case 0x07:
					{
						//Instruction name
						INSTR_NAME("idiv Eb");
						
						int32_t dx_ax=(regs[REG_DX].word<<16)+regs[REG_AX].word;

						if(*source==0)
						{
							RaiseInt(EXCEPTION_DIVIDE, prefixescount);
						}
						else
						{
							short temp=cast(short)*(source);
							regs[REG_AX].word=cast(short)(dx_ax/temp);
							regs[REG_DX].word=cast(short)(dx_ax%temp);
							IP.word+=2;
							AdjustIP(IP, modrm);
						}
						
						break;
					}
					// INVALID OPCODE!
				default:
					{
						x86instr.logf(format!"\nINVALID OPCODE!! OP:%02X GRP3b: %02X\n"(opcode, regfld));
						x86instr.logf(format!"CS=0x%04X IP=0x%04X\n"(CS.word, IP.word));
						RaiseInt(EXCEPTION_INVALIDOPCODE);
						break;
					}
				}
				break;
			}
			
			//asm: 	clc
		case 0xF8:
			{
				//Instruction name
				INSTR_NAME("clc");
				
				FLAGS.CF=false;
				IP.word+=1;
				break;
			}
			
			//asm: 	stc
		case 0xF9:
			{
				//Instruction name
				INSTR_NAME("stc");
				
				FLAGS.CF=true;
				IP.word+=1;
				break;
			}
			
			//asm: 	cli
		case 0xFA:
			{
				//Instruction name
				INSTR_NAME("cli");
				
				FLAGS.IF=false;
				IP.word+=1;
				break;
			}
			
			//asm: 	sti
		case 0xFB:
			{
				//Instruction name
				INSTR_NAME("sti");
				
				FLAGS.IF=true;
				IP.word+=1;
				break;
			}
			
			//asm: 	cld
		case 0xFC:
			{
				//Instruction name
				INSTR_NAME("cld");
				
				FLAGS.DF=false;
				IP.word+=1;
				break;
			}
			
			//asm: 	std
		case 0xFD:
			{
				//Instruction name
				INSTR_NAME("std");
				
				FLAGS.DF=true;
				IP.word+=1;
				break;
			}
			
			//asm: GRP4
		case 0xFE:
			{				
				//Retrieve operands
				uint8_t *dest; //Not used here
				uint8_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);

				uint8_t regfld=REG(modrm);
				switch(regfld)
				{
					//asm: inc
				case 0x00: 
					{
						//Instruction name
						INSTR_NAME("inc r/m8");
						
						bool preCF=FLAGS.CF;
						CheckAdd8(*source, 1);
						*source+=1;
						FLAGS.CF=preCF;
						TestVal(*source);
						
						IP.word+=2;
						AdjustIP(IP, modrm);
						break;
					}
					
					//asm: dec
				case 0x01:
					{
						//Instruction name
						INSTR_NAME("dec r/m8");
						
						bool preCF=FLAGS.CF;
						CheckSub8(*source, 1);
						*source-=1;
						FLAGS.CF=preCF;
						TestVal(*source);
						
						IP.word+=2;
						AdjustIP(IP, modrm);
						break;
					}
					// INVALID OPCODE!
				default:
					{
						x86instr.logf(format!"\nINVALID OPCODE!! OP:%02X GRP4: %02X\n"(opcode, regfld));
						x86instr.logf(format!"CS=0x%04X IP=0x%04X\n"(CS.word, IP.word));
						RaiseInt(EXCEPTION_INVALIDOPCODE);
						break;
					}
				}
				break;
			}
			
			//asm: GRP5
		case 0xFF:
			{
				
				//Retrieve operands
				uint16_t *dest; //Not used here
				uint16_t *source;
				SetupOperands(modrm, opcode, CodeFetchW(2), cast(void**)&dest, cast(void**)&source, currsegment);

				uint8_t regfld=REG(modrm);
				switch(regfld)
				{
					//asm: inc
				case 0x00: 
					{
						//Instruction name
						INSTR_NAME("inc r/m16");
						
						bool preCF=FLAGS.CF;
						CheckAdd16(*source, 1);
						*source+=1;
						FLAGS.CF=preCF;
						TestVal(*source);
						
						IP.word+=2;
						AdjustIP(IP, modrm);
						break;
					}
					
					//asm: dec
				case 0x01:
					{
						//Instruction name
						INSTR_NAME("dec r/m16");
						
						bool preCF=FLAGS.CF;
						CheckSub16(*source, 1);
						*source-=1;
						FLAGS.CF=preCF;
						TestVal(*source);
						
						IP.word+=2;
						AdjustIP(IP, modrm);
						break;
					}
					
					//asm: call
				case 0x02:
					{
						//Instruction name
						INSTR_NAME("call r/m16");
						IP.word+=2;
						AdjustIP(IP, modrm);
						push16(IP.word);
						IP.word=*source;
						break;
					}
					
					//asm: call far
					//To-do: Check if working correctly
				case 0x03:
					{
						INSTR_NAME("call Mp");
						
						//Retrieve operands
						Pointer8086_32bit* target=cast(Pointer8086_32bit*)source;
						
						IP.word+=2;
						AdjustIP(IP, modrm);
						push16(CS.word);
						push16(IP.word);
						CS.word=target.highpart;
						IP.word=target.lowpart;
						break;
					}
					
					//asm: JMP absolute
				case 0x04:
					{
						//Instruction name
						INSTR_NAME("jmp absolute");
						
						IP.word=*source;
						break;
					}
					
					//asm: jmp far
				case 0x05:
					{
						//Instruction name
						INSTR_NAME("jmp Mp");
						
						Pointer8086_32bit* target=cast(Pointer8086_32bit*)source;
						
						CS.word=target.highpart;
						IP.word=target.lowpart;
						break;
					}
					
					//asm: push r/m16
				case 0x06:
					{
						//Instruction name
						INSTR_NAME("push r/m16");
						
						push16(*source);
						IP.word+=2;
						AdjustIP(IP, modrm);
						break;
					}
				default:
					{
						x86instr.logf(format!"\nINVALID OPCODE!! OP:%02X GRP5: %02X"(opcode, regfld));
						x86instr.logf(format!"\nCS=0x%04X IP=0x%04X"(CS.word, IP.word));
						x86instr.logf("\nADJUSTING IP!\n");
						RaiseInt(EXCEPTION_INVALIDOPCODE);
						break;
					}
				}
				break;
			}

		default:
			{
				//Signal interrupt!
				x86instr.logf(format!"\nINVALID OPCODE!! 0x%02X\n"(opcode));
				x86instr.logf(format!"CS=0x%04X IP=0x%04X\n"(CS.word, IP.word));
				RaiseInt(EXCEPTION_INVALIDOPCODE);
				break;
			}
		}
		if(logeveryinstruction && GetIP()!=prevIP)
		{
			x86instr.logf(format!"\n============================================================\nInstruction executed: %s\nLength: %s\nOld IP: 0x%04X\nNew IP: 0x%04X\nPrefix: %s\nPrefix count: %s"(GetInstructionNameLast(), GetIP-prevIP, prevIP, GetIP(), rep, prefixescount));
			DumpCPUStateToInstFile();
			x86instr.logf(format!"\nStack content, relative to SP:\n[SP+8]\t0x%04X\n[SP+6]\t0x%04X\n[SP+4]\t0x%04X\n[SP+2]\t0x%04X\n[SP]\t0x%04X\n[SP-2]\t0x%04X\n[SP-4]\t0x%04X\n[SP-6]\t0x%04X\n[SP-8]\t0x%04X"(RAM.ReadMemory16(SS.word, cast(ushort)(regs[REG_SP].word+8)), RAM.ReadMemory16(SS.word, cast(ushort)(regs[REG_SP].word+6)), RAM.ReadMemory16(SS.word, cast(ushort)(regs[REG_SP].word+4)), RAM.ReadMemory16(SS.word, cast(ushort)(regs[REG_SP].word+2)), RAM.ReadMemory16(SS.word, regs[REG_SP].word), RAM.ReadMemory16(SS.word, cast(ushort)(regs[REG_SP].word-2)), RAM.ReadMemory16(SS.word, cast(ushort)(regs[REG_SP].word-4)), RAM.ReadMemory16(SS.word, cast(ushort)(regs[REG_SP].word-6)), RAM.ReadMemory16(SS.word, cast(ushort)(regs[REG_SP].word-8))));
			x86instr.logf(format!"\nStack content, relative to BP:\n[BP+8]\t0x%04X\n[BP+6]\t0x%04X\n[BP+4]\t0x%04X\n[BP+2]\t0x%04X\n[BP]\t0x%04X\n[BP-2]\t0x%04X\n[BP-4]\t0x%04X\n[BP-6]\t0x%04X\n[BP-8]\t0x%04X"(RAM.ReadMemory16(SS.word, cast(ushort)(regs[REG_BP].word+8)), RAM.ReadMemory16(SS.word, cast(ushort)(regs[REG_BP].word+6)), RAM.ReadMemory16(SS.word, cast(ushort)(regs[REG_BP].word+4)), RAM.ReadMemory16(SS.word, cast(ushort)(regs[REG_BP].word+2)), RAM.ReadMemory16(SS.word, regs[REG_BP].word), RAM.ReadMemory16(SS.word, cast(ushort)(regs[REG_BP].word-2)), RAM.ReadMemory16(SS.word, cast(ushort)(regs[REG_BP].word-4)), RAM.ReadMemory16(SS.word, cast(ushort)(regs[REG_BP].word-6)), RAM.ReadMemory16(SS.word, cast(ushort)(regs[REG_BP].word-8))));
			
			char* ds_si_str=cast(char*)RAM.GetAbsAddress8(DS.word, regs[REG_SI].word);
			char* es_di_str=cast(char*)RAM.GetAbsAddress8(ES.word, regs[REG_DI].word);
			char* ds_ax_str=cast(char*)RAM.GetAbsAddress8(DS.word, regs[REG_AX].word);
			
			if(ds_si_str!=null)
			{
				if(strlen(ds_si_str)<=max_str_lenght && strlen(ds_si_str))
				{
					x86instr.logf(format!"\nDS:SI: %s "(fromStringz(ds_si_str)));
				}
			}
			
			if(es_di_str!=null)
			{
				if(strlen(es_di_str)<=max_str_lenght && strlen(ds_si_str))
				{
					x86instr.logf(format!"\nES:DI: %s"(fromStringz(es_di_str)));
				}
			}
			
			if(ds_ax_str!=null)
			{
				if(strlen(ds_ax_str)<=max_str_lenght && strlen(ds_si_str))
				{
					x86instr.logf(format!"\nDS:AX: %s"(fromStringz(ds_ax_str)));
				}
			}
			
			x86instr.logf("\nBytes:");
			string formattedstring;
			for(ubyte i=0; i<GetIP-prevIP; i++)
			{
				if(i>20)
				{
					x86instr.logf("Too many bytes! Breaking...");
					break;
				}
				ubyte data=ExposeRam().ReadMemory8(prevCS, cast(ushort)(prevIP+i));
				formattedstring~= format!"%02X "(data);
			}
			if((GetIP-prevIP)!=0)
			{
				x86instr.log(formattedstring);
			}
		}
	}
	
	public void PrintStackToScreen()
	{
		writeln(format!"\nStack content, relative to SP:\n[SP+4]\t0x%04X\n[SP+2]\t0x%04X\n[SP]\t0x%04X\n[SP-2]\t0x%04X\n[SP-4]\t0x%04X"(RAM.ReadMemory16(SS.word, cast(ushort)(regs[REG_SP].word+4)), RAM.ReadMemory16(SS.word, cast(ushort)(regs[REG_SP].word+2)), RAM.ReadMemory16(SS.word, regs[REG_SP].word), RAM.ReadMemory16(SS.word, cast(ushort)(regs[REG_SP].word-2)), RAM.ReadMemory16(SS.word, cast(ushort)(regs[REG_SP].word-4))));
		writeln(format!"\nStack content, relative to BP:\n[BP+4]\t0x%04X\n[BP+2]\t0x%04X\n[BP]\t0x%04X\n[BP-2]\t0x%04X\n[BP-4]\t0x%04X"(RAM.ReadMemory16(SS.word, cast(ushort)(regs[REG_BP].word+4)), RAM.ReadMemory16(SS.word, cast(ushort)(regs[REG_BP].word+2)), RAM.ReadMemory16(SS.word, regs[REG_BP].word), RAM.ReadMemory16(SS.word, cast(ushort)(regs[REG_BP].word-2)), RAM.ReadMemory16(SS.word, cast(ushort)(regs[REG_BP].word-4))));
	}
	
	//Nothing to do here...
	void FPU_Instruction_Handler(ubyte opcode)
	{
		switch(opcode)
		{
			//asm: fninit
		case 0xDB:
			{
				IP.word+=2;
				break;
			}
			//asm: fnstcw
		case 0xD9:
			{
				IP.word+=2;
				break;
			}
		default:
			{
				break;
			}
		}
	}
	
	private void TestVal(uint8_t val)
	{
		FLAGS.ZF=(val==0x00);
		FLAGS.SF=(val>>7 & 0x1);
		
		FLAGS.PF=parity[val];
	}
	
	private void TestVal(uint16_t val)
	{
		FLAGS.ZF=(val==0x00);
		FLAGS.SF=val>>15 & 0x1;
		
		FLAGS.PF=parity[val&0xFF];
	}
	
	void CheckSub8(ubyte num1, ubyte num2, ubyte carry=0)
	{
		ushort result=cast(ushort)(cast(ushort)num1-cast(ushort)num2-cast(ushort)carry);
		if(result&0x100)
		{
			FLAGS.CF=true;
		}
		else
		{
			FLAGS.CF=false;
		}
		if(((result^num1)&(num1^num2)&0x80))
		{
			FLAGS.OF=true;
		}
		else
		{
			FLAGS.OF=false;
		}
		if((num1^num2^result)&0x10)
		{
			FLAGS.AF=true;
		}
		else
		{
			FLAGS.AF=false;
		}
	}
	
	void CheckSub16(ushort num1, ushort num2, ushort carry=0)
	{
		uint result=cast(uint)(cast(uint)num1-cast(uint)num2-cast(uint)carry);
		if(result&0x10000)
		{
			FLAGS.CF=true;
		}
		else
		{
			FLAGS.CF=false;
		}
		if(((result^num1)&(num1^num2)&0x8000))
		{
			FLAGS.OF=true;
		}
		else
		{
			FLAGS.OF=false;
		}
		if((num1^num2^result)&0x10)
		{
			FLAGS.AF=true;
		}
		else
		{
			FLAGS.AF=false;
		}
	}
	
	void CheckAdd8(ubyte num1, ubyte num2, ubyte carry=0)
	{
		ushort result=cast(ushort)(cast(ushort)num1+cast(ushort)num2+cast(ushort)carry);
		if(result&0x100)
		{
			FLAGS.CF=true;
		}
		else
		{
			FLAGS.CF=false;
		}
		if(((result^num1)&(result^num2)&0x80))
		{
			FLAGS.OF=true;
		}
		else
		{
			FLAGS.OF=false;
		}
		if((num1^num2^result)&0x10)
		{
			FLAGS.AF=true;
		}
		else
		{
			FLAGS.AF=false;
		}
	}
	
	void CheckAdd16(ushort num1, ushort num2, ushort carry=0)
	{
		uint result=cast(uint)(cast(uint)num1+cast(uint)num2+cast(uint)carry);
		if(result&0x10000)
		{
			FLAGS.CF=true;
		}
		else
		{
			FLAGS.CF=false;
		}
		if(((result^num1)&(result^num2)&0x8000))
		{
			FLAGS.OF=true;
		}
		else
		{
			FLAGS.OF=false;
		}
		if((num1^num2^result)&0x10)
		{
			FLAGS.AF=true;
		}
		else
		{
			FLAGS.AF=false;
		}
	}
	
	// Use only for loading ROM/RAM and DMA
	public ref MemoryX86 ExposeRam()
	{
		return RAM;
	}
	
	// Raise Interrupt
	private void RaiseInt(ubyte num, ubyte steps_back=0)
	{ 
		//Push necessary registers on stack
		push16(FLAGS.word);
		push16(CS.word);
		push16(cast(ushort)(IP.word-steps_back));
		
		//Disable interrupts and no single-stepping
		FLAGS.IF=false;
		FLAGS.TF=false;
		
		IP.word=RAM.ReadMemory16(0x0000, 0x0004*num);
		CS.word=RAM.ReadMemory16(0x0000, 0x0004*num+2);
	}
	
	// Raise Non-Maskable Interrupt
	private void RaiseNMI()
	{
		RaiseInt(EXCEPTION_NMI);
		NMIretawaiting=true;
	}
	
	//Public function for NMI
	public void SignalNMI()
	{
		RaiseNMI();
	}
	
	//Public function for interrupt
	public void SignalInt(ubyte num)
	{
		if(FLAGS.IF)
		{
			//x86instr.logf(format!"External interrupt: 0x%02X"(num));
			halted=false;
			RaiseInt(num);
		}
	}
	
	public void SignalReset()
	{
		// Set reset vector at 0xFFFF:0x0000, but
		// we now use 286 style reset vector 0xF000:0xFFF0
		CS.word=0xF000;
		IP.word=0xFFF0;
		
		// Set more registers
		SS.word=0x0000;
		//FLAGS.word=0xF000;
		FLAGS.word=0x0000;
		DS.word=0x000;
		ES.word=0x000;
		
		x86log.logf("Reset line is high! Processor was reset!");
	}
	
	public void SetInOutFunc(void delegate(ushort, ref ushort, bool) func)
	{
		inoutfunc=func;
	}
	
	public void SetVMHandler(void delegate(ProcessorX86) func)
	{
		VMInvokeHandler=func;
	}
	
	private void OutPort(ushort port, ushort data)
	{
		if(inoutfunc!=null) inoutfunc(port, data, false);
	}
	
	
	private ushort InPort(ushort port)
	{
		uint16_t data;
		if(inoutfunc!=null) inoutfunc(port, data, true);
		return data;
	}
	
	public uint16_t GetIP()
	{
		return IP.word;
	}
	
	public uint16_t GetCS()
	{
		return CS.word;
	}
	
	public void DumpCPUStateToConsole()
	{
		x86log.logf("CPU states:");
		x86log.logf("AX=0x%04X\tBX=0x%04X\tCX=0x%04X\tDX=0x%04X", regs[REG_AX].word, regs[REG_BX].word, regs[REG_CX].word, regs[REG_DX].word);
		x86log.logf("SI=0x%04X\tDI=0x%04X\tBP=0x%04X\tSP=0x%04X", regs[REG_SI].word, regs[REG_DI].word, regs[REG_BP].word, regs[REG_SP].word);
		x86log.logf("CS=0x%04X\tSS=0x%04X\tDS=0x%04X\tES=0x%04X", CS.word, SS.word, DS.word, ES.word);
		x86log.logf("IP=0x%04X", IP.word);
		x86log.logf("FLAGS=0x%04X", FLAGS.word);
		x86log.logf("CF=%s | PF=%s | AF=%s | ZF=%s | SF=%s\nTF=%s | IF=%s | DF=%s | OF=%s", cast(int)FLAGS.CF, cast(int)FLAGS.PF, cast(int)FLAGS.AF, cast(int)FLAGS.ZF, cast(int)FLAGS.SF, cast(int)FLAGS.TF, cast(int)FLAGS.IF, cast(int)FLAGS.DF, cast(int)FLAGS.OF);
	}
	
	public void DumpCPUStateToInstFile()
	{
		x86instr.logf(format!"\nCPU states:\nAX=0x%04X\tBX=0x%04X\tCX=0x%04X\tDX=0x%04X\nSI=0x%04X\tDI=0x%04X\tBP=0x%04X\tSP=0x%04X\nCS=0x%04X\tSS=0x%04X\tDS=0x%04X\tES=0x%04X\nIP=0x%04X\nFLAGS=0x%04X\nCF=%s | PF=%s | AF=%s | ZF=%s | SF=%s\nTF=%s | IF=%s | DF=%s | OF=%s"(regs[REG_AX].word, regs[REG_BX].word, regs[REG_CX].word, regs[REG_DX].word, regs[REG_SI].word, regs[REG_DI].word, regs[REG_BP].word, regs[REG_SP].word, CS.word, SS.word, DS.word, ES.word, IP.word, FLAGS.word, cast(int)FLAGS.CF, cast(int)FLAGS.PF, cast(int)FLAGS.AF, cast(int)FLAGS.ZF, cast(int)FLAGS.SF, cast(int)FLAGS.TF, cast(int)FLAGS.IF, cast(int)FLAGS.DF, cast(int)FLAGS.OF));
	}
	
	public void DumpCPUStateToScreen()
	{
		writefln("CPU states:");
		writefln("AX=0x%04X\tBX=0x%04X\tCX=0x%04X\tDX=0x%04X", regs[REG_AX].word, regs[REG_BX].word, regs[REG_CX].word, regs[REG_DX].word);
		writefln("SI=0x%04X\tDI=0x%04X\tBP=0x%04X\tSP=0x%04X", regs[REG_SI].word, regs[REG_DI].word, regs[REG_BP].word, regs[REG_SP].word);
		writefln("CS=0x%04X\tSS=0x%04X\tDS=0x%04X\tES=0x%04X", CS.word, SS.word, DS.word, ES.word);
		writefln("IP=0x%04X", IP.word);
		writefln("FLAGS=0x%04X", FLAGS.word);
		writefln("CF=%s | PF=%s | AF=%s | ZF=%s | SF=%s\nTF=%s | IF=%s | DF=%s | OF=%s", cast(int)FLAGS.CF, cast(int)FLAGS.PF, cast(int)FLAGS.AF, cast(int)FLAGS.ZF, cast(int)FLAGS.SF, cast(int)FLAGS.TF, cast(int)FLAGS.IF, cast(int)FLAGS.DF, cast(int)FLAGS.OF);
	}
	
	private void INSTR_NAME(string text)
	{
		lastinstructionname=text;
	}
	
	public string GetInstructionNameLast()
	{
		return lastinstructionname;
	}
	
	private uint8_t CodeFetchB(int32_t pos=0)
	{
		return RAM.ReadMemory8(CS.word, cast(ushort)(IP.word+pos));
	}
	
	private uint16_t CodeFetchW(int32_t pos=0)
	{
		return RAM.ReadMemory16(CS.word, cast(ushort)(IP.word+pos));
	}
	
	public void SetIP(uint16_t addr)
	{
		IP.word=addr;
	}
	
	public void SetInstructionLog(bool state)
	{
		logeveryinstruction=state;
	}
	
	public bool GetLogState()
	{
		return logeveryinstruction;
	}
	
	ref reg16 AX() {return regs[REG_AX];}
	
	ref reg16 BX() {return regs[REG_BX];}
	
	ref reg16 CX() {return regs[REG_CX];}
	
	ref reg16 DX() {return regs[REG_DX];}

	ref reg16 SI() {return regs[REG_SI];}
	
	ref reg16 DI() {return regs[REG_DI];}
	
	ref reg16 BP() {return regs[REG_BP];}
	
	ref reg16 SP() {return regs[REG_SP];}
	
	ref reg16 IP_reg() {return IP;}
	
	ref FLAGSreg16 FLAGS_reg() {return FLAGS;}
	
	ref reg16 CS_reg() {return CS;}
	
	ref reg16 DS_reg() {return DS;}
	
	ref reg16 SS_reg() {return SS;}
	
	ref reg16 ES_reg() {return ES;}
	
	public void SetLinearBreakpoint(ushort segment, ushort offset)
	{
		isexecbreakpointactive=true;
		BP_CS=segment;
		BP_IP=offset;
	}
	
	public bool InterruptsCanBeServiced()
	{
		return FLAGS.IF;
	}
	
	
	private
	{
		reg16[8] regs;

		reg16 CS;
		reg16 DS;
		reg16 SS;
		reg16 ES;
		
		FLAGSreg16 FLAGS;
		
		reg16 IP;
		
		MemoryX86 RAM;
		IBM_PC_COMPATIBLE machine;
		
		void delegate(ushort, ref ushort, bool) inoutfunc;
		void delegate(ProcessorX86) VMInvokeHandler;
		
		bool halted;
		
		bool NMIretawaiting;
		bool externalintr;
		bool logeveryinstruction;
		ubyte intr_number;
		
		ushort prevCS;
		ushort prevIP;
		
		ushort BP_CS;
		ushort BP_IP;
		bool isexecbreakpointactive;
		
		string lastinstructionname;
	}
}
