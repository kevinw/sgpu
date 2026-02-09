#scope_export


// Initialize the global bindless argument table
init_bindless :: () {
    assert(argument_tables.compute == null);

    auto_release_temp();

    // Create the argument table descriptor
    descriptor := objc_scope_new(MTL4ArgumentTableDescriptor);
    {
        using MTL4ArgumentTableDescriptor;
        setMaxBufferBindCount      (descriptor, 3);
        setMaxTextureBindCount     (descriptor, 1);
        setMaxSamplerStateBindCount(descriptor, 1);
        setSupportAttributeStrides (descriptor, YES);
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
}

shutdown_bindless :: () {
    using argument_tables;
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

MTLGPUAddress :: #type u64;
