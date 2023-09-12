package logger

import "core:fmt"
import "core:runtime"
import "core:mem"
import "core:time"
import "core:os"

LogLevel :: enum int {
    None    = 0,
    Error   = 1,
    Warn    = 2,
    Info    = 3,
}

@private
arena: mem.Arena
@private
ARENA_BUFFER_SIZE :: 1000 * 4
@private
ArenaBuffer :: [ARENA_BUFFER_SIZE]u8
@private
arena_buffer: ^ArenaBuffer
@private
arena_allocator: runtime.Allocator
@private
heap_allocator: runtime.Allocator

@private
log_level: LogLevel = LogLevel.Error
@private
log_to_file: bool
@private
initialised: bool = false

@private
check_init :: proc() {
    if ! initialised do panic("logger not initialised")
}

@private
write_log_file :: proc(msg: string) {
    if ! log_to_file do return

    // TODO: write to log file
}

@private
datetime_string :: proc() -> string {
    now : time.Time = time.now()
    hour, min, sec := time.clock_from_time(now)
    year, mon, day := time.date(now)

    return fmt.tprint("[", day, "/", int(mon), "/", year, "-", hour, ":", min, ":", sec, "]", sep="")
}

init :: proc(enable_file_dump: bool = false) {
    heap_allocator = os.heap_allocator()

    arena_buffer = new(ArenaBuffer, heap_allocator)
    mem.arena_init(&arena, arena_buffer^[:])
    arena_allocator = mem.arena_allocator(&arena)

    log_to_file = enable_file_dump
    initialised = true
}

cleanup :: proc() {
    free_all(heap_allocator)
}

set_level :: proc(level: LogLevel) {
    log_level = level
}

info :: proc(args: ..any, sep: string = " ") {
    check_init()
    if log_level < LogLevel.Info do return

    context.temp_allocator = arena_allocator

    str := fmt.tprint(..args, sep=sep)
    msg := fmt.tprint(datetime_string(), " INFO: ", str, sep="")
    fmt.println(msg)
    write_log_file(msg)

    free_all(context.temp_allocator)
}

warn :: proc(args: ..any, sep: string = " ") {
    check_init()
    if log_level < LogLevel.Warn do return

    context.temp_allocator = arena_allocator

    str := fmt.tprint(..args, sep=sep)
    msg := fmt.tprint(datetime_string(), " WARN: ", str, sep="")
    fmt.println(msg)
    write_log_file(msg)

    free_all(context.temp_allocator)
}

error :: proc(args: ..any, sep: string = " ") {
    check_init()
    if log_level < LogLevel.Error do return

    context.temp_allocator = arena_allocator

    str := fmt.tprint(..args, sep=sep)
    msg := fmt.tprint(datetime_string(), " ERROR: ", str, sep="")
    fmt.eprintln(msg)
    write_log_file(msg)

    free_all(context.temp_allocator)
}

