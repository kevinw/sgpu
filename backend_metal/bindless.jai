#scope_export

BINDLESS_PARAMS_BINDING_INDEX :: 0;
// Metal bindless textures are split into separate 2D / cube / 3D banks so distinct typed texture arrays
// can coexist in one shader without overlapping resource locations.
// `Gpu_Texture_View` values remain zero-based shader indices within each bank: 0 is the fallback slot.
BINDLESS_TEXTURES_2D_BASE_BINDING_INDEX :: 1;
BINDLESS_TEXTURES_CUBE_BASE_BINDING_INDEX :: 64;
BINDLESS_TEXTURES_3D_BASE_BINDING_INDEX :: 64;
BINDLESS_SAMPLERS_BASE_BINDING_INDEX :: 0;

METAL_MAX_TEXTURE_BINDS :: 128;
// Must stay aligned with the transpiler's bindless array lengths.
BINDLESS_TEXTURE_BIND_CAPACITY :: 63;
BINDLESS_SAMPLER_BIND_CAPACITY :: 16;
BINDLESS_TEXTURE_BIND_COUNT :: BINDLESS_TEXTURES_3D_BASE_BINDING_INDEX + BINDLESS_TEXTURE_BIND_CAPACITY;
BINDLESS_SAMPLER_BIND_COUNT :: BINDLESS_SAMPLERS_BASE_BINDING_INDEX + BINDLESS_SAMPLER_BIND_CAPACITY;

texture_view_handle_to_bindless_binding :: (base_binding: NSUInteger, view_handle: Gpu_Texture_View) -> NSUInteger {
    return base_binding + cast(NSUInteger) view_handle;
}

bindless_set_texture_resource :: (view_handle: Gpu_Texture_View, texture: *MTLTexture) {
    resource_id: MTLResourceID = .{};
    if texture == null {
        bind_2d := texture_view_handle_to_bindless_binding(BINDLESS_TEXTURES_2D_BASE_BINDING_INDEX, view_handle);
        bind_cube := texture_view_handle_to_bindless_binding(BINDLESS_TEXTURES_CUBE_BASE_BINDING_INDEX, view_handle);
        bind_3d := texture_view_handle_to_bindless_binding(BINDLESS_TEXTURES_3D_BASE_BINDING_INDEX, view_handle);
        if bind_2d < BINDLESS_TEXTURE_BIND_COUNT bindless_texture_resources[bind_2d] = resource_id;
        if bind_cube < BINDLESS_TEXTURE_BIND_COUNT bindless_texture_resources[bind_cube] = resource_id;
        if bind_3d < BINDLESS_TEXTURE_BIND_COUNT bindless_texture_resources[bind_3d] = resource_id;
        bindless_static_generation += 1;
        return;
    }

    if texture_view_pool != null && texture != null {
        texture_type := MTLTexture.textureType(texture);
        if texture_type == .Cube || texture_type == .CubeArray {
            bind_index := texture_view_handle_to_bindless_binding(BINDLESS_TEXTURES_CUBE_BASE_BINDING_INDEX, view_handle);
            if bind_index >= BINDLESS_TEXTURE_BIND_COUNT {
                log_error("Bindless cube texture handle % exceeds texture bindless capacity %.", view_handle, BINDLESS_TEXTURE_BIND_CAPACITY - 1);
                return;
            }
            resource_id = texture_view_pool.setTextureView(texture_view_pool, texture, bind_index);
            bindless_texture_resources[bind_index] = resource_id;
            bindless_static_generation += 1;
            return;
        } else if texture_type == ._3D {
            bind_index := texture_view_handle_to_bindless_binding(BINDLESS_TEXTURES_3D_BASE_BINDING_INDEX, view_handle);
            if bind_index >= BINDLESS_TEXTURE_BIND_COUNT {
                log_error("Bindless 3D texture handle % exceeds texture bindless capacity %.", view_handle, BINDLESS_TEXTURE_BIND_CAPACITY - 1);
                return;
            }
            resource_id = texture_view_pool.setTextureView(texture_view_pool, texture, bind_index);
            bindless_texture_resources[bind_index] = resource_id;
            bindless_static_generation += 1;
            return;
        } else {
            bind_index := texture_view_handle_to_bindless_binding(BINDLESS_TEXTURES_2D_BASE_BINDING_INDEX, view_handle);
            if bind_index >= BINDLESS_TEXTURE_BIND_COUNT {
                log_error("Bindless texture handle % exceeds texture bindless capacity %.", view_handle, BINDLESS_TEXTURE_BIND_CAPACITY - 1);
                return;
            }
            resource_id = texture_view_pool.setTextureView(texture_view_pool, texture, bind_index);
            bindless_texture_resources[bind_index] = resource_id;
            bindless_static_generation += 1;
            return;
        }
    }
}

bindless_set_sampler_resource :: (sampler_handle: Gpu_Sampler, resource_id: MTLResourceID) {
    if sampler_handle == 0 return;

    bind_index := BINDLESS_SAMPLERS_BASE_BINDING_INDEX + cast(NSUInteger) (cast(u32) sampler_handle - 1);
    if bind_index >= BINDLESS_SAMPLER_BIND_COUNT {
        log_error("Bindless sampler handle % exceeds sampler bindless capacity %.", sampler_handle, BINDLESS_SAMPLER_BIND_CAPACITY - 1);
        return;
    }
    bindless_sampler_resources[bind_index] = resource_id;
    bindless_static_generation += 1;
}

// Returns a frame-scoped argument table snapshot for one draw/dispatch.
// Caller may patch buffer addresses (setAddress) before binding.
bindless_lease_argument_table :: () -> *MTL4ArgumentTable {
    if argument_table_descriptor == null return null;

    slot := cast(s32) (frame_index % MAX_FRAMES_IN_FLIGHT);
    if argument_table_pool_epoch[slot] != frame_index {
        argument_table_pool_epoch[slot] = frame_index;
        argument_table_pool_cursor[slot] = 0;
    }

    cursor := argument_table_pool_cursor[slot];

    if cursor >= argument_table_pool[slot].count {
        table := make_argument_table(argument_table_descriptor);
        if table == null return null;
        array_add(*argument_table_pool[slot], Argument_Table_Entry.{table = table, static_generation = 0});
    }

    entry := *argument_table_pool[slot][cursor];
    argument_table_pool_cursor[slot] = cursor + 1;

    if entry.static_generation != bindless_static_generation {
        apply_static_bindings(entry.table);
        entry.static_generation = bindless_static_generation;
    }

    return entry.table;
}

// Initialize bindless argument table descriptor and texture-view pool.
init_bindless :: () {
    assert(argument_table_descriptor == null);

    auto_release_temp();
    if BINDLESS_TEXTURE_BIND_COUNT > METAL_MAX_TEXTURE_BINDS {
        log("Metal bindless textures clamped to % total entries (requested total=%).", METAL_MAX_TEXTURE_BINDS, BINDLESS_TEXTURE_BIND_COUNT);
    }

    // Keep descriptor alive for runtime table leasing.
    descriptor := objc_new(MTL4ArgumentTableDescriptor);
    {
        using MTL4ArgumentTableDescriptor;
        setMaxBufferBindCount      (descriptor, 15);
        setMaxTextureBindCount     (descriptor, BINDLESS_TEXTURE_BIND_COUNT);
        setMaxSamplerStateBindCount(descriptor, BINDLESS_SAMPLER_BIND_COUNT);
        setSupportAttributeStrides (descriptor, NO);
        setInitializeBindings      (descriptor, YES);
    }
    argument_table_descriptor = descriptor;

    bindless_static_generation = 1;
    for i: 0..MAX_FRAMES_IN_FLIGHT-1 {
        argument_table_pool[i].allocator = cpu_allocator;
        argument_table_pool_epoch[i] = U64_MAX;
        argument_table_pool_cursor[i] = 0;
    }

    texture_view_pool_desc := objc_scope_new(MTLResourceViewPoolDescriptor);
    texture_view_pool_desc.setResourceViewCount(texture_view_pool_desc, BINDLESS_TEXTURE_BIND_COUNT);
    error: *NSError = null;
    texture_view_pool = MTLDevice.newTextureViewPoolWithDescriptor(mtl_device, texture_view_pool_desc, *error);
    if log_error_if_not_null(error) {
        assert(false, "Failed to create texture view pool");
    }
    assert(texture_view_pool != null);
}

shutdown_bindless :: () {
    release_and_set_null(*texture_view_pool);
    release_and_set_null(*argument_table_descriptor);

    for i: 0..MAX_FRAMES_IN_FLIGHT-1 {
        for argument_table_pool[i] {
            if it.table != null release(it.table);
        }
        array_free(argument_table_pool[i]);
    }
}


#scope_module

texture_view_pool: *MTLTextureViewPool;
argument_table_descriptor: *MTL4ArgumentTableDescriptor;

Argument_Table_Entry :: struct {
    table: *MTL4ArgumentTable;
    static_generation: u64;
}

argument_table_pool: [MAX_FRAMES_IN_FLIGHT] [..] Argument_Table_Entry;
argument_table_pool_cursor: [MAX_FRAMES_IN_FLIGHT] s32;
argument_table_pool_epoch: [MAX_FRAMES_IN_FLIGHT] u64;

bindless_texture_resources: [BINDLESS_TEXTURE_BIND_COUNT] MTLResourceID;
bindless_sampler_resources: [BINDLESS_SAMPLER_BIND_COUNT] MTLResourceID;
bindless_static_generation: u64;

MTLGPUAddress :: #type u64;

make_argument_table :: (desc: *MTL4ArgumentTableDescriptor) -> *MTL4ArgumentTable {
    error: *NSError = null;
    arg_table := MTLDevice.newArgumentTableWithDescriptor(mtl_device, desc, *error);
    if log_error_if_not_null(error) {
        assert(false, "Failed to create argument table");
    }
    return arg_table;
}

apply_static_bindings :: (table: *MTL4ArgumentTable) {
    if table == null return;

    for i: BINDLESS_TEXTURES_2D_BASE_BINDING_INDEX..BINDLESS_TEXTURE_BIND_COUNT-1 {
        table.setTexture(table, bindless_texture_resources[i], cast(NSUInteger) i);
    }
    for i: BINDLESS_SAMPLERS_BASE_BINDING_INDEX..BINDLESS_SAMPLER_BIND_COUNT-1 {
        table.setSamplerState(table, bindless_sampler_resources[i], cast(NSUInteger) i);
    }
}
