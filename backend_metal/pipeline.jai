#scope_export

gpu_create_meshlets_pipeline :: (meshlets_spirv: [] u8, pixel_spirv: [] u8, raster_desc: Gpu_Raster_Desc) -> Gpu_Pipeline {
    return 0;
}

gpu_draw_meshlets :: (cmd: Gpu_Command_Buffer, data: Gpu_Ptr, dimensions: [3] u32) -> Gpu_Result {
    return .SUCCESS;
}

gpu_create_compute_pipeline :: (metal_source: []u8) -> Gpu_Pipeline {

    error: *NSError;
    mtl_library := MTLDevice.newLibraryWithSource(mtl_device, to_temp_nsstring(cast(string)metal_source), compile_options, *error);
    defer if mtl_library release(mtl_library);
    if log_error_if_not_null(error) || mtl_library == null {
        log_error("Failed to create Metal library");
        return 0;
    }

    // Get the entry point function from the library
    // Try "computeMain" first (our convention), then fall back to "main"
    mtl_function := get_function_from_library(mtl_library, "computeMain", "main", "main_0");
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
        mtl_compute_pipeline = mtl_pipeline
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

_internal_gpu_create_graphics_pipeline :: (vertex_library: *MTLLibrary, pixel_library: *MTLLibrary, raster_desc: Gpu_Raster_Desc) -> Gpu_Pipeline {
    // Get vertex function - try various names (Slang may rename "main" to "main_0")
    vertex_function := get_only_function_by_type(vertex_library, .Vertex);
    //vertex_function := get_function_from_library(vertex_library, "vertexMain", "vertexMain_0", "main", "main_0");
    if vertex_function == null {
        log_error("Failed to automatically find vertex function in shader");
        return 0;
    }
    defer release(vertex_function);

    // Get fragment function - try various names (Slang may rename "main" to "main_0")
    fragment_function := get_only_function_by_type(pixel_library, .Fragment);
    //fragment_function := get_function_from_library(pixel_library, "fragmentMain", "fragmentMain_0", "main", "main_0");
    if fragment_function == null {
        log_error("Failed to automatically find fragment function in shader");
        return 0;
    }
    defer release(fragment_function);

    func_desc :: (mtl_library: *MTLLibrary, function: *MTLFunction) -> *MTL4LibraryFunctionDescriptor #expand {
        using func_desc := objc_new(MTL4LibraryFunctionDescriptor);
        `defer release(func_desc);
        setLibrary(func_desc, mtl_library);
        setName(func_desc, MTLFunction.name(function));
        return func_desc;
    }

    // Create MTL4 render pipeline descriptor
    pipeline_desc := objc_new_defer_release(MTL4RenderPipelineDescriptor);
    pipeline_desc.setVertexFunctionDescriptor(pipeline_desc, func_desc(vertex_library, vertex_function));
    pipeline_desc.setFragmentFunctionDescriptor(pipeline_desc, func_desc(pixel_library, fragment_function));

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

    add_to_residency(render_pipeline);
    handle := pool_add(*live_pipelines, .{
        type = .GRAPHICS,
        mtl_compute_pipeline = null,
        mtl_render_pipeline = render_pipeline,
    });

    return handle;
}

gpu_free_pipeline :: (pipeline_handle: Gpu_Pipeline) {
    removed, pipeline := pool_remove(*live_pipelines, pipeline_handle);
    if !removed return;

    using pipeline;
    release_and_set_null(*mtl_compute_pipeline);
    release_and_set_null(*mtl_render_pipeline);
}

gpu_dispatch :: (cmd: Gpu_Command_Buffer, data: Gpu_Ptr, dimensions: [3] u32) {
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

    indirect_buffer := get_indirect_params_buffer(get_queue(cmd_info.queue), data, 0);

    // Ensure bindless argument table is initialized
    assert(argument_tables.compute != null);
    MTL4ArgumentTable.setAddress(argument_tables.compute, indirect_buffer.gpuAddress(indirect_buffer), 0);
    MTL4ComputeCommandEncoder.setArgumentTable(compute_encoder, argument_tables.compute);

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
}

live_pipelines: Pool(Gpu_Pipeline, Pipeline);

get_pipeline :: (handle: Gpu_Pipeline) -> *Pipeline {
    return pool_get(live_pipelines, handle);
}

// Look up a function by a series of names, returning the first one found.
get_function_from_library :: (library: *MTLLibrary, names: ..string) -> *MTLFunction {
    for name: names {
        fn := MTLLibrary.newFunctionWithName(library, to_temp_nsstring(name));
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

// TODO: this could accept constants and create the function with them
get_only_function_by_type :: (library: *MTLLibrary, type: MTLFunctionType) -> *MTLFunction {
    auto_release_temp();

    fns:      [..]*MTLFunction; fns.allocator = temp;
    fn_names: [..]string;       fn_names.allocator = temp;
    defer for fn_names free(it);

    for library.functionNames(library) {
        fn := library.newFunctionWithName(library, it);
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

NSUTF8StringEncoding :: 4;

#scope_file

for_expansion :: (array: *$T/NSArray, body: Code, flags: For_Flags) #expand {
    assert(array != null, "for_expansion for NSArray received a null pointer");
    #assert(flags == 0);
    for i: 0..array.count(array) - 1 {
        `it := array.objectAtIndex(array, i);
        `it_index := i;
        #insert(remove=#assert(false)) body;
    }
}
