#version 330 core

out vec2 tex_coords;

void main() {
    vec2 verts[3] = vec2[3](vec2(-1, -1), vec2(3, -1), vec2(-1, 3));

    vec4 v = vec4(verts[gl_VertexID], 0, 1);
    tex_coords = 0.5 * v.xy + vec2(0.5);
    gl_Position = v;
}

