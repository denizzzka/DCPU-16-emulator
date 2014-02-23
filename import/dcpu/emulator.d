/**
Copyright: Copyright (c) 2013-2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/


module dcpu.emulator;

import dcpu.dcpu;
import std.conv : to;
import std.stdio;

import dcpu.devices.idevice;

//@safe nothrow:

/// Does actual interpreting of DCPU-16
public class Emulator
{
	Dcpu dcpu; /// data storage: memory, registers.

	void attachDevice(IDevice device)
	{
		dcpu.attachDevice(device);
		device.attachEmulator(this);
	}

	void loadProgram(ushort[] binary)
	{
		ushort size = binary.length & 0xFFFF;

		dcpu.mem[0..size] = binary[0..size];
	}

	/// Performs next instruction
	void step()
	{
		ulong initialCycles = dcpu.cycles;

		ushort instruction = dcpu.mem[dcpu.pc++];

		if ((instruction & 0x1F) != 0) //basic
		{
			basicInstruction(instruction);
		}
		else //special
		{
			specialInstruction(instruction);
		}

		// Handle interrupts only when interrupt queuing is disabled.
		// It may be enabled by interrupt handler or manually in time critical code.
		if (!dcpu.queueInterrupts)
		{
			handleInterrupt();
		}

		ulong diff = dcpu.cycles - initialCycles;

		dcpu.updateQueue.onTick(diff);
	}

	// Tries to do cyclesToStep cycles of dcpu.
	// Returns actual cycles done.
	ulong stepCycles(ulong cyclesToStep)
	{
		ulong initialCycles = dcpu.cycles;
		while(dcpu.cycles - initialCycles < cyclesToStep)
		{
			step();
		}

		return dcpu.cycles - initialCycles;
	}

	// Steps instructionsToStep instructions.
	void stepInstructions(ulong instructionsToStep)
	{
		foreach(_; 0..instructionsToStep)
			step();
	}

	/// Adds interrupt with message 'message' to dcpu.intQueue or starts burning DCPU if queue grows bigger than 256
	void triggerInterrupt(ushort message)
	{
		if (dcpu.intQueue.isFull)
		{
			dcpu.isBurning = true;
		}
		else
		{
			dcpu.intQueue.add(message);
		}
	}

	/// Resets dcpu state and interpreter state to their initial state.
	void reset()
	{
		dcpu.reset();
	}

private:

	/// Performs basic instruction.
	void basicInstruction(ushort instruction)
	{
		ushort opcode = instruction & 0x1F;

		ushort a = *getOperand!true(instruction >> 10); // a

		ushort destinationType = (instruction >> 5) & 0x1F;
		ushort* destination = getOperand!false(destinationType); // b
		ushort  b = *destination;

		uint result;

		dcpu.cycles += basicCycles[opcode];

		with(dcpu) switch (opcode)
		{
			case 0x00 : assert(false); // Special opcode. Execution never goes here.
			case SET: result = a; break;
			case ADD: result = b + a; ex = result >> 16; break;
			case SUB: result = b - a; ex = (a > b) ? 0xFFFF : 0; break;
			case MUL: result = b * a; ex = result >> 16; break;
			case MLI: result = cast(short)a * cast(short)b; ex = result >> 16; break;
			case DIV: if (a==0){ex = 0; result = 0;}
						else {result = b/a; ex = ((b << 16)/a) & 0xffff;} break; // TODO:test
			case DVI: if (a==0){ex = 0; result = 0;}
						else {
							result = cast(short)b/cast(short)a;
							ex = ((cast(short)b << 16)/cast(short)a) & 0xffff;
						} break; // TODO:test
			case MOD: result = a == 0 ? 0 : b % a; break;
			case MDI: result = a == 0 ? 0 : cast(short)b % cast(short)a; break;
			case AND: result = a & b; break;
			case BOR: result = a | b; break;
			case XOR: result = a ^ b; break;
			case SHR: result = b >> a; ex = ((b<<16)>>a) & 0xffff; break;
			case ASR: result = cast(short)b >>> a;
						ex = ((b<<16)>>>a) & 0xffff; break;
			case SHL: result = b << a; ex = ((b<<a)>>16) & 0xffff; break;
			case IFB: if ((b & a)==0) skipIfs(); return; // TODO:test
			case IFC: if ((b & a)!=0) skipIfs(); return; // TODO:test
			case IFE: if (b != a) skipIfs(); return; // TODO:test
			case IFN: if (b == a) skipIfs(); return; // TODO:test
			case IFG: if (b <= a) skipIfs(); return; // TODO:test
			case IFA: if (cast(short)b <= cast(short)a) skipIfs(); return; // TODO:test
			case IFL: if (b >= a) skipIfs(); return; // TODO:test
			case IFU: if (cast(short)b >= cast(short)a) skipIfs(); return; // TODO:test
			case ADX: result = b + a + ex;
						ex = result >> 16 ? 1 : 0; break;
			case SBX: result = b - a + ex; ex = 0;
						if (ushort over = result >> 16)
							ex = over == 0xFFFF ? 0xFFFF : 0x0001;
						break;
			case STI: result = a; ++reg[6]; ++reg[7]; break;
			case STD: result = a; --reg[6]; --reg[7]; break;
			default: ;//writeln("Unknown instruction " ~ to!string(opcode)); //Invalid opcode
		}

		if (destinationType < 0x1F)
		{
			*destination = result & 0xFFFF;
		}
		//else Attempting to write to a literal
	}

	/// Performs special instruction.
	void specialInstruction(ushort instruction)
	{
		ushort* a = getOperand!true(instruction >> 10);

		ushort opcode = (instruction >> 5) & 0x1F;

		with(dcpu) switch (opcode)
		{
			case JSR: push(pc); pc = *a; break;
			case INT: triggerInterrupt(*a); break;
			case IAG: *a = ia; break;
			case IAS: ia = *a; break;
			case RFI: queueInterrupts = false;
						reg[0] = pop();
						pc = pop();
						break;
			case IAQ: queueInterrupts = *a > 0; break;
			case HWN: *a = numDevices; writefln("numDevices %s", numDevices);break;
			case HWQ: queryHardwareInfo(*a); break;
			case HWI: sendHardwareInterrupt(*a); break;
			default : ;//writeln("Unknown instruction " ~ to!string(opcode));
		}
	}

	/// Pushes value onto stack increasing SP.
	void push(ushort value)
	{
		dcpu.mem[--dcpu.sp] = value;
	}

	/// Pops value from stack decreasing SP.
	ushort pop()
	{
		return dcpu.mem[++dcpu.sp];
	}

	/// Sets A, B, C, X, Y registers to information about hardware deviceIndex
	void queryHardwareInfo(ushort deviceIndex)
	{
		if (auto device = deviceIndex in dcpu.devices)
		{
			cast(uint[1])dcpu.reg[0..2] = device.hardwareId;
			dcpu.reg[2] = device.hardwareVersion;
			cast(uint[1])dcpu.reg[3..5] = device.manufacturer;
		}
		else
		{
			dcpu.reg[0..5] = 0;
		}
	}

	/// Sends an interrupt to hardware deviceIndex
	void sendHardwareInterrupt(ushort deviceIndex)
	{
		if (auto device = deviceIndex in dcpu.devices)
		{
			dcpu.cycles += device.handleInterrupt(this);
		}
	}

	/// Handles interrupt from interrupt queue if IA != 0 && intQueue.length > 0
	void handleInterrupt()
	{
		if (dcpu.intQueue.size == 0) return;

		ushort message = dcpu.intQueue.take();

		if (dcpu.ia != 0)
		{
			dcpu.queueInterrupts = true;

			push(dcpu.pc);
			push(dcpu.reg[0]);

			dcpu.pc = dcpu.ia;
			dcpu.reg[0] = message;
		}
	}

	/++
	+ Skips instructions if conditional opcode was failed.
	+
	+ The conditional opcodes take one cycle longer to perform if the test fails.
  	+ When they skip a conditional instruction, they will skip an additional
  	+ instruction at the cost of one extra cycle. This continues until a non-
  	+ conditional instruction has been skipped. This lets you easily chain
  	+ conditionals. Interrupts are not triggered while the DCPU-16 is skipping.
	+/
	void skipIfs()
	{
		while ((dcpu.mem[dcpu.pc] & 0x1f) >= IFB && (dcpu.mem[dcpu.pc] & 0x1f) <= IFU)
		{
			skip();
		}

		skip();
	}

	void skip()
	{
		ulong cycles = dcpu.cycles;
		ushort instr = dcpu.mem[dcpu.pc++];
		ushort opcode = instr & 0x1f;

		if (opcode != 0) //basic
		{
			getOperand!true(instr >> 10);
			getOperand!false((instr >> 5) & 0x1F);
		}
		else //special
		{
			getOperand!true(instr >> 10);
		}			

		dcpu.cycles = cycles + 1;
	}

	/// Extracts operand from an instruction
	ushort* getOperand(bool isA)(ushort instr)
	in
	{
		assert(instr <= 0x3f, "operand must be lower than 0x40");
		static if (!isA)
			assert(instr <= 0x1f);
	}
	body
	{
		with(dcpu) switch(instr)
		{
			case 0x00: .. case 0x07: // register
				return &reg[instr];
			case 0x08: .. case 0x0f: // [register]
				return &mem[reg[instr & 7]];
			case 0x10: .. case 0x17: // [register + next word]
				++dcpu.cycles;
				return &mem[(reg[instr & 7] + mem[pc++]) & 0xffff];
			case 0x18: // PUSH / POP
				static if (isA)
					return &mem[sp++];
				else
					return &mem[--sp];
			case 0x19: // [SP] / PEEK
				return &mem[sp];
			case 0x1a: // [SP + next word]
				++dcpu.cycles;
				return &mem[cast(ushort)(sp + pc++)];
			case 0x1b: // SP
				return &sp;
			case 0x1c: // PC
				return &pc;
			case 0x1d: // EX
				return &ex;
			case 0x1e: // [next word]
				++dcpu.cycles;
				return &mem[mem[pc++]];
			case 0x1f: // next word
				++dcpu.cycles;
				return &mem[pc++];
			default: // 0xffff-0x1e (-1..30) (literal) (only for a)
				return &literals[instr & 0x1F];
		}
	}
}

/// Table of literal values which may be stored in 'a' operand.
private static ushort[0x20] literals =
	[0xFFFF, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06,
	 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E,
	 0x0F, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16,
	 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E];

/// Table of basic instructions cost.
private static immutable ubyte[] basicCycles = 
	[0, 1, 2, 2, 2, 2, 3, 3, 3, 3, 1, 1, 1, 1, 1, 1,
	 2, 2, 2, 2, 2, 2, 2, 2, 0, 0, 3, 3, 0, 0, 2, 2];

/// Table of special instructions cost.
private static immutable ubyte[] specialCycles = 
	[0, 3, 0, 0, 0, 0, 0, 0, 4, 1, 1, 3, 2, 0, 0, 0,
	 2, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

// Enums for opcodes. Just a bit of self documented code.
private enum {SET = 0x01, ADD, SUB, MUL, MLI, DIV, DVI, MOD, MDI, AND, BOR, XOR, SHR, ASR,
			SHL, IFB, IFC, IFE, IFN, IFG, IFA, IFL, IFU, ADX = 0x1a, SBX, STI = 0x1e, STD}
private enum {JSR = 0x01, INT = 0x08, IAG, IAS, RFI, IAQ, HWN = 0x10, HWQ, HWI}