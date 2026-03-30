const static float2 positions[3] = {
    float2(0.0, -0.5),
    float2(0.5, 0.5),
    float2(-0.5, 0.5),
};

struct MeshPayload {
    uint dummy;
}

struct Vertex {
    float4 pos: SV_Position;
}

struct Primitive {
    [[vk::location(0)]]
    nointerpolation float3 color;
    bool cull: SV_CullPrimitive;
}

const static uint MAX_VERTICES = 3;
const static uint MAX_PRIMITIVES = 1;

[outputtopology("triangle")]
[numthreads(3, 1, 1)]
[shader("mesh")]
void main(
    uint thread_id: SV_GroupIndex,
    in payload MeshPayload payload,
    OutputIndices<uint3, MAX_PRIMITIVES> out_triangles,
    OutputVertices<Vertex, MAX_VERTICES> out_vertices,
    OutputPrimitives<Primitive, MAX_PRIMITIVES> out_primitives
) {
    _ = payload;
    SetMeshOutputCounts(MAX_VERTICES, MAX_PRIMITIVES);

    if (thread_id < MAX_VERTICES) {
        Vertex vert;
        vert.pos = float4(positions[thread_id], 0, 1);
        out_vertices[thread_id] = vert;
    }

    if (thread_id < MAX_PRIMITIVES) {
        out_triangles[thread_id] = uint3(0, 1, 2);
        Primitive prim;
        prim.color = float3(1, 0.5, 0.5);
        prim.cull = false;
        out_primitives[thread_id] = prim;
    }
}
