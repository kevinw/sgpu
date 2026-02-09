import "common";

struct VS_Output {
    float4 position : SV_POSITION;
    float3 color : COLOR;
}

struct Vertex_Buffers {
    float2* positions;
    float4* colors;
};

[vk::push_constant]
VertexParams<Vertex_Buffers> sp;

[shader("vertex")]
VS_Output main(uint vertex_id: SV_VertexID) {
    VS_Output output;
    output.position = float4(sp.get().positions[vertex_id], 0., 1.);
    output.color = sp.get().colors[vertex_id].xyz;
    return output;
}
