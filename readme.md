# chip8-odin
another [chip8](https://en.wikipedia.org/wiki/CHIP-8) interpreter written in odin.

this project is very much a WIP, and is mostly to get me familiar with odin.

# building
ensure that you have odin built/installed on your system and added to your `PATH`. then just run `build.sh` and you'll
get the output binary `chip8-odin`.

# TODO
- extend build script to allow for cleaning, running, and setting optimisation level
- windowing and input
- opengl abstraction
- core cpu implementation
- instruction implementation
- imgui debug ui for performance stats
- sounds

# wishlist
- abstractions over dx11/metal for windows/macos
- double buffered rendering
- nice ui for loading programs from disk
- memory/register inspector ui
- chip8 debugger

