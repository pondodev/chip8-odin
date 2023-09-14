#version 330 core

in vec2 tex_coords;

out vec4 frag_color;

void main() {
    frag_color = vec4(tex_coords.xy, 0.0, 1.0);
}

