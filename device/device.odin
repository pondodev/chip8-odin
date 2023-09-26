package device

import "core:time"
import "core:fmt"

DISPLAY_SIZE : [2]u16 : { 64, 32 } // display has (0,0) in the top left

@private
CHAR_SPRITES :: [?]u8 {
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
}

@private
PROGRAM_START_ADDR :: 0x200
@private
MEM_SIZE :: 0xFFF
@private
GP_REGISTER_COUNT :: 16
@private
STACK_SIZE :: 16

@private
Device :: struct {
    // device
    memory          : [MEM_SIZE]u8,
    registers       : [GP_REGISTER_COUNT]u8, // registers v0 - vF
    reg_timer       : u8,
    reg_sound       : u8,
    reg_i           : u16,
    pc              : u16,
    sp              : u8,
    stack           : [STACK_SIZE]u16,
    key_flags       : u8,
    display         : [(DISPLAY_SIZE.x * DISPLAY_SIZE.y) / 8]u8, // 1-bit display buffer

    // implementation details
    display_dirty   : bool,
    next_advance    : u8,
}

@private
dev: Device

@private
timer: time.Duration
@private
last_update: time.Time

init :: proc() {
    dev.pc = PROGRAM_START_ADDR

    // TODO: debug code, remove
    dev.display[0] = 0x1
    last_update = time.now()
}

load_rom :: proc(path: string) -> bool {
    // TODO
    return true
}

is_display_dirty :: proc() -> bool {
    return dev.display_dirty
}

get_display_buffer :: proc() -> []u8 {
    dev.display_dirty = false
    return dev.display[:]
}

set_key_state :: proc(key_flags: u8) {
    MASK : u8 : 0x0F
    dev.key_flags = key_flags & MASK
}

cycle :: proc() {
    op: u16 = (cast(u16)dev.memory[dev.pc]) << 8 | (cast(u16)dev.memory[dev.pc])
    addr: u16 = op & 0x0FFF
    reg_x: u8 = dev.memory[dev.pc] & 0x0F
    reg_y: u8 = (dev.memory[dev.pc+1] & 0xF0) >> 4
    data_byte: u8 = dev.memory[dev.pc+1]
    data_nibble: u8 = dev.memory[dev.pc+1] & 0x0F

    switch {
        case (op & 0xFFFF) == 0x00E0: instr_00E0()
        case (op & 0xFFFF) == 0x00EE: instr_00EE()
        case (op & 0xF000) == 0x0000: instr_0nnn()
        case (op & 0xF000) == 0x1000: instr_1nnn(addr)
        case (op & 0xF000) == 0x2000: instr_2nnn(addr)
        case (op & 0xF000) == 0x3000: instr_3xkk(reg_x, data_byte)
        case (op & 0xF000) == 0x4000: instr_4xkk(reg_x, data_byte)
        case (op & 0xF00F) == 0x5000: instr_5xy0(reg_x, reg_y)
        case (op & 0xF000) == 0x6000: instr_6xkk(reg_x, data_byte)
        case (op & 0xF000) == 0x7000: instr_7xkk(reg_x, data_byte)
        case (op & 0xF00F) == 0x8000: instr_8xy0(reg_x, reg_y)
        case (op & 0xF00F) == 0x8001: instr_8xy1(reg_x, reg_y)
        case (op & 0xF00F) == 0x8002: instr_8xy2(reg_x, reg_y)
        case (op & 0xF00F) == 0x8003: instr_8xy3(reg_x, reg_y)
        case (op & 0xF00F) == 0x8004: instr_8xy4(reg_x, reg_y)
        case (op & 0xF00F) == 0x8005: instr_8xy5(reg_x, reg_y)
        case (op & 0xF00F) == 0x8006: instr_8xy6(reg_x, reg_y)
        case (op & 0xF00F) == 0x8007: instr_8xy7(reg_x, reg_y)
        case (op & 0xF00F) == 0x800E: instr_8xyE(reg_x, reg_y)
        case (op & 0xF00F) == 0x9000: instr_9xy0(reg_x, reg_y)
        case (op & 0xF000) == 0xA000: instr_Annn(addr)
        case (op & 0xF000) == 0xB000: instr_Bnnn(addr)
        case (op & 0xF000) == 0xC000: instr_Cxkk(reg_x, data_byte)
        case (op & 0xF000) == 0xD000: instr_Dxyn(reg_x, reg_y, data_nibble)
        case (op & 0xF0FF) == 0xE09E: instr_Ex9E(reg_x)
        case (op & 0xF0FF) == 0xE0A1: instr_ExA1(reg_x)
        case (op & 0xF0FF) == 0xF007: instr_Fx07(reg_x)
        case (op & 0xF0FF) == 0xF00A: instr_Fx0A(reg_x)
        case (op & 0xF0FF) == 0xF015: instr_Fx15(reg_x)
        case (op & 0xF0FF) == 0xF018: instr_Fx18(reg_x)
        case (op & 0xF0FF) == 0xF01E: instr_Fx1E(reg_x)
        case (op & 0xF0FF) == 0xF029: instr_Fx29(reg_x)
        case (op & 0xF0FF) == 0xF033: instr_Fx33(reg_x)
        case (op & 0xF0FF) == 0xF055: instr_Fx55(reg_x)
        case (op & 0xF0FF) == 0xF065: instr_Fx65(reg_x)
    }
}

update :: proc() {
    // TODO: debug code, remove
    now := time.now()
    diff := time.diff(last_update, now)
    last_update = now
    timer += diff
    if (time.duration_milliseconds(timer) < 50) do return

    timer = 0

    MSB :: 0x1 << 7;
    for _, i  in dev.display {
        chunk: ^u8 = &dev.display[i]
        if chunk^ > 0 {
            if (chunk^ & MSB) > 0 {
                chunk^ = 0
                new_chunk_index := i+1 >= len(dev.display) ? 0 : i+1
                dev.display[new_chunk_index] = 0x1
            } else {
                chunk^ <<= 1
            }

            break
        }
    }
    dev.display_dirty = true
}

validate_addr :: proc(addr: u16) -> bool {
    return addr >= PROGRAM_START_ADDR && addr <= MEM_SIZE
}

validate_reg :: proc(reg: u8) -> bool {
    return reg < GP_REGISTER_COUNT
}

/* SYS addr
 * jump to a machine code routine at nnn (ignored)
 */
instr_0nnn :: proc() {
    // NOP

    dev.next_advance = 1
}

/* CLS
 * clear the display
 */
instr_00E0 :: proc() {
    for _, i in dev.display {
        dev.display[i] = 0x00
    }
    dev.display_dirty = true

    dev.next_advance  = 1
}

/* RET
 * return from subroutine
 */
instr_00EE :: proc() {
    assert(dev.sp != 0, "no addresses left in call stack")

    dev.sp -= 1
    dev.pc = dev.stack[dev.sp]

    dev.next_advance = 0
}

/* JP nnn
 * jump to address nnn
 */
instr_1nnn :: proc(addr: u16) {
    assert(validate_addr(addr), "address out of range")

    dev.pc = addr

    dev.next_advance = 0
}

/* CALL nnn
 * call subroutine at address nnn
 */
instr_2nnn :: proc(addr: u16) {
    assert(validate_addr(addr), "address out of range")

    dev.stack[dev.sp] = dev.pc
    dev.sp += 1
    dev.pc = addr

    dev.next_advance = 0
}

/* SE vx, byte
 * skip next instruction if vx == kk
 */
instr_3xkk :: proc(reg: u8, val: u8) {
    assert(validate_reg(reg), "invalid register number")

    if dev.registers[reg] == val {
        dev.next_advance = 2
    } else {
        dev.next_advance = 1
    }
}

/* SNE vx, byte
 * skip next instruction if vx != kk
 */
instr_4xkk :: proc(reg: u8, val: u8) {
    assert(validate_reg(reg), "invalid register number")

    if dev.registers[reg] != val {
        dev.next_advance = 2
    } else {
        dev.next_advance = 1
    }
}

/* SE vx, vy
 * skip next instruction if vx == vy
 */
instr_5xy0 :: proc(reg_x: u8, reg_y: u8) {
    assert(validate_reg(reg_x), "invalid register number")
    assert(validate_reg(reg_y), "invalid register number")

    if dev.registers[reg_x] == dev.registers[reg_y] {
        dev.next_advance = 2
    } else {
        dev.next_advance = 1
    }
}

/* LD vx, byte
 * vx = kk
 */
instr_6xkk :: proc(reg: u8, val: u8) {
    assert(validate_reg(reg), "invalid register number")

    dev.registers[reg] = val

    dev.next_advance = 1
}

/* ADD vx, byte
 * vx = vx + kk
 */
instr_7xkk :: proc(reg: u8, val: u8) {
    assert(validate_reg(reg), "invalid register number")

    dev.registers[reg] += val

    dev.next_advance = 1
}

/* LD vx, vy
 * vx = vy
 */
instr_8xy0 :: proc(reg_x: u8, reg_y: u8) {
    assert(validate_reg(reg_x), "invalid register number")
    assert(validate_reg(reg_y), "invalid register number")

    dev.registers[reg_x] = dev.registers[reg_y]

    dev.next_advance = 1
}

/* OR vx, vy
 * vx = vx OR vy
 */
instr_8xy1 :: proc(reg_x: u8, reg_y: u8) {
    assert(validate_reg(reg_x), "invalid register number")
    assert(validate_reg(reg_y), "invalid register number")

    dev.registers[reg_x] |= dev.registers[reg_y]

    dev.next_advance = 1
}

/* AND vx, vy
 * vx = vx AND vy
 */
instr_8xy2 :: proc(reg_x: u8, reg_y: u8) {
    assert(validate_reg(reg_x), "invalid register number")
    assert(validate_reg(reg_y), "invalid register number")

    dev.registers[reg_x] &= dev.registers[reg_y]

    dev.next_advance = 1
}

/* XOR vx, vy
 * vx = vx XOR vy
 */
instr_8xy3 :: proc(reg_x: u8, reg_y: u8) {
}

/* ADD vx, vy
 * vx = vx + vy, vF = carry
 */
instr_8xy4 :: proc(reg_x: u8, reg_y: u8) {
}

/* SUB vx, vy
 * vx = vx - vy, vF = NOT borrow
 */
instr_8xy5 :: proc(reg_x: u8, reg_y: u8) {
}

/* SHR vx{, vy}
 * vx = vx SHR 1. if LSB is 1 then set vF to 1
 */
instr_8xy6 :: proc(reg_x: u8, reg_y: u8) {
}

/* SUBN vx, vy
 * vx = vy - vx, vF = NOT borrow
 */
instr_8xy7 :: proc(reg_x: u8, reg_y: u8) {
}

/* SHL vx{, vy}
 * vx = vx SHL 1. if MSB is 1 then set vF to 1
 */
instr_8xyE :: proc(reg_x: u8, reg_y: u8) {
}

/* SNE vx, vy
 * skip next instruction if vx != vy
 */
instr_9xy0 :: proc(reg_x: u8, reg_y: u8) {
}

/* LD I, nnn
 * set register I to nnn
 */
instr_Annn :: proc(addr: u16) {
}

/* JP v0, nnn
 * set pc to nnn + v0
 */
instr_Bnnn :: proc(addr: u16) {
}

/* RND vx, kk
 * vx = kk AND random byte
 */
instr_Cxkk :: proc(reg: u8, val: u8) {
}

/* DRW vx, vy, nibble
 * reads n bytes from memory from address stored in I, and draws
 * this sprite at coords (vx, vy). sprites are XOR'd onto the screen,
 * and if any pixels are erased then vF is set to 1. if a sprite is
 * drawn off the screen, it wraps to the other side.
 */
instr_Dxyn :: proc(reg_x: u8, reg_y: u8, nibble: u8) {
}

/* SKP vx
 * skip next instruction if key at index stored in vx was pressed
 */
instr_Ex9E :: proc(reg: u8) {
}

/* SKNP vx
 * skip next instruction if key at index stored in vx was NOT pressed
 */
instr_ExA1 :: proc(reg: u8) {
}

/* LD vx, DT
 * set vx to DT
 */
instr_Fx07 :: proc(reg: u8) {
}

/* LD vx, K
 * wait for a key press, store the key value in vx
 */
instr_Fx0A :: proc(reg: u8) {
}

/* LD DT, vx
 * set DT to vx
 */
instr_Fx15 :: proc(reg: u8) {
}

/* LD ST, vx
 * set ST to vx
 */
instr_Fx18 :: proc(reg: u8) {
}

/* ADD I, vx
 * I = I + vx
 */
instr_Fx1E :: proc(reg: u8) {
}

/* LD F, vx
 * set I to the location of the sprite at vx
 */
instr_Fx29 :: proc(reg: u8) {
}

/* LD B, vx
 * store BCD representation of vx in memory locations I, I+1, and I+2
 */
instr_Fx33 :: proc(reg: u8) {
}

/* LD [I], vx
 * store registers v0-vx in memory starting at location I
 */
instr_Fx55 :: proc(reg: u8) {
}

/* LD vx, [I]
 * read registers v0-vx in memory starting at location I
 */
instr_Fx65 :: proc(reg: u8) {
}

