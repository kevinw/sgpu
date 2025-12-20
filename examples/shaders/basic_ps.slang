struct PS_Input {
}

struct Data {
    float3 color;
};

struct Params {
    [[vk::offset(8)]]
    Data* data;
}
[vk::push_constant]
Params pc;

[shader("pixel")]
float4 main(PS_Input input) : SV_Target0 {
    return float4(pc.data.color, 1.);
}