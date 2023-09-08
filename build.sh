#!/bin/bash

if ! command -v odin &> /dev/null
then
    echo "odin not found on your PATH, please ensure it's built/installed and on your PATH"
    exit 1
fi

# TODO: argument parsing. allow for building, running, cleaning

# TODO: allow setting of optimisation levels
odin build .        \
    -out:chip8-odin \
    -o:speed        \
    -show-timings   \

