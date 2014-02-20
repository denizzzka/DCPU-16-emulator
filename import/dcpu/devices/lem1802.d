/**
Copyright: Copyright (c) 2013-2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/


module dcpu.devices.lem1802;

import anchovy.graphics.bitmap;

import dcpu.devices.idevice;
import dcpu.emulator;
import dcpu.dcpu;

@safe nothrow:

/++
 + NE_LEM1802 v1.0
 + Low Energy Monitor
 + See 'docs/LEM1802 monitor.txt' for specification.
 +/

class Lem1802 : IDevice
{
protected:
	Dcpu* _dcpu;
	Bitmap _bitmap;

	ushort fontAddress;
	ushort videoAddress;
	ushort paletteAddress;
	ushort borderColor;

	bool blinkPhase;

	enum numRows = 12;
	enum numCols = 32;
	enum charWidth = 4;
	enum charHeight = 8;
	enum borderSize = 4;
	enum screenWidth = numCols * charWidth + borderSize * 2;
	enum screenHeight = numRows * charHeight + borderSize * 2;

public:
	this()
	{
		_bitmap = new Bitmap(screenWidth, screenHeight, 4);
	}

	Bitmap bitmap() @property
	{
		return _bitmap;
	}

	override void attachDcpu(Dcpu* dcpu)
	{
		_dcpu = dcpu;
	}

	/// Handles hardware interrupt and returns a number of cycles.
	override uint handleInterrupt(ref Emulator emulator)
	{
		ushort aRegister = emulator.dcpu.reg[0]; // A register
		ushort bRegister = emulator.dcpu.reg[1]; // B register

		switch(aRegister)
		{
			case 0:
				mapScreen(bRegister);
				return 0;
			case 1:
				mapFont(bRegister);
				return 0;
			case 2:
				mapPalette(bRegister);
				return 0;
			case 3:
				setBorderColor(bRegister);
				return 0;
			case 4:
				dumpFont(bRegister);
				return 256;
			case 5:
				dumpPalette(bRegister);
				return 16;
			default:
				break;
		}

		return 0;
	}

	/// Called every application frame.
	/// Can be used to update screens.
	override void update()
	{
		drawScreen();
	}

	/// Returns: 32 bit word identifying the hardware id.
	override uint hardwareId() @property
	{
		return 0x7349f615;
	}

	/// Returns: 16 bit word identifying the hardware version.
	override ushort hardwareVersion() @property
	{
		return 0x1802;
	}

	/// Returns: 32 bit word identifying the manufacturer
	override uint manufacturer() @property
	{
		return 0x1c6c8b36;
	}

protected:

	void drawScreen()
	{
		if (_dcpu is null) return;

		foreach(line; 0..numRows)
		{
			foreach(column; 0..numCols)
			{
				ushort memoryAddress = (videoAddress + line * numCols + column) & 0xFFFF;
				drawChar(_dcpu.mem[memoryAddress], column, line);
			}
		}

		_bitmap.dataChanged.emit();
	}

	void drawChar(ushort charData, size_t x, size_t y)
	{
		uint charIndex = charData & 0x7F;
		bool blinkBit  = (charData & 0x80) > 0;
		uint foreIndex = (charData & 0xF000) >> 12;
		uint backIndex = (charData & 0xF00) >> 8;

		ushort foreColor;
		ushort backColor;

		if (paletteAddress == 0)
		{
			foreColor = defaultPalette[foreIndex];
			backColor = defaultPalette[backIndex];
		}
		else
		{
			foreColor = _dcpu.mem[(paletteAddress + foreIndex) & 0xFFFF];
			backColor = _dcpu.mem[(paletteAddress + backIndex) & 0xFFFF];
		}

		uint foreRGB = ((foreColor & 0xF) << 16) * 17 +
						((foreColor & 0xF0) << 4) * 17 +
						((foreColor & 0xF00) >> 8) * 17 +
						0xFF000000;
		uint backRGB = ((backColor & 0xF) << 16) * 17 +
						((backColor & 0xF0) << 4) * 17 +
						((backColor & 0xF00) >> 8) * 17 +
						0xFF000000;

		if (blinkBit && blinkPhase)
		{
			fillCell(x, y, backRGB);
		}
		else
		{
			drawCell(x, y, foreRGB, backRGB, charIndex);
		}

		drawBorder();
	}

	void fillCell(size_t x, size_t y, uint color)
	{
		
	}

	void drawCell(size_t x, size_t y, uint foreColor, uint backColor, uint charIndex)
	{

	}

	void drawBorder()
	{

	}

	void mapScreen(ushort b)
	{

	}

	void mapFont(ushort b)
	{

	}

	void mapPalette(ushort b)
	{
		
	}

	void setBorderColor(ushort b)
	{
		borderColor = b & 0xF;
	}

	void dumpFont(ushort b)
	{

	}

	void dumpPalette(ushort b)
	{
		
	}
}

static immutable ushort[] defaultPalette = [
	0x000, 0x00a, 0x0a0, 0x0aa,
	0xa00, 0xa0a, 0xa50, 0xaaa,
	0x555, 0x55f, 0x5f5, 0x5ff,
	0xf55, 0xf5f, 0xff5, 0xfff
];

static immutable ushort[] defaultFont = [
	0xb79e, 0x388e, 0x722c, 0x75f4, 0x19bb, 0x7f8f, 0x85f9, 0xb158,
	0x242e, 0x2400, 0x082a, 0x0800, 0x0008, 0x0000, 0x0808, 0x0808,
	0x00ff, 0x0000, 0x00f8, 0x0808, 0x08f8, 0x0000, 0x080f, 0x0000,
	0x000f, 0x0808, 0x00ff, 0x0808, 0x08f8, 0x0808, 0x08ff, 0x0000,
	0x080f, 0x0808, 0x08ff, 0x0808, 0x6633, 0x99cc, 0x9933, 0x66cc,
	0xfef8, 0xe080, 0x7f1f, 0x0701, 0x0107, 0x1f7f, 0x80e0, 0xf8fe,
	0x5500, 0xaa00, 0x55aa, 0x55aa, 0xffaa, 0xff55, 0x0f0f, 0x0f0f,
	0xf0f0, 0xf0f0, 0x0000, 0xffff, 0xffff, 0x0000, 0xffff, 0xffff,
	0x0000, 0x0000, 0x005f, 0x0000, 0x0300, 0x0300, 0x3e14, 0x3e00,
	0x266b, 0x3200, 0x611c, 0x4300, 0x3629, 0x7650, 0x0002, 0x0100,
	0x1c22, 0x4100, 0x4122, 0x1c00, 0x1408, 0x1400, 0x081c, 0x0800,
	0x4020, 0x0000, 0x0808, 0x0800, 0x0040, 0x0000, 0x601c, 0x0300,
	0x3e49, 0x3e00, 0x427f, 0x4000, 0x6259, 0x4600, 0x2249, 0x3600,
	0x0f08, 0x7f00, 0x2745, 0x3900, 0x3e49, 0x3200, 0x6119, 0x0700,
	0x3649, 0x3600, 0x2649, 0x3e00, 0x0024, 0x0000, 0x4024, 0x0000,
	0x0814, 0x2200, 0x1414, 0x1400, 0x2214, 0x0800, 0x0259, 0x0600,
	0x3e59, 0x5e00, 0x7e09, 0x7e00, 0x7f49, 0x3600, 0x3e41, 0x2200,
	0x7f41, 0x3e00, 0x7f49, 0x4100, 0x7f09, 0x0100, 0x3e41, 0x7a00,
	0x7f08, 0x7f00, 0x417f, 0x4100, 0x2040, 0x3f00, 0x7f08, 0x7700,
	0x7f40, 0x4000, 0x7f06, 0x7f00, 0x7f01, 0x7e00, 0x3e41, 0x3e00,
	0x7f09, 0x0600, 0x3e61, 0x7e00, 0x7f09, 0x7600, 0x2649, 0x3200,
	0x017f, 0x0100, 0x3f40, 0x7f00, 0x1f60, 0x1f00, 0x7f30, 0x7f00,
	0x7708, 0x7700, 0x0778, 0x0700, 0x7149, 0x4700, 0x007f, 0x4100,
	0x031c, 0x6000, 0x417f, 0x0000, 0x0201, 0x0200, 0x8080, 0x8000,
	0x0001, 0x0200, 0x2454, 0x7800, 0x7f44, 0x3800, 0x3844, 0x2800,
	0x3844, 0x7f00, 0x3854, 0x5800, 0x087e, 0x0900, 0x4854, 0x3c00,
	0x7f04, 0x7800, 0x047d, 0x0000, 0x2040, 0x3d00, 0x7f10, 0x6c00,
	0x017f, 0x0000, 0x7c18, 0x7c00, 0x7c04, 0x7800, 0x3844, 0x3800,
	0x7c14, 0x0800, 0x0814, 0x7c00, 0x7c04, 0x0800, 0x4854, 0x2400,
	0x043e, 0x4400, 0x3c40, 0x7c00, 0x1c60, 0x1c00, 0x7c30, 0x7c00,
	0x6c10, 0x6c00, 0x4c50, 0x3c00, 0x6454, 0x4c00, 0x0836, 0x4100,
	0x0077, 0x0000, 0x4136, 0x0800, 0x0201, 0x0201, 0x0205, 0x0200
];