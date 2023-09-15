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
    defer gl.DeleteVertexArrays(1, &vao)

    logger.info("loading texture")
    // init the texture
    texture_buffer: [device.DISPLAY_SIZE.x * device.DISPLAY_SIZE.y * 3]u8;
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

    upload_texture(texture_buffer)
    defer gl.DeleteTextures(1, &texture)

    logger.info("running main loop")
    device.init()
    for ! glfw.WindowShouldClose(platform) {
        glfw.PollEvents()

        device.update()

        gl.ClearColor(1.0, 0.0, 1.0, 1.0)
        // TODO: clean this up
        if device.is_display_dirty() {
            display_buffer: []u8 = device.get_display_buffer()
            for chunk, i in display_buffer {
                for bit in 0..=7 {
                    pixel_index := (i * 8) + bit
                    buffer_index := pixel_index * 3

                    pixel_on: bool = bool(chunk & (1 << u8(bit)))
                    color := pixel_on ? COLOR_PALETTE[1] : COLOR_PALETTE[0]
                    texture_buffer[buffer_index+0] = u8(color.r * 255)
                    texture_buffer[buffer_index+1] = u8(color.g * 255)
                    texture_buffer[buffer_index+2] = u8(color.b * 255)
                }
            }
            upload_texture(texture_buffer)
        }

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

upload_texture :: proc(texture: [device.DISPLAY_SIZE.x * device.DISPLAY_SIZE.y * 3]u8) {
    texture := texture
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB, i32(device.DISPLAY_SIZE.x), i32(device.DISPLAY_SIZE.y), 0, gl.RGB, gl.UNSIGNED_BYTE, &texture)
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

