package main

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:runtime"

import "vendor:glfw"
import gl "vendor:OpenGL"

import "logger"

Color :: [4]f32

DISPLAY_SIZE : [2]u16 : { 64, 32 } // display has (0,0) in the top left
WINDOW_SCALE :: 10
WINDOW_TITLE :: "chip8-odin"
GL_MAJOR_VERSION :: 3
GL_MINOR_VERSION :: 2 // macos go brr

COLOR_PALETTE : [2]Color : {
    { 0.1, 0.1, 0.1, 1.0 },
    { 0.9, 0.9, 0.9, 1.0 },
}

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

Device :: struct {
    memory      : [0xFFF]u8,
    registers   : [16]u8, // registers v0 - vF
    reg_timer   : u8,
    reg_sound   : u8,
    pc          : u16,
    sp          : u8,
    key_flags   : u16,
    display     : [(DISPLAY_SIZE.x * DISPLAY_SIZE.y) / 8]u8, // 1-bit display buffer
}

dev: Device
platform: glfw.WindowHandle

main :: proc() {
    context.allocator = mem.panic_allocator()
    context.temp_allocator = mem.panic_allocator()

    logger.init()
    logger.set_level(logger.LogLevel.Info) // TODO: set based on build type

    defer logger.cleanup()

    logger.info("initialising glfw")
    glfw.SetErrorCallback(glfw_error_callback)
    if ! bool(glfw.Init()) {
        panic("failed to init glfw")
    }

    logger.info("setting window hints")
    glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_MAJOR_VERSION)
    glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_MINOR_VERSION)
    glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, 1)
    glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)

    logger.info("creating window")
    platform = glfw.CreateWindow(i32(DISPLAY_SIZE.x * WINDOW_SCALE),
                                 i32(DISPLAY_SIZE.y * WINDOW_SCALE),
                                 WINDOW_TITLE,
                                 nil,
                                 nil)

    defer glfw.Terminate()
    defer glfw.DestroyWindow(platform)

    if platform == nil {
       panic("failed to create window")
    }

    glfw.SetKeyCallback(platform, glfw_key_callback)

    logger.info("setting up opengl context")
    glfw.MakeContextCurrent(platform)
    glfw.SwapInterval(0)

    logger.info("loading up opengl to version ", GL_MAJOR_VERSION, ".", GL_MINOR_VERSION, sep="")
    gl.load_up_to(GL_MAJOR_VERSION, GL_MINOR_VERSION, glfw.gl_set_proc_address)

    logger.info("compiling/creating shader program")
    vert_shader_src: []u8 = #load("vert.glsl")
    frag_shader_src: []u8 = #load("frag.glsl")
    vertShader: u32 = gl.CreateShader(gl.VERTEX_SHADER)
    fragShader: u32 = gl.CreateShader(gl.FRAGMENT_SHADER)

    vert_shader: u32
    frag_shader: u32
    ok: bool
    if vert_shader, ok = compile_shader(&vert_shader_src, gl.VERTEX_SHADER); ! ok {
        panic("failed to compile vertex shader")
    }
    if frag_shader, ok = compile_shader(&frag_shader_src, gl.FRAGMENT_SHADER); ! ok {
        panic("failed to compile fragment shader")
    }

    defer gl.DeleteShader(vert_shader)
    defer gl.DeleteShader(frag_shader)

    program: u32 = gl.CreateProgram()
    gl.AttachShader(program, vert_shader)
    gl.AttachShader(program, frag_shader)
    gl.LinkProgram(program)

    {
        success: i32
        gl.GetProgramiv(program, gl.LINK_STATUS, &success)
        if ! bool(success) {
        BUF_SIZE :: 1024
            buffer: [BUF_SIZE]u8
            gl.GetProgramInfoLog(program, BUF_SIZE, nil, raw_data(&buffer))

            error_msg := cstring(raw_data(&buffer))
            panic_msg := strings.join({ "program error:", string(error_msg) }, "\n")
            panic(panic_msg)
        }
    }

    gl.UseProgram(program)

    defer gl.DeleteProgram(program)

    logger.info("creating vao")
    vao: u32
    gl.GenVertexArrays(1, &vao)
    gl.BindVertexArray(vao)

    logger.info("running main loop")
    for ! glfw.WindowShouldClose(platform) {
        glfw.PollEvents()

        gl.ClearColor(1.0, 0.0, 1.0, 1.0)
        gl.Clear(gl.COLOR_BUFFER_BIT)
        gl.DrawArrays(gl.TRIANGLES, 0, 3)

        glfw.SwapBuffers(platform)
    }
}

compile_shader :: proc(shader_src: ^[]u8, type: u32) -> (u32, bool) {
    shader_handle: u32 = gl.CreateShader(type)
    gl.ShaderSource(shader_handle, 1, auto_cast shader_src, nil)
    gl.CompileShader(shader_handle)

    success: i32
    gl.GetShaderiv(shader_handle, gl.COMPILE_STATUS, &success)
    if ! bool(success) {
        BUF_SIZE :: 1024
        buffer: [BUF_SIZE]u8
        gl.GetShaderInfoLog(shader_handle, BUF_SIZE, nil, raw_data(&buffer))

        error_msg := cstring(raw_data(&buffer))
        logger.error("shader compilation error:\n", error_msg)
    }

    return shader_handle, bool(success)
}

glfw_error_callback :: proc "c" (error: i32, desc: cstring) {
    context = runtime.default_context()
    logger.error("error in glfw (", error, "): ", desc)
}

glfw_key_callback :: proc "c" (window: glfw.WindowHandle, key: i32, scancode: i32, action: i32, mods: i32) {
    context = runtime.default_context()

    if window != platform do return
    switch action {
        // on key press
        case glfw.PRESS:
            switch key {
                case glfw.KEY_ESCAPE:
                    glfw.SetWindowShouldClose(platform, true)
            }

        // on key release
        case glfw.RELEASE:
            switch key {
                // NOP
            }
    }
}

/* SYS addr
 * jump to a machine code routine at nnn (ignored)
 */
instr_0nnn :: proc() {
    // NOP
}

/* CLS
 * clear the display
 */
instr_00E0 :: proc() {
}

/* RET
 * return from subroutine
 */
instr_00EE :: proc() {
}

/* JP nnn
 * jump to address nnn
 */
instr_1nnn :: proc(addr: u16) {
}

/* CALL nnn
 * call subroutine at address nnn
 */
instr_2nnn :: proc(addr: u16) {
}

/* SE vx, byte
 * skip next instruction if vx == kk
 */
instr_3xkk :: proc(reg: u8, val: u8) {
}

/* SNE vx, byte
 * skip next instruction if vx != kk
 */
instr_4xkk :: proc(reg: u8, val: u8) {
}

/* SE vx, vy
 * skip next instruction if vx == vy
 */
instr_5xy0 :: proc(reg_x: u8, reg_y: u8) {
}

/* LD vx, byte
 * vx = kk
 */
instr_6xkk :: proc(reg: u8, val: u8) {
}

/* ADD vx, byte
 * vx = vx + kk
 */
instr_7xkk :: proc(reg: u8, val: u8) {
}

/* LD vx, vy
 * vx = vy
 */
instr_8xy0 :: proc(reg_x: u8, reg_y: u8) {
}

/* OR vx, vy
 * vx = vx OR vy
 */
instr_8xy1 :: proc(reg_x: u8, reg_y: u8) {
}

/* AND vx, vy
 * vx = vx AND vy
 */
instr_8xy2 :: proc(reg_x: u8, reg_y: u8) {
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

