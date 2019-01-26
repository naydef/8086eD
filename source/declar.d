module cpu.decl;

import std.bitmanip;
import core.bitop;

enum
{
	ES_SEGMENT=0,
	CS_SEGMENT,
	SS_SEGMENT,
	DS_SEGMENT,
	FS_SEGMENT, // For the future Intel 386 emulation
	GS_SEGMENT, // For the future Intel 386 emulation
	NO_SEGMENT,
};

enum
{
	REG_AX=0, //000b
	REG_CX=1, //001b
	REG_DX=2, //010b
	REG_BX=3, //011b
	REG_SP=4, //100b
	REG_BP=5, //101b
	REG_SI=6, //110b
	REG_DI=7, //111b
};

enum
{
	EXCEPTION_DIVIDE=0x00,
	EXCEPTION_SINGLESTEP=0x01,
	EXCEPTION_NMI=0x02,
	EXCEPTION_BREAKPOINT=0x03,
	EXCEPTION_OVERFLOW=0x04,
	EXCEPTION_BOUNDRAGEEXCEEEDED=0x05,
	EXCEPTION_INVALIDOPCODE=0x06,
};

enum
{
	CF=0x00,
	PF=0x02,
	AF=0x04,
	ZF=0x06,
	SF=0x07,
	TF=0x08,
	IF=0x09,
	DF=0x0A,
	OF=0x0B,
	B15=0x0F,
};

enum
{
	REP_PREFIX_NONE=0,
	REP_PREFIX_REPN=1,
	REP_PREFIX_REP=2,
	REP_PREFIX_REPE=2,
};

const int l=0;
const int h=1;

union reg16
{
	ushort word;
	ubyte[2] hfword;
	mixin(bitfields!(
	ubyte, "l", 8,
	ubyte, "h", 8));
	ushort w;
};

union FLAGSreg16
{
	ushort word;
	ubyte[2] hfword;
	mixin(bitfields!(
	bool, "CF", 1,
	bool, "", 1,
	bool, "PF", 1,
	bool, "", 1,
	bool, "AF", 1,
	bool, "", 1,
	bool, "ZF", 1,
	bool, "SF", 1,
	bool, "TF", 1,
	bool, "IF", 1,
	bool, "DF", 1,
	bool, "OF", 1,
	ubyte, "IOPL", 2,
	bool, "NT", 1,
	bool, "", 1));
};

immutable bool[0x100] parity = [
true, false, false, true, false, true, true, false,
false, true, true, false, true, false, false, true,
false, true, true, false, true, false, false, true,
true, false, false, true, false, true, true, false,
false, true, true, false, true, false, false, true,
true, false, false, true, false, true, true, false,
true, false, false, true, false, true, true, false,
false, true, true, false, true, false, false, true,
false, true, true, false, true, false, false, true,
true, false, false, true, false, true, true, false,
true, false, false, true, false, true, true, false,
false, true, true, false, true, false, false, true,
true, false, false, true, false, true, true, false,
false, true, true, false, true, false, false, true,
false, true, true, false, true, false, false, true,
true, false, false, true, false, true, true, false,
false, true, true, false, true, false, false, true,
true, false, false, true, false, true, true, false,
true, false, false, true, false, true, true, false,
false, true, true, false, true, false, false, true,
true, false, false, true, false, true, true, false,
false, true, true, false, true, false, false, true,
false, true, true, false, true, false, false, true,
true, false, false, true, false, true, true, false,
true, false, false, true, false, true, true, false,
false, true, true, false, true, false, false, true,
false, true, true, false, true, false, false, true,
true, false, false, true, false, true, true, false,
false, true, true, false, true, false, false, true,
true, false, false, true, false, true, true, false,
true, false, false, true, false, true, true, false,
false, true, true, false, true, false, false, true,
];