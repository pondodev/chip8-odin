package main

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:runtime"

import "vendor:glfw"
import gl "vendor:OpenGL"

import "logger"
import "device"

Color :: [4]f32

WINDOW_SCALE :: 10
WINDOW_SIZE : [2]u16 : {
    device.DISPLAY_SIZE.x * WINDOW_SCALE,
    device.DISPLAY_SIZE.y * WINDOW_SCALE,
}
WINDOW_TITLE :: "chip8-odin"
GL_MAJOR_VERSION :: 3
GL_MINOR_VERSION :: 2 // macos go brr

COLOR_PALETTE : [2]Color : {
    { 0.1, 0.1, 0.1, 1.0 },
    { 0.9, 0.9, 0.9, 1.0 },
}

platform: glfw.WindowHandle
TEX_BUFFER_SIZE :: device.DISPLAY_SIZE.x * device.DISPLAY_SIZE.y * 3
texture_buffer: [TEX_BUFFER_SIZE]u8

// TODO: user input for rom
ROM_PATH :: "./trip8.ch8"

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
    glfw.WindowHint(glfw.RESIZABLE, 0)

    logger.info("creating window")
    platform = glfw.CreateWindow(i32(WINDOW_SIZE.x),
                                 i32(WINDOW_SIZE.y),
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

    vert_shader, frag_shader := create_shaders()
    defer gl.DeleteShader(vert_shader)
    defer gl.DeleteShader(frag_shader)

    program := create_program(vert_shader, frag_shader)
    defer gl.DeleteProgram(program)

    vao := create_vao()
    defer gl.DeleteVertexArrays(1, &vao)

    texture := create_texture()
    defer gl.DeleteTextures(1, &texture)

    upload_texture()

    device.init()
    if ! device.load_rom(ROM_PATH) {
        panic("failed to load rom")
    }

    logger.info("running main loop")
    for ! glfw.WindowShouldClose(platform) {
        glfw.PollEvents()

        device.update()

        gl.ClearColor(1.0, 0.0, 1.0, 1.0)
        if device.is_display_dirty() {
            update_texture()
            upload_texture()
        }

        gl.Clear(gl.COLOR_BUFFER_BIT)
        gl.DrawArrays(gl.TRIANGLES, 0, 3)

        glfw.SwapBuffers(platform)
    }
}

create_shaders :: proc() -> (u32, u32) {
    logger.info("loading and compiling shaders")
    vert_shader_src: []u8 = #load("vert.glsl")
    frag_shader_src: []u8 = #load("frag.glsl")

    vert_shader: u32
    frag_shader: u32
    ok: bool
    if vert_shader, ok = compile_shader(&vert_shader_src, gl.VERTEX_SHADER); ! ok {
        panic("failed to compile vertex shader")
    }
    if frag_shader, ok = compile_shader(&frag_shader_src, gl.FRAGMENT_SHADER); ! ok {
        panic("failed to compile fragment shader")
    }

    return vert_shader, frag_shader
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
        logger.error("shader compilation error:\n", error_msg, sep="")
    }

    return shader_handle, bool(success)
}

create_program :: proc(vert_shader, frag_shader: u32) -> u32 {
    logger.info("creating program and linking shaders")
    program: u32 = gl.CreateProgram()
    gl.AttachShader(program, vert_shader)
    gl.AttachShader(program, frag_shader)
    gl.LinkProgram(program)

    ok: i32
    gl.GetProgramiv(program, gl.LINK_STATUS, &ok)
    if ! bool(ok) {
        BUF_SIZE :: 1024
        buffer: [BUF_SIZE]u8
        gl.GetProgramInfoLog(program, BUF_SIZE, nil, raw_data(&buffer))

        error_msg := cstring(raw_data(&buffer))
        panic_msg := strings.join({ "program error:", string(error_msg) }, "\n")
        panic(panic_msg)
    }

    gl.UseProgram(program)
    return program
}

create_vao :: proc() -> u32 {
    logger.info("creating vao")
    vao: u32
    gl.GenVertexArrays(1, &vao)
    gl.BindVertexArray(vao)

    return vao
}

create_texture :: proc() -> u32 {
    logger.info("loading texture")
    // init the texture
    for _, i in texture_buffer {
        component := i % 3;
        color := COLOR_PALETTE[0]
        texture_buffer[i] = u8(color[component] * 255)
    }

    texture: u32
    gl.GenTextures(1, &texture)
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D, texture)

    // clamp texture to border (set to red to spot issues with mapping)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_BORDER)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_BORDER)
    tex_border_color: Color = { 1.0, 0.0, 0.0, 1.0 }
    gl.TexParameterfv(gl.TEXTURE_2D, gl.TEXTURE_BORDER_COLOR, raw_data(&tex_border_color))

    // nearest neighbour texture filtering
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)

    return texture
}

update_texture :: proc() {
    display_buffer: []u8 = device.get_display_buffer()
    for chunk, i in display_buffer {
        for bit in 0..=7 {
            pixel_index := (i * 8) + bit
            buffer_index := pixel_index * 3

            pixel_on := bool(chunk & (1 << u8(bit)))
            color := pixel_on ? COLOR_PALETTE[1] : COLOR_PALETTE[0]
            texture_buffer[buffer_index+0] = u8(color.r * 255)
            texture_buffer[buffer_index+1] = u8(color.g * 255)
            texture_buffer[buffer_index+2] = u8(color.b * 255)
        }
    }
}

upload_texture :: proc() {
    gl.TexImage2D(gl.TEXTURE_2D,
                  0,
                  gl.RGB,
                  i32(device.DISPLAY_SIZE.x),
                  i32(device.DISPLAY_SIZE.y),
                  0,
                  gl.RGB,
                  gl.UNSIGNED_BYTE,
                  &texture_buffer)
}

glfw_error_callback :: proc "c" (error: i32, desc: cstring) {
    context = runtime.default_context()
    logger.error("error in glfw (", error, "):", desc)
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

