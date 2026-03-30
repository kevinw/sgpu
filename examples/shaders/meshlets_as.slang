struct MeshPayload {
    uint dummy;
}

[shader("amplification")]
[numthreads(1, 1, 1)]
void main(out MeshPayload payload) {
    payload.dummy = 0;
    DispatchMesh(1, 1, 1, payload);
}
