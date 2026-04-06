#scope_export

gpu_create_mesh_pipeline :: (desc: Gpu_Mesh_Pipeline_Desc) -> Gpu_Pipeline {
    auto_release_temp();
    assert(desc.mesh_threads[0] != 0 && desc.mesh_threads[1] != 0 && desc.mesh_threads[2] != 0, "gpu_create_mesh_pipeline requires explicit mesh_threads.");
    assert(desc.pixel_shader.count != 0, "gpu_create_mesh_pipeline requires pixel_shader.");
    assert(desc.mesh_shader.count != 0, "gpu_create_mesh_pipeline requires mesh_shader.");
    assert(desc.task_shader.count == 0 || (desc.task_threads[0] != 0 && desc.task_threads[1] != 0 && desc.task_threads[2] != 0), "gpu_create_mesh_pipeline requires explicit task_threads when task_shader is provided.");

    mesh_library  := new_scoped_library_or_return_0(desc.mesh_shader, "mesh shader");
    pixel_library := new_scoped_library_or_return_0(desc.pixel_shader, "fragment shader");

    task_library: *MTLLibrary = mesh_library;
    if desc.task_shader.count != 0 && (desc.task_shader.count != desc.mesh_shader.count || desc.task_shader.data != desc.mesh_shader.data) {
        task_library = new_library_or_return_0(desc.task_shader, "task shader");
    }
    defer if task_library {
        release(task_library);
    }

    mesh_function := MTLLibrary.newFunctionWithName(mesh_library, to_temp_nsstring("meshMain"));
    if mesh_function == null {
        log_error("Failed to find meshMain in mesh shader library");
        return 0;
    }
    //defer release(mesh_function);

    fragment_function := MTLLibrary.newFunctionWithName(pixel_library, to_temp_nsstring("fragmentMain"));
    if fragment_function == null {
        log_error("Failed to find fragmentMain in fragment shader library");
        return 0;
    }
    //defer release(fragment_function);

    object_function: *MTLFunction;
    if desc.task_shader.count != 0 {
        object_function = MTLLibrary.newFunctionWithName(task_library, to_temp_nsstring("objectMain"));
        if object_function == null {
            log_error("Failed to find objectMain in task shader library");
            return 0;
        }
    } else {
        object_function = null;
    }
    //defer if object_function release(object_function);

    mesh_threads := to_mtl_size(desc.mesh_threads);
    object_threads := to_mtl_size(desc.task_threads);

    max_mesh_threads := 128;
    if mesh_threads.width != 0 && mesh_threads.height != 0 && mesh_threads.depth != 0 {
        max_mesh_threads = (mesh_threads.width * mesh_threads.height * mesh_threads.depth).(int);
    }

    func_desc :: (mtl_library: *MTLLibrary, function: *MTLFunction) -> *MTL4FunctionDescriptor #expand {
        library_desc := objc_new(MTL4LibraryFunctionDescriptor);
        MTL4LibraryFunctionDescriptor.setLibrary(library_desc, mtl_library);
        MTL4LibraryFunctionDescriptor.setName(library_desc, MTLFunction.name(function));
        return library_desc;
    }

    pipeline_desc := objc_new_defer_release(MTL4MeshRenderPipelineDescriptor);
    {
        using pipeline_desc;
        setMeshFunctionDescriptor(pipeline_desc, func_desc(mesh_library, mesh_function));
        if object_function != null {
            setObjectFunctionDescriptor(pipeline_desc, func_desc(task_library, object_function));
        }
        setFragmentFunctionDescriptor(pipeline_desc, func_desc(pixel_library, fragment_function));
        setRasterSampleCount(pipeline_desc, max(1, desc.raster_desc.sample_count).(NSUInteger));
        setMaxTotalThreadsPerMeshThreadgroup(pipeline_desc, max_mesh_threads.(NSUInteger));
        setMeshThreadgroupSizeIsMultipleOfThreadExecutionWidth(pipeline_desc, NO);
        if mesh_threads.width != 0 && mesh_threads.height != 0 && mesh_threads.depth != 0 {
            setRequiredThreadsPerMeshThreadgroup(pipeline_desc, mesh_threads);
        }
        if object_function != null {
            max_object_threads := max(1, (object_threads.width * object_threads.height * object_threads.depth).(int));
            setMaxTotalThreadsPerObjectThreadgroup(pipeline_desc, max_object_threads.(NSUInteger));
            setObjectThreadgroupSizeIsMultipleOfThreadExecutionWidth(pipeline_desc, NO);
            if object_threads.width != 0 && object_threads.height != 0 && object_threads.depth != 0 {
                setRequiredThreadsPerObjectThreadgroup(pipeline_desc, object_threads);
            }
            if desc.payload_memory_length != 0 {
                setPayloadMemoryLength(pipeline_desc, desc.payload_memory_length.(NSUInteger));
            }
            if desc.max_total_threadgroups_per_mesh_grid != 0 {
                setMaxTotalThreadgroupsPerMeshGrid(pipeline_desc, desc.max_total_threadgroups_per_mesh_grid.(NSUInteger));
            }
        }
    }

    color_attachments := pipeline_desc.colorAttachments(pipeline_desc);
    for desc.raster_desc.color_targets {
        color_attachment := MTL4RenderPipelineColorAttachmentDescriptorArray.objectAtIndexedSubscript(color_attachments, it_index.(NSUInteger));

        using color_attachment;
        setPixelFormat(color_attachment, format_to_mtl(it.format));

        if desc.raster_desc.blend_state != null {
            blend := desc.raster_desc.blend_state;
            if blend.src_color_factor != .ZERO || blend.dst_color_factor != .ZERO {
                setBlendingState(color_attachment, .Enabled);
                setSourceRGBBlendFactor(color_attachment, blend_factor_to_mtl(blend.src_color_factor));
                setDestinationRGBBlendFactor(color_attachment, blend_factor_to_mtl(blend.dst_color_factor));
                setRgbBlendOperation(color_attachment, blend_op_to_mtl(blend.color_op));
                setSourceAlphaBlendFactor(color_attachment, blend_factor_to_mtl(blend.src_alpha_factor));
                setDestinationAlphaBlendFactor(color_attachment, blend_factor_to_mtl(blend.dst_alpha_factor));
                setAlphaBlendOperation(color_attachment, blend_op_to_mtl(blend.alpha_op));
            }
            setWriteMask(color_attachment, color_write_mask_to_mtl(blend.color_write_mask));
        }
    }

    compiler_desc := objc_new_defer_release(MTL4CompilerDescriptor);
    error: *NSError = null;
    compiler := MTLDevice.newCompilerWithDescriptor(mtl_device, compiler_desc, *error);
    if error != null || compiler == null {
        log_error_if_not_null(error, "newCompilerWithDescriptor");
        return 0;
    }
    defer release(compiler);

    task_options: *MTL4CompilerTaskOptions = null;
    render_pipeline := MTL4Compiler.newRenderPipelineStateWithDescriptor(compiler, cast(*MTL4PipelineDescriptor) pipeline_desc, task_options, *error);
    if log_error_if_not_null(error) return 0;
    if render_pipeline == null {
        log_error("Failed to create mesh render pipeline state");
        return 0;
    }

    return pool_add(*live_pipelines, .{
        type = .GRAPHICS,
        mtl_render_pipeline = render_pipeline,
        raster_desc = desc.raster_desc,
        is_mesh_pipeline = true,
        has_mesh_object_stage = object_function != null,
        required_threads_per_object_threadgroup = fallback_threadgroup_size(render_pipeline.requiredThreadsPerObjectThreadgroup(render_pipeline)),
        required_threads_per_mesh_threadgroup = ifx render_pipeline.requiredThreadsPerMeshThreadgroup(render_pipeline).width != 0
            then render_pipeline.requiredThreadsPerMeshThreadgroup(render_pipeline)
            else fallback_threadgroup_size(mesh_threads),
        max_total_threadgroups_per_mesh_grid = cast(u32) render_pipeline.maxTotalThreadgroupsPerMeshGrid(render_pipeline),
    });
}

gpu_draw_meshlets :: (cmd: Gpu_Command_Buffer, data: Gpu_Ptr, dimensions: [3] u32) -> Gpu_Result {
    return gpu_draw_meshlets(cmd, data, .[], dimensions);
}

gpu_draw_meshlets :: (cmd: Gpu_Command_Buffer, data: Gpu_Ptr, extra_bindings: []Gpu_Ptr, dimensions: [3] u32) -> Gpu_Result {
    using cmd_info := get_cmd_info(cmd);
    if cmd_info == null || current_render_encoder == null then return .ERROR_INVALID_PIPELINE;

    pipeline := pool_get(live_pipelines, current_pipeline);
    if pipeline == null || pipeline.mtl_render_pipeline == null || !pipeline.is_mesh_pipeline {
        return .ERROR_INVALID_PIPELINE;
    }

    if data != 0 {
        table := bindless_lease_argument_table();
        if table == null {
            log_error("could not lease argument table");
            return .FATAL_ERROR_UNKNOWN;
        }
        table.setAddress(table, cast(MTLGPUAddress) data, 0);
        for extra_bindings {
            table.setAddress(table, cast(MTLGPUAddress) it, cast(NSUInteger) (it_index + 1));
        }
        stages := cast(MTLRenderStages)(MTLRenderStage.Mesh | .Fragment);
        if pipeline.has_mesh_object_stage stages |= cast(MTLRenderStages) MTLRenderStage.Object;
        current_render_encoder.setArgumentTable(current_render_encoder, table, stages);
    }

    object_threads := ifx pipeline.has_mesh_object_stage
        then fallback_threadgroup_size(pipeline.required_threads_per_object_threadgroup)
        else MTLSize.{ width = 0, height = 0, depth = 0 };
    mesh_threads := fallback_threadgroup_size(pipeline.required_threads_per_mesh_threadgroup);
    current_render_encoder.drawMeshThreadgroups(
        current_render_encoder,
        to_mtl_size(dimensions),
        object_threads,
        mesh_threads
    );

    return .SUCCESS;
}

gpu_create_compute_pipeline :: (metal_source: []u8) -> Gpu_Pipeline {
    auto_release_temp();
    compile_options := new_scoped_common_mtl_compile_options();

    error: *NSError;
    mtl_library := MTLDevice.newLibraryWithSource(mtl_device, to_temp_nsstring(cast(string)metal_source), compile_options, *error);
    defer if mtl_library release(mtl_library);
    if log_error_if_not_null(error) || mtl_library == null {
        log_error("Failed to create Metal library");
        return 0;
    }

    // Try both naming conventions plus fallback names.
    mtl_function := get_function_from_library(mtl_library, "ComputeMain", "computeMain", "main", "main_0");
    if mtl_function == null {
        mtl_function = get_only_function_by_type(mtl_library, .Kernel);
    }
    if mtl_function == null {
        log_error("Failed to find compute main function in Metal shader");
        return 0;
    }
    defer release(mtl_function);

    // Create the compute pipeline state
    mtl_pipeline := MTLDevice.newComputePipelineStateWithFunction(mtl_device, mtl_function, *error);
    if log_error_if_not_null(error) {
        log_error("Failed to create compute pipeline.");
        return 0;
    }

    if mtl_pipeline == null {
        log_error("Failed to create compute pipeline state");
        return 0;
    }

    return pool_add(*live_pipelines, {
        type = .COMPUTE,
        mtl_compute_pipeline = mtl_pipeline,
        compute_binding_mode = detect_compute_binding_mode(metal_source),
    });
}

gpu_create_compute_pipeline_from_metallib :: (metallib_path: string, function_name: string, use_root_pointer_struct := false) -> Gpu_Pipeline {
    auto_release_temp();
    if metallib_path.count == 0 || function_name.count == 0 {
        log_error("gpu_create_compute_pipeline_from_metallib: metallib path/function name missing.");
        return 0;
    }

    library := new_scoped_library_from_file_or_return_0(metallib_path, "compute metallib");
    mtl_function := get_function_from_library(library, function_name);
    if mtl_function == null {
        log_error("Failed to find compute function '%' in metallib '%'.", function_name, metallib_path);
        return 0;
    }
    defer release(mtl_function);

    error: *NSError;
    mtl_pipeline := MTLDevice.newComputePipelineStateWithFunction(mtl_device, mtl_function, *error);
    if log_error_if_not_null(error) {
        log_error("Failed to create compute pipeline from metallib '%'.", metallib_path);
        return 0;
    }
    if mtl_pipeline == null {
        log_error("Failed to create compute pipeline state from metallib '%'.", metallib_path);
        return 0;
    }

    return pool_add(*live_pipelines, {
        type = .COMPUTE,
        mtl_compute_pipeline = mtl_pipeline,
        compute_binding_mode = ifx use_root_pointer_struct then .ROOT_POINTER_STRUCT else .DIRECT_ADDRESSES,
    });
}

gpu_create_graphics_pipeline :: (vertex_metal: []u8, pixel_metal: []u8, raster_desc: Gpu_Raster_Desc) -> Gpu_Pipeline {
    auto_release_temp();

    // Create library from vertex shader Metal source
    vertex_library := new_scoped_library_or_return_0(vertex_metal, "vertex shader");
    pixel_library  := new_scoped_library_or_return_0(pixel_metal,  "fragment shader");
    return _internal_gpu_create_graphics_pipeline(vertex_library, pixel_library, raster_desc);
}

gpu_create_graphics_pipeline :: (metal: []u8, raster_desc: Gpu_Raster_Desc) -> Gpu_Pipeline {
    auto_release_temp();
    library := new_scoped_library_or_return_0(metal, "vertex+fragment shader");
    return _internal_gpu_create_graphics_pipeline(library, library, raster_desc);
}

gpu_create_graphics_pipeline_from_metallib :: (metallib_path: string, vertex_function_name: string, fragment_function_name: string, raster_desc: Gpu_Raster_Desc) -> Gpu_Pipeline {
    auto_release_temp();
    if metallib_path.count == 0 || vertex_function_name.count == 0 || fragment_function_name.count == 0 {
        log_error("gpu_create_graphics_pipeline_from_metallib: metallib path/function names missing.");
        return 0;
    }
    library := new_scoped_library_from_file_or_return_0(metallib_path, "graphics metallib");
    return _internal_gpu_create_graphics_pipeline_with_names(library, library, raster_desc, vertex_function_name, fragment_function_name);
}

gpu_create_graphics_pipeline_from_metallib_with_function_constants :: (
    metallib_path: string,
    vertex_function_name: string,
    fragment_function_name: string,
    raster_desc: Gpu_Raster_Desc,
    vertex_constants: *MTLFunctionConstantValues = null,
    fragment_constants: *MTLFunctionConstantValues = null
) -> Gpu_Pipeline {
    auto_release_temp();
    if metallib_path.count == 0 || vertex_function_name.count == 0 || fragment_function_name.count == 0 {
        log_error("gpu_create_graphics_pipeline_from_metallib_with_function_constants: metallib path/function names missing.");
        return 0;
    }
    library := new_scoped_library_from_file_or_return_0(metallib_path, "graphics metallib");
    return _internal_gpu_create_graphics_pipeline_with_names_and_constants(
        library, library, raster_desc, vertex_function_name, fragment_function_name, vertex_constants, fragment_constants);
}

gpu_create_mesh_pipeline_from_metallib :: (metallib_path: string, task_function_name: string, mesh_function_name: string, fragment_function_name: string, desc: Gpu_Mesh_Pipeline_Desc) -> Gpu_Pipeline {
    return gpu_create_mesh_pipeline_from_metallib_with_function_constants(
        metallib_path, task_function_name, mesh_function_name, fragment_function_name, desc, null, null, null);
}

gpu_create_mesh_pipeline_from_metallib_with_function_constants :: (
    metallib_path: string,
    task_function_name: string,
    mesh_function_name: string,
    fragment_function_name: string,
    desc: Gpu_Mesh_Pipeline_Desc,
    task_constants: *MTLFunctionConstantValues = null,
    mesh_constants: *MTLFunctionConstantValues = null,
    fragment_constants: *MTLFunctionConstantValues = null
) -> Gpu_Pipeline {
    auto_release_temp();
    if metallib_path.count == 0 || mesh_function_name.count == 0 || fragment_function_name.count == 0 {
        log_error("gpu_create_mesh_pipeline_from_metallib: metallib path/function names missing.");
        return 0;
    }
    assert(desc.mesh_threads[0] != 0 && desc.mesh_threads[1] != 0 && desc.mesh_threads[2] != 0, "gpu_create_mesh_pipeline_from_metallib requires explicit mesh_threads.");
    if task_function_name.count != 0 {
        assert(desc.task_threads[0] != 0 && desc.task_threads[1] != 0 && desc.task_threads[2] != 0, "gpu_create_mesh_pipeline_from_metallib requires explicit task_threads when task shader is provided.");
    }

    error: *NSError = null;
    lib_url := NSURL.fileURLWithPath(to_temp_nsstring(metallib_path));
    library := MTLDevice.newLibraryWithURL(mtl_device, lib_url, *error);
    if error != null || library == null {
        log_error_if_not_null(error, "newLibraryWithURL");
        return 0;
    }
    defer release(library);

    mesh_function := MTLLibrary.newFunctionWithName(library, to_temp_nsstring(mesh_function_name));
    if mesh_function == null {
        log_error("Failed to find % in mesh metallib", mesh_function_name);
        return 0;
    }

    fragment_function := MTLLibrary.newFunctionWithName(library, to_temp_nsstring(fragment_function_name));
    if fragment_function == null {
        log_error("Failed to find % in mesh metallib", fragment_function_name);
        return 0;
    }

    object_function: *MTLFunction;
    if task_function_name.count != 0 {
        object_function = MTLLibrary.newFunctionWithName(library, to_temp_nsstring(task_function_name));
        if object_function == null {
            log_error("Failed to find % in mesh metallib", task_function_name);
            return 0;
        }
    } else {
        object_function = null;
    }

    mesh_threads := to_mtl_size(desc.mesh_threads);
    object_threads := to_mtl_size(desc.task_threads);
    max_mesh_threads := 128;
    if mesh_threads.width != 0 && mesh_threads.height != 0 && mesh_threads.depth != 0 {
        max_mesh_threads = (mesh_threads.width * mesh_threads.height * mesh_threads.depth).(int);
    }

    func_desc :: (mtl_library: *MTLLibrary, function: *MTLFunction, constants: *MTLFunctionConstantValues) -> *MTL4FunctionDescriptor #expand {
        library_desc := objc_new(MTL4LibraryFunctionDescriptor);
        MTL4LibraryFunctionDescriptor.setLibrary(library_desc, mtl_library);
        MTL4LibraryFunctionDescriptor.setName(library_desc, MTLFunction.name(function));
        if constants == null return library_desc;

        defer release(library_desc);

        validate_function_constants(function, constants);

        specialized_desc := objc_new(MTL4SpecializedFunctionDescriptor);
        MTL4SpecializedFunctionDescriptor.setFunctionDescriptor(specialized_desc, library_desc);
        MTL4SpecializedFunctionDescriptor.setConstantValues(specialized_desc, constants);
        return specialized_desc;
    }

    pipeline_desc := objc_new_defer_release(MTL4MeshRenderPipelineDescriptor);
    {
        using pipeline_desc;
        setMeshFunctionDescriptor(pipeline_desc, func_desc(library, mesh_function, mesh_constants));
        if object_function != null {
            setObjectFunctionDescriptor(pipeline_desc, func_desc(library, object_function, task_constants));
        }
        setFragmentFunctionDescriptor(pipeline_desc, func_desc(library, fragment_function, fragment_constants));
        setRasterSampleCount(pipeline_desc, max(1, desc.raster_desc.sample_count).(NSUInteger));
        setMaxTotalThreadsPerMeshThreadgroup(pipeline_desc, max_mesh_threads.(NSUInteger));
        setMeshThreadgroupSizeIsMultipleOfThreadExecutionWidth(pipeline_desc, NO);
        if mesh_threads.width != 0 && mesh_threads.height != 0 && mesh_threads.depth != 0 {
            setRequiredThreadsPerMeshThreadgroup(pipeline_desc, mesh_threads);
        }
        if object_function != null {
            max_object_threads := max(1, (object_threads.width * object_threads.height * object_threads.depth).(int));
            setMaxTotalThreadsPerObjectThreadgroup(pipeline_desc, max_object_threads.(NSUInteger));
            setObjectThreadgroupSizeIsMultipleOfThreadExecutionWidth(pipeline_desc, NO);
            if object_threads.width != 0 && object_threads.height != 0 && object_threads.depth != 0 {
                setRequiredThreadsPerObjectThreadgroup(pipeline_desc, object_threads);
            }
            if desc.payload_memory_length != 0 {
                setPayloadMemoryLength(pipeline_desc, desc.payload_memory_length.(NSUInteger));
            }
            if desc.max_total_threadgroups_per_mesh_grid != 0 {
                setMaxTotalThreadgroupsPerMeshGrid(pipeline_desc, desc.max_total_threadgroups_per_mesh_grid.(NSUInteger));
            }
        }
    }

    color_attachments := pipeline_desc.colorAttachments(pipeline_desc);
    for desc.raster_desc.color_targets {
        color_attachment := MTL4RenderPipelineColorAttachmentDescriptorArray.objectAtIndexedSubscript(color_attachments, it_index.(NSUInteger));
        using color_attachment;
        setPixelFormat(color_attachment, format_to_mtl(it.format));
        if desc.raster_desc.blend_state != null {
            blend := desc.raster_desc.blend_state;
            if blend.src_color_factor != .ZERO || blend.dst_color_factor != .ZERO {
                setBlendingState(color_attachment, .Enabled);
                setSourceRGBBlendFactor(color_attachment, blend_factor_to_mtl(blend.src_color_factor));
                setDestinationRGBBlendFactor(color_attachment, blend_factor_to_mtl(blend.dst_color_factor));
                setRgbBlendOperation(color_attachment, blend_op_to_mtl(blend.color_op));
                setSourceAlphaBlendFactor(color_attachment, blend_factor_to_mtl(blend.src_alpha_factor));
                setDestinationAlphaBlendFactor(color_attachment, blend_factor_to_mtl(blend.dst_alpha_factor));
                setAlphaBlendOperation(color_attachment, blend_op_to_mtl(blend.alpha_op));
            }
            setWriteMask(color_attachment, color_write_mask_to_mtl(blend.color_write_mask));
        }
    }
    compiler_desc := objc_new_defer_release(MTL4CompilerDescriptor);
    error = null;
    compiler := MTLDevice.newCompilerWithDescriptor(mtl_device, compiler_desc, *error);
    if error != null || compiler == null {
        log_error_if_not_null(error, "newCompilerWithDescriptor");
        return 0;
    }
    defer release(compiler);

    error = null;
    task_options: *MTL4CompilerTaskOptions = null;
    pipeline_state := MTL4Compiler.newRenderPipelineStateWithDescriptor(compiler, cast(*MTL4PipelineDescriptor) pipeline_desc, task_options, *error);
    if error != null || pipeline_state == null {
        log_error_if_not_null(error, "newRenderPipelineStateWithDescriptor");
        return 0;
    }

    return pool_add(*live_pipelines, .{
        type = .GRAPHICS,
        mtl_render_pipeline = cast(*MTLRenderPipelineState) pipeline_state,
        raster_desc = desc.raster_desc,
        is_mesh_pipeline = true,
        has_mesh_object_stage = object_function != null,
        required_threads_per_object_threadgroup = fallback_threadgroup_size(pipeline_state.requiredThreadsPerObjectThreadgroup(pipeline_state)),
        required_threads_per_mesh_threadgroup = ifx pipeline_state.requiredThreadsPerMeshThreadgroup(pipeline_state).width != 0
            then pipeline_state.requiredThreadsPerMeshThreadgroup(pipeline_state)
            else fallback_threadgroup_size(mesh_threads),
        max_total_threadgroups_per_mesh_grid = cast(u32) pipeline_state.maxTotalThreadgroupsPerMeshGrid(pipeline_state),
    });
}

_internal_gpu_create_graphics_pipeline :: (vertex_library: *MTLLibrary, pixel_library: *MTLLibrary, raster_desc: Gpu_Raster_Desc) -> Gpu_Pipeline {
    return _internal_gpu_create_graphics_pipeline_with_names(vertex_library, pixel_library, raster_desc, "", "");
}

_internal_gpu_create_graphics_pipeline_with_names :: (vertex_library: *MTLLibrary, pixel_library: *MTLLibrary, raster_desc: Gpu_Raster_Desc, vertex_name: string, fragment_name: string) -> Gpu_Pipeline {
    return _internal_gpu_create_graphics_pipeline_with_names_and_constants(vertex_library, pixel_library, raster_desc,
                                                                           vertex_name, fragment_name,
                                                                           null, null);
}

_internal_gpu_create_graphics_pipeline_with_names_and_constants :: (vertex_library: *MTLLibrary,
                                                                    pixel_library: *MTLLibrary,
                                                                    raster_desc: Gpu_Raster_Desc,
                                                                    vertex_name: string,
                                                                    fragment_name: string,
                                                                    vertex_constants: *MTLFunctionConstantValues,
                                                                    fragment_constants: *MTLFunctionConstantValues) -> Gpu_Pipeline {
    // Get vertex function - try various names (Slang may rename "main" to "main_0")
    vertex_function: *MTLFunction;
    if vertex_name.count != 0 {
        vertex_function = get_function_from_library(vertex_library, vertex_name);
    } else {
        vertex_function = get_only_function_by_type(vertex_library, .Vertex);
    }
    if vertex_function == null {
        if vertex_name.count != 0 {
            log_error("Failed to find vertex function '%' in library.", vertex_name);
            fn_names := vertex_library.functionNames(vertex_library);
            for idx: 0..fn_names.count(fn_names)-1 {
                s := to_string(fn_names.objectAtIndex(fn_names, idx));
                log("  available function: '%'", s);
            }
        }
        else log_error("Failed to automatically find vertex function in shader");
        return 0;
    }
    defer release(vertex_function);

    // Get fragment function - try various names (Slang may rename "main" to "main_0")
    fragment_function: *MTLFunction;
    if fragment_name.count != 0 {
        fragment_function = get_function_from_library(pixel_library, fragment_name);
    } else {
        fragment_function = get_only_function_by_type(pixel_library, .Fragment);
    }
    if fragment_function == null {
        if fragment_name.count != 0 log_error("Failed to find fragment function '%' in library.", fragment_name);
        else log_error("Failed to automatically find fragment function in shader");
        return 0;
    }
    defer release(fragment_function);

    func_desc :: (mtl_library: *MTLLibrary, function: *MTLFunction, constants: *MTLFunctionConstantValues) -> *MTL4FunctionDescriptor #expand {
        library_desc := objc_new(MTL4LibraryFunctionDescriptor);
        MTL4LibraryFunctionDescriptor.setLibrary(library_desc, mtl_library);
        MTL4LibraryFunctionDescriptor.setName(library_desc, MTLFunction.name(function));
        if constants == null return library_desc;

        defer release(library_desc);

        validate_function_constants(function, constants);

        specialized_desc := objc_new(MTL4SpecializedFunctionDescriptor);
        MTL4SpecializedFunctionDescriptor.setFunctionDescriptor(specialized_desc, library_desc);
        MTL4SpecializedFunctionDescriptor.setConstantValues(specialized_desc, constants);

        return specialized_desc;
    }

    // Create MTL4 render pipeline descriptor
    pipeline_desc := objc_new_defer_release(MTL4RenderPipelineDescriptor);
    pipeline_desc.setVertexFunctionDescriptor(pipeline_desc, func_desc(vertex_library, vertex_function, vertex_constants));
    pipeline_desc.setFragmentFunctionDescriptor(pipeline_desc, func_desc(pixel_library, fragment_function, fragment_constants));

    // Configure color attachments
    color_attachments := pipeline_desc.colorAttachments(pipeline_desc);
    for raster_desc.color_targets {
        color_attachment := MTL4RenderPipelineColorAttachmentDescriptorArray.objectAtIndexedSubscript(color_attachments, it_index.(NSUInteger));

        using color_attachment;
        setPixelFormat(color_attachment, format_to_mtl(it.format));

        // Configure blending if we have a blend state
        if raster_desc.blend_state != null {
            blend := raster_desc.blend_state;

            // Enable blending if any factor is not the default
            if blend.src_color_factor != .ZERO || blend.dst_color_factor != .ZERO {
                setBlendingState(color_attachment, .Enabled);

                setSourceRGBBlendFactor(color_attachment, blend_factor_to_mtl(blend.src_color_factor));
                setDestinationRGBBlendFactor(color_attachment, blend_factor_to_mtl(blend.dst_color_factor));
                setRgbBlendOperation(color_attachment, blend_op_to_mtl(blend.color_op));

                setSourceAlphaBlendFactor(color_attachment, blend_factor_to_mtl(blend.src_alpha_factor));
                setDestinationAlphaBlendFactor(color_attachment, blend_factor_to_mtl(blend.dst_alpha_factor));
                setAlphaBlendOperation(color_attachment, blend_op_to_mtl(blend.alpha_op));
            }

            // Set write mask
            setWriteMask(color_attachment, color_write_mask_to_mtl(blend.color_write_mask));
        }
    }

    // Set sample count
    if raster_desc.sample_count > 0 {
        MTL4RenderPipelineDescriptor.setRasterSampleCount(pipeline_desc, raster_desc.sample_count.(NSUInteger));
    }

    // Create the compiler and pipeline state
    compiler_desc := objc_new_defer_release(MTL4CompilerDescriptor);

    error: *NSError;
    compiler := MTLDevice.newCompilerWithDescriptor(mtl_device, compiler_desc, *error);
    if error != null || compiler == null {
        log_error_if_not_null(error, "newCompilerWithDescriptor");
        return 0;
    }
    defer release(compiler);

    // Create compiler task options (can be null for default options)
    task_options: *MTL4CompilerTaskOptions = null;

    // Cast pipeline_desc to base type MTL4PipelineDescriptor
    error = null;
    render_pipeline := MTL4Compiler.newRenderPipelineStateWithDescriptor(compiler, pipeline_desc, task_options, *error);
    if log_error_if_not_null(error, "newRenderPipelineStateWithDescriptor") {
        return 0;
    }
    if render_pipeline == null {
        log_error("Failed to create render pipeline state");
        return 0;
    }

    handle := pool_add(*live_pipelines, .{
        type = .GRAPHICS,
        mtl_compute_pipeline = null,
        mtl_render_pipeline = render_pipeline,
        raster_desc = raster_desc,
    });

    return handle;
}

NSEnumerator :: struct(T: Type) {
    using #as super: NSObject;
    type :: T;
}

nextObject :: (container: *NSEnumerator($T)) -> T {
    next_object: (*void, Selector) -> T #c_call;
    next_object = xx objc_msgSend;
    return next_object(container, selector("nextObject"));
}

keyEnumerator :: (dict: *NSDictionary($K, $V)) -> *NSEnumerator(K) {
    key_enumerator: (*void, Selector) -> *NSEnumerator(K) #c_call;
    key_enumerator = xx objc_msgSend;
    return key_enumerator(dict, selector("keyEnumerator"));
}

validate_function_constants :: (function: *MTLFunction, constants: *MTLFunctionConstantValues) {
    //
    // TODO - delete or fix this up and use it in non release builds?
    //
    fn_constants_dict := function.functionConstantsDictionary(function);

    key_enumerator := keyEnumerator(fn_constants_dict);
    while true {
        next_object := nextObject(key_enumerator);
        if next_object == null {
            break;
        }
    }

}

gpu_free_pipeline :: (pipeline_handle: Gpu_Pipeline) {
    removed, pipeline := pool_remove(*live_pipelines, pipeline_handle);
    if !removed return;

    using pipeline;
    release_and_set_null(*mtl_compute_pipeline);
    release_and_set_null(*mtl_render_pipeline);
}

gpu_dispatch :: (cmd: Gpu_Command_Buffer, data: Gpu_Ptr, dimensions: [3] u32) {
    gpu_dispatch_buffers(cmd, .[data], dimensions);
}

gpu_dispatch_buffers :: (cmd: Gpu_Command_Buffer, data_ptrs: []Gpu_Ptr, dimensions: [3] u32) {
    cmd_info := get_cmd_info(cmd);
    if cmd_info == null return;

    pipeline := pool_get(live_pipelines, cmd_info.current_pipeline);
    return_if(pipeline == null, tprint("gpu_dispatch: no pipeline for %", cmd_info.current_pipeline));
    return_if(pipeline.type != .COMPUTE, "gpu_dispatch: pipeline is not .COMPUTE");

    queue := get_queue(cmd_info.queue);
    return_if(queue == null || queue.mtl4_queue == null, tprint("gpu_dispatch: no queue (cmd_info.queue is %)", cmd_info.queue));

    // End any existing render encoder before starting compute
    end_current_render_encoder(cmd_info);

    // Ensure compute encoder exists
    compute_encoder := ensure_compute_encoder(cmd_info);
    if compute_encoder == null then return;

    compute_encoder.setComputePipelineState(compute_encoder, pipeline.mtl_compute_pipeline);

    if pipeline.compute_binding_mode == .DIRECT_ADDRESSES {
        table := bindless_lease_argument_table();
        if table == null return;
        for data_ptrs {
            MTL4ArgumentTable.setAddress(table, cast(MTLGPUAddress) it, cast(NSUInteger) it_index);
        }
        MTL4ComputeCommandEncoder.setArgumentTable(compute_encoder, table);
    } else {
        table := bindless_lease_argument_table();
        if table == null return;
        ptr0 := ifx data_ptrs.count > 0 then data_ptrs[0] else 0;
        ptr1 := ifx data_ptrs.count > 1 then data_ptrs[1] else 0;
        ptr2 := ifx data_ptrs.count > 2 then data_ptrs[2] else 0;
        indirect_buffer := get_indirect_params_buffer(queue, ptr0, ptr1, ptr2);
        MTL4ArgumentTable.setAddress(table, indirect_buffer.gpuAddress(indirect_buffer), 0);
        MTL4ComputeCommandEncoder.setArgumentTable(compute_encoder, table);
    }

    // Get thread execution width and calculate threads per threadgroup
    max_threads := MTLComputePipelineState.maxTotalThreadsPerThreadgroup(pipeline.mtl_compute_pipeline);

    // Use a reasonable threadgroup size (typically 64 for compute shaders)
    threads_per_group := MTLSize.{ width = 64, height = 1, depth = 1 };
    if threads_per_group.width > max_threads {
        threads_per_group.width = max_threads;
    }

    // Dispatch threadgroups
    threadgroups := MTLSize.{
        width  = dimensions[0].(NSUInteger),
        height = dimensions[1].(NSUInteger),
        depth  = dimensions[2].(NSUInteger),
    };

    MTL4ComputeCommandEncoder.dispatchThreadgroups(compute_encoder, threadgroups, threads_per_group);
}

gpu_indirect_dispatch :: (cmd: Gpu_Command_Buffer, data: Gpu_Ptr, dimensions_gpu: Gpu_Ptr) -> Gpu_Result {
    return gpu_indirect_dispatch_buffers(cmd, .[data], dimensions_gpu);
}

gpu_indirect_dispatch_buffers :: (cmd: Gpu_Command_Buffer, data_ptrs: []Gpu_Ptr, dimensions_gpu: Gpu_Ptr) -> Gpu_Result {
    cmd_info := get_cmd_info(cmd);
    if cmd_info == null return .FATAL_ERROR_UNKNOWN;

    pipeline := pool_get(live_pipelines, cmd_info.current_pipeline);
    if pipeline == null return_error(.ERROR_INVALID_PIPELINE, "gpu_indirect_dispatch: no pipeline for %", cmd_info.current_pipeline);
    if pipeline.type != .COMPUTE return_error(.ERROR_INVALID_PIPELINE, "gpu_indirect_dispatch: pipeline is not .COMPUTE");

    queue := get_queue(cmd_info.queue);
    if queue == null || queue.mtl4_queue == null return_error(.FATAL_ERROR_UNKNOWN, "gpu_indirect_dispatch: no queue (cmd_info.queue is %)", cmd_info.queue);

    end_current_render_encoder(cmd_info);

    compute_encoder := ensure_compute_encoder(cmd_info);
    if compute_encoder == null return .FATAL_ERROR_UNKNOWN;

    compute_encoder.setComputePipelineState(compute_encoder, pipeline.mtl_compute_pipeline);

    table := bindless_lease_argument_table();
    if table == null return .FATAL_ERROR_UNKNOWN;

    if pipeline.compute_binding_mode == .DIRECT_ADDRESSES {
        for data_ptrs {
            MTL4ArgumentTable.setAddress(table, cast(MTLGPUAddress) it, cast(NSUInteger) it_index);
        }
    } else {
        ptr0 := ifx data_ptrs.count > 0 then data_ptrs[0] else 0;
        ptr1 := ifx data_ptrs.count > 1 then data_ptrs[1] else 0;
        ptr2 := ifx data_ptrs.count > 2 then data_ptrs[2] else 0;
        indirect_buffer := get_indirect_params_buffer(queue, ptr0, ptr1, ptr2);
        MTL4ArgumentTable.setAddress(table, indirect_buffer.gpuAddress(indirect_buffer), 0);
    }
    MTL4ComputeCommandEncoder.setArgumentTable(compute_encoder, table);

    max_threads := MTLComputePipelineState.maxTotalThreadsPerThreadgroup(pipeline.mtl_compute_pipeline);
    threads_per_group := MTLSize.{ width = 64, height = 1, depth = 1 };
    if threads_per_group.width > max_threads {
        threads_per_group.width = max_threads;
    }

    MTL4ComputeCommandEncoder.dispatchThreadgroupsWithIndirectBuffer(
        compute_encoder,
        cast(MTLGPUAddress) dimensions_gpu,
        threads_per_group);
    return .SUCCESS;
}

new_library_or_return_0 :: (source: []u8, debug_name: string) -> *MTLLibrary #expand {
    compile_options := new_scoped_common_mtl_compile_options();
    error: *NSError;
    library := MTLDevice.newLibraryWithSource(mtl_device, to_temp_nsstring(cast(string)source), compile_options, *error);
    if log_error_if_not_null(error) {
        log_error("Failed to compile %.", debug_name);
        `return 0;
    }
    if library == null {
        log_error("Failed to create % library", debug_name);
        `return 0;
    }
    return library;
}

new_scoped_library_or_return_0 :: (source: []u8, debug_name: string) -> *MTLLibrary #expand {
    compile_options := new_scoped_common_mtl_compile_options();

    error: *NSError;
    library := MTLDevice.newLibraryWithSource(mtl_device, to_temp_nsstring(cast(string)source), compile_options, *error);
    if log_error_if_not_null(error) {
        log_error("Failed to compile %.", debug_name);
        `return 0;
    }
    if library == null {
        log_error("Failed to create % library", debug_name);
        `return 0;
    }
    `defer release(library);
    return library;
}


#scope_module

Pipeline_Type :: enum {
    GRAPHICS;
    COMPUTE;
}

Shader_Stage :: enum {
    VERTEX  :: 0x1;
    PIXEL   :: 0x10;
    COMPUTE :: 0x20;
    TASK    :: 0x40;
    MESH    :: 0x80;
}

NUM_SHADER_STAGES :: #run enum_values_as_enum(Shader_Stage).count;

Pipeline :: struct {
    type: Pipeline_Type;
    mtl_compute_pipeline: *MTLComputePipelineState;
    mtl_render_pipeline: *MTLRenderPipelineState;
    compute_binding_mode: Compute_Binding_Mode;
    raster_desc: Gpu_Raster_Desc;
    is_mesh_pipeline: bool;
    has_mesh_object_stage: bool;
    required_threads_per_object_threadgroup: MTLSize;
    required_threads_per_mesh_threadgroup: MTLSize;
    max_total_threadgroups_per_mesh_grid: u32;
}

Compute_Binding_Mode :: enum {
    DIRECT_ADDRESSES;
    ROOT_POINTER_STRUCT;
}

live_pipelines: Pool(Gpu_Pipeline, Pipeline);
hot_reload_metallib_copy_counter: u64;

get_pipeline :: (handle: Gpu_Pipeline) -> *Pipeline {
    return pool_get(live_pipelines, handle);
}

#scope_export
gpu_get_mesh_pipeline_max_total_threadgroups_per_grid :: (pipeline_handle: Gpu_Pipeline) -> u32 {
    pipeline := get_pipeline(pipeline_handle);
    if pipeline == null || !pipeline.is_mesh_pipeline return 0;
    return pipeline.max_total_threadgroups_per_mesh_grid;
}

#scope_module

detect_compute_binding_mode :: (metal_source: []u8) -> Compute_Binding_Mode {
    source := cast(string) metal_source;
    if contains(source, "[[kernel]]") && contains(source, "constant*") && contains(source, "[[buffer(0)]]") {
        return .ROOT_POINTER_STRUCT;
    }
    return .DIRECT_ADDRESSES;
}

to_mtl_size :: (size: [3]u32) -> MTLSize {
    return .{ width = size[0], height = size[1], depth = size[2] };
}

fallback_threadgroup_size :: (size: MTLSize) -> MTLSize {
    if size.width == 0 || size.height == 0 || size.depth == 0 {
        return .{ width = 1, height = 1, depth = 1 };
    }
    return size;
}

// Look up a function by a series of names, returning the first one found.
get_function_from_library :: (library: *MTLLibrary, names: ..string) -> *MTLFunction {
    for name: names {
        fn := MTLLibrary.newFunctionWithName(library, to_temp_nsstring(name));
        if fn != null return fn;
    }
    return null;
}

get_function_from_library_with_constants :: (library: *MTLLibrary, constants: *MTLFunctionConstantValues, names: ..string) -> *MTLFunction {
    if constants == null return get_function_from_library(library, ..names);

    for name: names {
        error: *NSError;
        fn := MTLLibrary.newFunctionWithName(library, to_temp_nsstring(name), constants, *error);
        if log_error_if_not_null(error) continue;
        if fn != null return fn;
    }
    return null;
}

blend_factor_to_mtl :: (factor: Factor) -> MTLBlendFactor {
    if factor == {
        case .ZERO;                     return .Zero;
        case .ONE;                      return .One;
        case .SRC_COLOR;                return .SourceColor;
        case .ONE_MINUS_SRC_COLOR;      return .OneMinusSourceColor;
        case .DST_COLOR;                return .DestinationColor;
        case .ONE_MINUS_DST_COLOR;      return .OneMinusDestinationColor;
        case .SRC_ALPHA;                return .SourceAlpha;
        case .ONE_MINUS_SRC_ALPHA;      return .OneMinusSourceAlpha;
        case .DST_ALPHA;                return .DestinationAlpha;
        case .ONE_MINUS_DST_ALPHA;      return .OneMinusDestinationAlpha;
        case .CONSTANT_COLOR;           return .BlendColor;
        case .ONE_MINUS_CONSTANT_COLOR; return .OneMinusBlendColor;
        case .CONSTANT_ALPHA;           return .BlendAlpha;
        case .ONE_MINUS_CONSTANT_ALPHA; return .OneMinusBlendAlpha;
        case .SRC_ALPHA_SATURATE;       return .SourceAlphaSaturated;
    }
    return .Zero;
}

blend_op_to_mtl :: (op: Blend) -> MTLBlendOperation {
    if op == {
        case .ADD;          return .Add;
        case .SUBTRACT;     return .Subtract;
        case .REV_SUBTRACT; return .ReverseSubtract;
        case .MIN;          return .Min;
        case .MAX;          return .Max;
    }
    return .Add;
}

color_write_mask_to_mtl :: (mask: Component_Flags) -> MTLColorWriteMask {
    if mask == .ALL then return cast(MTLColorWriteMask)MTLColorWriteMask_1.All;

    result: MTLColorWriteMask = 0;
    if mask & .R then result |= cast(MTLColorWriteMask) MTLColorWriteMask_1.Red;
    if mask & .G then result |= cast(MTLColorWriteMask) MTLColorWriteMask_1.Green;
    if mask & .B then result |= cast(MTLColorWriteMask) MTLColorWriteMask_1.Blue;
    if mask & .A then result |= cast(MTLColorWriteMask) MTLColorWriteMask_1.Alpha;

    return result;
}

return_if :: (cond: bool, message: string) #expand {
    if cond {
        log_error(message);
        `return;
    }
}

new_scoped_common_mtl_compile_options :: () -> *MTLCompileOptions #expand {
    using opts := objc_new(MTLCompileOptions);
    `defer release(opts);

    // Create compile options with Metal 3.2 language version (required for MTL4)
    setLanguageVersion(opts, ._3_2);
    setEnableLogging(opts, ifx SGPU_ENABLE_SHADER_LOGGING then YES else NO);
    return opts;
}

new_scoped_library_from_file_or_return_0 :: (path: string, debug_name: string) -> *MTLLibrary #expand {
    load_path := path;
    uncached_path := make_uncached_metallib_copy(path);
    if uncached_path.count != 0 load_path = uncached_path;

    error: *NSError;
    library := MTLDevice.newLibraryWithFile(mtl_device, to_temp_nsstring(load_path), *error);
    if log_error_if_not_null(error) {
        log_error("Failed to load % from file '%'.", debug_name, load_path);
        `return 0;
    }
    if library == null {
        log_error("Failed to create % from file '%'.", debug_name, load_path);
        `return 0;
    }
    `defer release(library);
    return library;
}

make_uncached_metallib_copy :: (path: string) -> string {
    source_bytes, read_ok := File.read_entire_file(path);
    if !read_ok return "";
    hot_reload_metallib_copy_counter += 1;
    copy_path := tprint("%.__sgpu_hot_%.metallib", path, hot_reload_metallib_copy_counter);
    if !File.write_entire_file(copy_path, source_bytes) return "";
    free(source_bytes);
    return copy_path;
}

// TODO: this could accept constants and create the function with them
get_only_function_by_type :: (library: *MTLLibrary, type: MTLFunctionType) -> *MTLFunction {
    auto_release_temp();

    fns:      [..]*MTLFunction; fns.allocator = temp;
    fn_names: [..]string;       fn_names.allocator = temp;
    defer for fn_names free(it);

    for library.functionNames(library) {
        fn := MTLLibrary.newFunctionWithName(library, it);
        if fn == null continue;
        if fn.functionType(fn) != type {
            release(fn);
            continue;
        }

        array_add(*fns, fn);
        array_add(*fn_names, copy_string(to_string(it)));
    }

    if fns.count == 0 {
        log_error("No % function found in library", type);
        return null;
    }

    if fns.count > 1 {
        log_error("% % functions found in library, expected exactly 1. Names: %",
            fns.count, type, join(..fn_names, separator=", "));
        for fns release(it);
        return null;
    }

    assert(fns.count == 1);
    return fns[0];
}

get_optional_function_by_type :: (library: *MTLLibrary, type: MTLFunctionType) -> *MTLFunction {
    auto_release_temp();

    found: *MTLFunction = null;
    matches := 0;
    for library.functionNames(library) {
        fn := MTLLibrary.newFunctionWithName(library, it);
        if fn == null continue;
        if fn.functionType(fn) != type {
            release(fn);
            continue;
        }

        matches += 1;
        if matches == 1 {
            found = fn;
        } else {
            release(fn);
        }
    }

    if matches == 0 return null;
    if matches > 1 {
        if found != null release(found);
        log_error("% % functions found in library, expected at most 1.", matches, type);
        return null;
    }
    return found;
}

NSUTF8StringEncoding :: 4;

#scope_file
File :: #import "File";
String :: #import "String";

for_expansion :: (array: *$T/NSArray, body: Code, flags: For_Flags) #expand {
    assert(array != null, "for_expansion for NSArray received a null pointer");
    #assert(flags == 0);
    for i: 0..array.count(array) - 1 {
        `it := array.objectAtIndex(array, i);
        `it_index := i;
        #insert(remove=#assert(false)) body;
    }
}
