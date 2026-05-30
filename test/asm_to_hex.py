#!/usr/bin/env python3
"""Simple RISC-V assembler for creating directed test hex files.
Supports rv32i base integer instructions needed for P5a testing.
Usage: python asm_to_hex.py <input.asm> <output.hex>
"""

import sys
import struct

# Register name → number mapping
REGS = {
    'x0': 0, 'zero': 0,
    'x1': 1, 'ra': 1,
    'x2': 2, 'sp': 2,
    'x3': 3, 'gp': 3,
    'x4': 4, 'tp': 4,
    'x5': 5, 't0': 5,
    'x6': 6, 't1': 6,
    'x7': 7, 't2': 7,
    'x8': 8, 's0': 8, 'fp': 8,
    'x9': 9, 's1': 9,
    'x10': 10, 'a0': 10,
    'x11': 11, 'a1': 11,
    'x12': 12, 'a2': 12,
    'x13': 13, 'a3': 13,
    'x14': 14, 'a4': 14,
    'x15': 15, 'a5': 15,
    'x16': 16, 'a6': 16,
    'x17': 17, 'a7': 17,
    'x18': 18, 's2': 18,
    'x19': 19, 's3': 19,
    'x20': 20, 's4': 20,
    'x21': 21, 's5': 21,
    'x22': 22, 's6': 22,
    'x23': 23, 's7': 23,
    'x24': 24, 's8': 24,
    'x25': 25, 's9': 25,
    'x26': 26, 's10': 26,
    'x27': 27, 's11': 27,
    'x28': 28, 't3': 28,
    'x29': 29, 't4': 29,
    'x30': 30, 't5': 30,
    'x31': 31, 't6': 31,
}

# Opcodes
OP_IMM  = 0b0010011  # ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI
OP_IMM_32 = 0b0011011
OP      = 0b0110011  # ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND
LUI     = 0b0110111
AUIPC   = 0b0010111
OP_BR   = 0b1100011  # BEQ, BNE, BLT, BGE, BLTU, BGEU
JAL     = 0b1101111
JALR    = 0b1100111
LOAD    = 0b0000011  # LW, LH, LB, LHU, LBU
STORE   = 0b0100011  # SW, SH, SB
SYSTEM  = 0b1110011  # ECALL, EBREAK
FENCE   = 0b0001111

# Funct3
F3_ADD  = 0b000  # ADD/SUB/MUL
F3_SLL  = 0b001
F3_SLT  = 0b010
F3_SLTU = 0b011
F3_XOR  = 0b100
F3_SRL  = 0b101  # SRL/SRA/DIV
F3_OR   = 0b110
F3_AND  = 0b111

F3_BEQ  = 0b000
F3_BNE  = 0b001
F3_BLT  = 0b100
F3_BGE  = 0b101
F3_BLTU = 0b110
F3_BGEU = 0b111

F3_LW   = 0b010
F3_LH   = 0b001
F3_LB   = 0b000
F3_LHU  = 0b101
F3_LBU  = 0b100

F3_SW   = 0b010
F3_SH   = 0b001
F3_SB   = 0b000

F3_JALR = 0b000

# Funct7
F7_ADD  = 0b0000000
F7_SUB  = 0b0100000
F7_SRL  = 0b0000000
F7_SRA  = 0b0100000


def parse_reg(s):
    s = s.strip().rstrip(',')
    if s in REGS:
        return REGS[s]
    raise ValueError(f"Unknown register: {s}")


def parse_imm(s):
    s = s.strip().rstrip(',')
    if s.startswith('0x'):
        return int(s, 16)
    elif s.startswith('0b'):
        return int(s, 2)
    else:
        return int(s, 10)


def sext(val, bits):
    """Sign-extend val to given bit width."""
    if val & (1 << (bits - 1)):
        return val - (1 << bits)
    return val


def encode_i(rd, rs1, imm12):
    """I-type: imm[11:0] | rs1 | funct3 | rd | opcode"""
    return ((imm12 & 0xFFF) << 20) | (rs1 << 15) | (rd << 7)


def encode_r(rd, rs1, rs2, funct3, funct7):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7)


def encode_b(rs1, rs2, imm13):
    """B-type immediate is scrambled:
    inst[31]=imm[12], inst[30:25]=imm[10:5], inst[11:8]=imm[4:1], inst[7]=imm[11]
    """
    b_imm = imm13 & 0x1FFF  # 13-bit signed
    bits = (
        ((b_imm >> 12) & 0x1) << 31 |
        ((b_imm >> 5) & 0x3F) << 25 |
        (rs2 << 20) |
        (rs1 << 15) |
        ((b_imm >> 1) & 0xF) << 8 |
        ((b_imm >> 11) & 0x1) << 7
    )
    return bits


def encode_u(rd, imm32):
    """U-type: imm[31:12] | rd[11:7] | opcode"""
    return (imm32 & 0xFFFFF000) | (rd << 7)


def encode_j(rd, imm21):
    """J-type immediate is scrambled:
    inst[31]=imm[20], inst[30:21]=imm[10:1], inst[20]=imm[11],
    inst[19:12]=imm[19:12], inst[11:7]=rd, inst[6:0]=opcode
    """
    j_imm = imm21 & 0x1FFFFF
    bits = (
        ((j_imm >> 20) & 0x1) << 31 |
        ((j_imm >> 1) & 0x3FF) << 21 |
        ((j_imm >> 11) & 0x1) << 20 |
        ((j_imm >> 12) & 0xFF) << 12 |
        (rd << 7)
    )
    return bits


class Assembler:
    def __init__(self, start_addr=0x80000000):
        self.start_addr = start_addr
        self.instructions = []
        self.labels = {}
        self.current_addr = start_addr

    def parse_line(self, line):
        """Parse one line of assembly. Returns (label, mnemonic, args) or None."""
        line = line.split('#')[0].strip()
        if not line:
            return None

        # Check for label
        if ':' in line:
            label, rest = line.split(':', 1)
            label = label.strip()
            rest = rest.strip()
            if not rest:
                return (label, None, None)
            line = rest

        parts = line.replace(',', ' ').split()
        if not parts:
            return None

        mnemonic = parts[0].lower()
        args = parts[1:] if len(parts) > 1 else []
        return (None, mnemonic, args)

    def assemble_inst(self, mnemonic, args, addr):
        """Assemble one instruction. Returns 32-bit instruction word."""
        a = args

        # === R-type ===
        if mnemonic == 'add':
            return encode_r(parse_reg(a[0]), parse_reg(a[1]), parse_reg(a[2]), F3_ADD, F7_ADD) | OP
        elif mnemonic == 'sub':
            return encode_r(parse_reg(a[0]), parse_reg(a[1]), parse_reg(a[2]), F3_ADD, F7_SUB) | OP
        elif mnemonic == 'sll':
            return encode_r(parse_reg(a[0]), parse_reg(a[1]), parse_reg(a[2]), F3_SLL, 0) | OP
        elif mnemonic == 'slt':
            return encode_r(parse_reg(a[0]), parse_reg(a[1]), parse_reg(a[2]), F3_SLT, 0) | OP
        elif mnemonic == 'sltu':
            return encode_r(parse_reg(a[0]), parse_reg(a[1]), parse_reg(a[2]), F3_SLTU, 0) | OP
        elif mnemonic == 'xor':
            return encode_r(parse_reg(a[0]), parse_reg(a[1]), parse_reg(a[2]), F3_XOR, 0) | OP
        elif mnemonic == 'srl':
            return encode_r(parse_reg(a[0]), parse_reg(a[1]), parse_reg(a[2]), F3_SRL, 0) | OP
        elif mnemonic == 'sra':
            return encode_r(parse_reg(a[0]), parse_reg(a[1]), parse_reg(a[2]), F3_SRL, F7_SRA) | OP
        elif mnemonic == 'or':
            return encode_r(parse_reg(a[0]), parse_reg(a[1]), parse_reg(a[2]), F3_OR, 0) | OP
        elif mnemonic == 'and':
            return encode_r(parse_reg(a[0]), parse_reg(a[1]), parse_reg(a[2]), F3_AND, 0) | OP

        # === I-type ALU ===
        elif mnemonic == 'addi':
            return encode_i(parse_reg(a[0]), parse_reg(a[1]), parse_imm(a[2])) | (F3_ADD << 12) | OP_IMM
        elif mnemonic == 'slti':
            return encode_i(parse_reg(a[0]), parse_reg(a[1]), parse_imm(a[2])) | (F3_SLT << 12) | OP_IMM
        elif mnemonic == 'sltiu':
            return encode_i(parse_reg(a[0]), parse_reg(a[1]), parse_imm(a[2])) | (F3_SLTU << 12) | OP_IMM
        elif mnemonic == 'xori':
            return encode_i(parse_reg(a[0]), parse_reg(a[1]), parse_imm(a[2])) | (F3_XOR << 12) | OP_IMM
        elif mnemonic == 'ori':
            return encode_i(parse_reg(a[0]), parse_reg(a[1]), parse_imm(a[2])) | (F3_OR << 12) | OP_IMM
        elif mnemonic == 'andi':
            return encode_i(parse_reg(a[0]), parse_reg(a[1]), parse_imm(a[2])) | (F3_AND << 12) | OP_IMM
        elif mnemonic == 'slli':
            imm = parse_imm(a[2]) & 0x1F
            return ((0 << 26) | (imm << 20) | (parse_reg(a[1]) << 15) | (F3_SLL << 12) | (parse_reg(a[0]) << 7) | OP_IMM)
        elif mnemonic == 'srli':
            imm = parse_imm(a[2]) & 0x1F
            return ((0 << 26) | (imm << 20) | (parse_reg(a[1]) << 15) | (F3_SRL << 12) | (parse_reg(a[0]) << 7) | OP_IMM)
        elif mnemonic == 'srai':
            imm = parse_imm(a[2]) & 0x1F
            return ((0b0100000 << 26) | (imm << 20) | (parse_reg(a[1]) << 15) | (F3_SRL << 12) | (parse_reg(a[0]) << 7) | OP_IMM)

        # === I-type Load ===
        elif mnemonic == 'lw':
            imm = parse_imm(a[1])
            return encode_i(parse_reg(a[0]), parse_reg(a[1].split('(')[1].rstrip(')')), imm) | (F3_LW << 12) | LOAD

        # === JALR ===
        elif mnemonic == 'jalr':
            # jalr rd, imm(rs1)
            if '(' in a[1]:
                imm_str, rs1_str = a[1].split('(')
                rs1_str = rs1_str.rstrip(')')
                return encode_i(parse_reg(a[0]), parse_reg(rs1_str), parse_imm(imm_str)) | (F3_JALR << 12) | JALR
            else:
                return encode_i(parse_reg(a[0]), parse_reg(a[1]), parse_imm(a[2])) | (F3_JALR << 12) | JALR

        # === B-type ===
        elif mnemonic in ('beq', 'bne', 'blt', 'bge', 'bltu', 'bgeu'):
            rs1 = parse_reg(a[0])
            rs2 = parse_reg(a[1])
            target = a[2]
            if target in self.labels:
                offset = self.labels[target] - addr
            else:
                offset = parse_imm(target) - addr
            f3_map = {'beq': F3_BEQ, 'bne': F3_BNE, 'blt': F3_BLT,
                      'bge': F3_BGE, 'bltu': F3_BLTU, 'bgeu': F3_BGEU}
            return encode_b(rs1, rs2, offset) | (f3_map[mnemonic] << 12) | OP_BR

        # === JAL ===
        elif mnemonic == 'jal':
            rd = parse_reg(a[0])
            target = a[1]
            if target in self.labels:
                offset = self.labels[target] - addr
            else:
                offset = parse_imm(target) - addr
            return encode_j(rd, offset) | JAL

        # === U-type ===
        elif mnemonic == 'lui':
            imm = parse_imm(a[1]) & 0xFFFFF000
            return encode_u(parse_reg(a[0]), imm) | LUI
        elif mnemonic == 'auipc':
            imm = parse_imm(a[1]) & 0xFFFFF000
            return encode_u(parse_reg(a[0]), imm) | AUIPC

        # === S-type ===
        elif mnemonic == 'sw':
            imm_str, rs1_str = a[1].split('(')
            rs1 = parse_reg(rs1_str.rstrip(')'))
            rs2 = parse_reg(a[0])
            imm = parse_imm(imm_str)
            s_imm = imm & 0xFFF
            return (
                ((s_imm >> 5) << 25) |
                (rs2 << 20) |
                (rs1 << 15) |
                (F3_SW << 12) |
                ((s_imm & 0x1F) << 7) |
                STORE
            )

        # === Pseudo-instructions ===
        elif mnemonic == 'nop':
            return 0x00000013  # addi x0, x0, 0
        elif mnemonic == 'li':
            # li rd, imm → addi rd, x0, imm
            imm = parse_imm(a[1])
            if -2048 <= imm < 2048:
                return encode_i(parse_reg(a[0]), 0, imm) | (F3_ADD << 12) | OP_IMM
            else:
                # Use LUI + ADDI for larger immediates (simplified)
                upper = (imm + 0x800) >> 12
                lower = imm - (upper << 12)
                raise ValueError(f"li with large immediate not implemented: {imm}")
        elif mnemonic == 'mv':
            return encode_r(parse_reg(a[0]), 0, parse_reg(a[1]), F3_ADD, 0) | OP

        # === M-extension ===
        elif mnemonic == 'mul':
            return encode_r(parse_reg(a[0]), parse_reg(a[1]), parse_reg(a[2]), F3_ADD, 0b0000001) | OP
        elif mnemonic == 'mulh':
            return encode_r(parse_reg(a[0]), parse_reg(a[1]), parse_reg(a[2]), F3_SLL, 0b0000001) | OP
        elif mnemonic == 'mulhu':
            return encode_r(parse_reg(a[0]), parse_reg(a[1]), parse_reg(a[2]), F3_SLT, 0b0000001) | OP
        elif mnemonic == 'div':
            return encode_r(parse_reg(a[0]), parse_reg(a[1]), parse_reg(a[2]), F3_SRL, 0b0000001) | OP

        elif mnemonic == 'ecall':
            return 0x00000073
        elif mnemonic == 'ebreak':
            return 0x00100073

        else:
            raise ValueError(f"Unknown instruction: {mnemonic}")

    def assemble(self, asm_text):
        """Assemble assembly text. Returns list of (addr, word) tuples."""
        # First pass: collect labels
        addr = self.start_addr
        for line in asm_text.strip().split('\n'):
            result = self.parse_line(line)
            if result is None:
                continue
            label, mnemonic, args = result
            if label:
                self.labels[label] = addr
            if mnemonic:
                addr += 4

        # Second pass: assemble instructions
        addr = self.start_addr
        instructions = []
        for line in asm_text.strip().split('\n'):
            result = self.parse_line(line)
            if result is None:
                continue
            label, mnemonic, args = result
            if mnemonic is None:
                continue
            word = self.assemble_inst(mnemonic, args, addr)
            instructions.append((addr, word))
            addr += 4

        return instructions

    def to_hex(self, instructions, mem_size=8192):
        """Convert instructions to hex file format (one 32-bit word per line)."""
        # Create a memory array filled with NOP
        mem = [0x00000013] * (mem_size // 4)
        for addr, word in instructions:
            idx = (addr - self.start_addr) // 4
            if 0 <= idx < len(mem):
                mem[idx] = word

        # Last word: jump to self (infinite loop)
        last_idx = len(mem) - 1
        if last_idx > len(instructions):
            #self-loop at end
            mem[last_idx] = 0x0000006F  # jal x0, 0 (infinite loop)

        lines = []
        for word in mem:
            lines.append(f"{word:08X}")
        return '\n'.join(lines)


def main():
    if len(sys.argv) < 2:
        print("Usage: python asm_to_hex.py <input.asm> [output.hex]")
        print("       python asm_to_hex.py --inline <assembly> [output.hex]")
        sys.exit(1)

    if sys.argv[1] == '--inline':
        asm_text = sys.argv[2]
        out_path = sys.argv[3] if len(sys.argv) > 3 else 'out.hex'
    else:
        with open(sys.argv[1], encoding='utf-8') as f:
            asm_text = f.read()
        out_path = sys.argv[2] if len(sys.argv) > 2 else sys.argv[1].replace('.asm', '.hex')

    asm = Assembler()
    instructions = asm.assemble(asm_text)
    hex_content = asm.to_hex(instructions)

    with open(out_path, 'w') as f:
        f.write(hex_content + '\n')

    print(f"Assembled {len(instructions)} instructions to {out_path}")
    for addr, word in instructions:
        print(f"  {addr:08X}: {word:08X}")


if __name__ == '__main__':
    main()
