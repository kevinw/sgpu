#scope_export

compile_shader :: (shader_path: string, write_output: bool = false, debug_symbols: bool = false) -> bool, []u8 {
    if !global_session then create_session();

    auto_release_temp();

    options: [..] slang.CompilerOptionEntry;
    options.allocator = temp;
    array_add(*options, .{
        slang.CompilerOptionName.Language, .{
            slang.CompilerOptionValueKind.String, 0, 0, "slang", null
        }
    });

    // Use Metal capability instead of SPIR-V
    array_add(*options, .{
        slang.CompilerOptionName.Capability, .{
            slang.CompilerOptionValueKind.Int, xx slang.IGlobalSession_findCapability(global_session, "metal"), 0, null, null
        }
    });

    if debug_symbols {
        array_add(*options, .{
            slang.CompilerOptionName.DebugInformation, .{
                slang.CompilerOptionValueKind.Int, 2, 0, null, null
            }
        });
    }

    // Target Metal shading language
    // Use metal profile for macOS
    target_desc := slang.TargetDesc.{
        format = .SLANG_METAL,
        profile = slang.IGlobalSession_findProfile(global_session, "sm_6_0"),
        compilerOptionEntries = options.data,
        compilerOptionEntryCount = xx options.count,
    };

    source_dir := path_strip_filename(shader_path);
    search_paths := temp_c_string(source_dir);

    session_desc := slang.SessionDesc.{
        targets = *target_desc,
        targetCount = 1,
        defaultMatrixLayoutMode = .ROW_MAJOR,
        searchPaths = *search_paths,
        searchPathCount = 1,
        compilerOptionEntries = options.data,
        compilerOptionEntryCount = xx options.count,
    };

    session: *slang.ISession;
    slang.IGlobalSession_createSession(global_session, *session_desc, *session);
    if !session then return false, {};
    defer slang.ISlangUnknown_release(session);

    diagnostic_blob: *slang.IBlob = null;

    slang_module := slang.ISession_loadModule(session, temp_c_string(shader_path), *diagnostic_blob);
    log_blob_if_nonnull(*diagnostic_blob);
    if !slang_module then return false, {};

    entry_points: [..] *slang.IEntryPoint;
    entry_points.allocator = temp;
    {
        main := array_add(*entry_points);
        // Try "computeMain" first, then fall back to "main"
        slang.IModule_findEntryPointByName(slang_module, "computeMain", main);
        if main.* == null {
            slang.IModule_findEntryPointByName(slang_module, "main", main);
        }
    }

    components: [..] *slang.IComponentType;
    components.allocator = temp;
    array_add(*components, slang_module);
    for entry_points {
        array_add(*components, it);
    }

    composed_program: *slang.IComponentType;
    slang.ISession_createCompositeComponentType(session, components.data, components.count, *composed_program, *diagnostic_blob);
    log_blob_if_nonnull(*diagnostic_blob);
    if !composed_program then return false, {};
    defer slang.ISlangUnknown_release(composed_program);

    linked_program: *slang.IComponentType;
    link_result := slang.IComponentType_link(composed_program, *linked_program, *diagnostic_blob);
    log_blob_if_nonnull(*diagnostic_blob);
    if !slang.SLANG_SUCCEEDED(link_result) || !linked_program then return false, {};
    defer slang.ISlangUnknown_release(linked_program);

    metal_code: *slang.IBlob = null;
    slang.IComponentType_getEntryPointCode(linked_program, 0, 0, *metal_code, *diagnostic_blob);
    log_blob_if_nonnull(*diagnostic_blob);
    if !metal_code then return false, {};
    defer slang.ISlangUnknown_release(metal_code);

    // Get the Metal source as a string
    metal_source: string = {
        data  =    slang.ISlangBlob_getBufferPointer(metal_code),
        count = xx slang.ISlangBlob_getBufferSize(metal_code),
    };

    // Copy to a new allocation since the blob will be released
    result := copy_string(metal_source);

    if write_output {
        output_directory := path_strip_filename(shader_path);
        output_path := tprint("%/%.generated.metal", output_directory, path_strip_extension(path_filename(shader_path)));
        File.write_entire_file(output_path, result);
    }

    return true, { result.count, result.data };
}

#scope_module

gpu_internal_slang_shutdown :: () {
    if global_session != null {
        slang.ISlangUnknown_release(global_session);
        global_session = null;
    }
    slang.slang_shutdown();
}

#scope_file

create_session :: () {
    result := slang.slang_createGlobalSession(slang.SLANG_API_VERSION, *global_session);
    assert(slang.SLANG_SUCCEEDED(result));
}

log_blob_if_nonnull :: (blob_ptr: **slang.IBlob) {
    if blob_ptr.* == null return;

    blob := blob_ptr.*;

    diagnostic_string := string.{
        data = slang.ISlangBlob_getBufferPointer(blob),
        count = xx slang.ISlangBlob_getBufferSize(blob),
    };

    log_error("%", diagnostic_string);

    slang.ISlangUnknown_release(blob);
    blob_ptr.* = null;
}


global_session: *slang.IGlobalSession;

slang :: #import,file "../modules/slang/module.jai";
File :: #import "File";
