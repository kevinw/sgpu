#scope_export

BINDLESS_PARAMS_BINDING_INDEX :: 0;
BINDLESS_TEXTURES_BASE_BINDING_INDEX :: 1;
BINDLESS_SAMPLERS_BASE_BINDING_INDEX :: 0;

METAL_MAX_TEXTURE_BINDS :: 128;
// Metal validates maxTextureBindCount <= 128. With base texture binding at 1, this leaves 127 bindless texture slots.
BINDLESS_TEXTURE_BIND_CAPACITY :: 127;
BINDLESS_SAMPLER_BIND_CAPACITY :: MAX_SAMPLERS;

bindless_set_texture_resource :: (view_handle: Gpu_Texture_View, texture: *MTLTexture) {
    if view_handle == 0 return;

    bind_index := BINDLESS_TEXTURES_BASE_BINDING_INDEX + cast(NSUInteger) (cast(u32) view_handle - 1);
    if bind_index >= BINDLESS_TEXTURES_BASE_BINDING_INDEX + BINDLESS_TEXTURE_BIND_CAPACITY {
        log_error("Bindless texture handle % exceeds texture bindless capacity %.", view_handle, BINDLESS_TEXTURE_BIND_CAPACITY - 1);
        return;
    }

    resource_id: MTLResourceID;
    if texture_view_pool != null && texture != null {
        resource_id = texture_view_pool.setTextureView(texture_view_pool, texture, bind_index);
    } else {
        resource_id = .{};
    }
    argument_tables.compute.setTexture(argument_tables.compute, resource_id, bind_index);
    argument_tables.vertex.setTexture(argument_tables.vertex, resource_id, bind_index);
    argument_tables.fragment.setTexture(argument_tables.fragment, resource_id, bind_index);

}

bindless_set_sampler_resource :: (sampler_handle: Gpu_Sampler, resource_id: MTLResourceID) {
    if sampler_handle == 0 return;

    bind_index := BINDLESS_SAMPLERS_BASE_BINDING_INDEX + cast(NSUInteger) (cast(u32) sampler_handle - 1);
    if bind_index >= BINDLESS_SAMPLERS_BASE_BINDING_INDEX + BINDLESS_SAMPLER_BIND_CAPACITY {
        log_error("Bindless sampler handle % exceeds sampler bindless capacity %.", sampler_handle, BINDLESS_SAMPLER_BIND_CAPACITY - 1);
        return;
    }
    argument_tables.compute.setSamplerState(argument_tables.compute, resource_id, bind_index);
    argument_tables.vertex.setSamplerState(argument_tables.vertex, resource_id, bind_index);
    argument_tables.fragment.setSamplerState(argument_tables.fragment, resource_id, bind_index);
}


// Initialize the global bindless argument table
init_bindless :: () {
    assert(argument_tables.compute == null);

    auto_release_temp();
    if MAX_IMAGES > BINDLESS_TEXTURE_BIND_CAPACITY {
        log("Metal bindless textures clamped to % (requested MAX_IMAGES=%).", BINDLESS_TEXTURE_BIND_CAPACITY, MAX_IMAGES);
    }

    // Create the argument table descriptor
    descriptor := objc_scope_new(MTL4ArgumentTableDescriptor);
    {
        using MTL4ArgumentTableDescriptor;
        setMaxBufferBindCount      (descriptor, 3);
        setMaxTextureBindCount     (descriptor, BINDLESS_TEXTURES_BASE_BINDING_INDEX + BINDLESS_TEXTURE_BIND_CAPACITY);
        setMaxSamplerStateBindCount(descriptor, BINDLESS_SAMPLERS_BASE_BINDING_INDEX + BINDLESS_SAMPLER_BIND_CAPACITY);
        setSupportAttributeStrides (descriptor, NO);
        setInitializeBindings      (descriptor, YES);
    }

    make_argument_table :: (desc: *MTL4ArgumentTableDescriptor) -> *MTL4ArgumentTable {
        error: *NSError = null;
        arg_table := MTLDevice.newArgumentTableWithDescriptor(mtl_device, desc, *error);
        if log_error_if_not_null(error) {
            assert(false, "Failed to create argument table");
        }
        return arg_table;
    }

    // Create the global argument tables
    using argument_tables;
    argument_tables.compute  = make_argument_table(descriptor);
    argument_tables.vertex   = make_argument_table(descriptor);
    argument_tables.fragment = make_argument_table(descriptor);

    texture_view_pool_desc := objc_scope_new(MTLResourceViewPoolDescriptor);
    texture_view_pool_desc.setResourceViewCount(texture_view_pool_desc, BINDLESS_TEXTURES_BASE_BINDING_INDEX + BINDLESS_TEXTURE_BIND_CAPACITY);
    error: *NSError = null;
    texture_view_pool = MTLDevice.newTextureViewPoolWithDescriptor(mtl_device, texture_view_pool_desc, *error);
    if log_error_if_not_null(error) {
        assert(false, "Failed to create texture view pool");
    }
    assert(texture_view_pool != null);
}

shutdown_bindless :: () {
    using argument_tables;
    release_and_set_null(*texture_view_pool);
    release_and_set_null(*compute);
    release_and_set_null(*fragment);
    release_and_set_null(*vertex);
}


#scope_module

argument_tables: struct {
    compute: *MTL4ArgumentTable;
    vertex: *MTL4ArgumentTable;
    fragment: *MTL4ArgumentTable;
}

texture_view_pool: *MTLTextureViewPool;

MTLGPUAddress :: #type u64;
