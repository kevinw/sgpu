struct Vertex {
    float4 pos: SV_Position;
}

struct Primitive {
    [[vk::location(0)]]
    nointerpolation float3 color;
}

[shader("fragment")]
float3 main(Vertex vert, Primitive prim) {
    return prim.color;
}
