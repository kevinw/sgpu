//
// Slang -> Metal
//

// TODO: Tunables below:
// defaultMatrixLayoutMode = .ROW_MAJOR,
// searchPaths = *search_paths,

compile_shader :: (shader_path: string, entry_points: []string, write_output: bool = false, debug_symbols: bool = false) -> bool, []u8 {
    if !global_session create_session();

    auto_release_temp();

    metal_capability := IGlobalSession_findCapability(global_session, "metal");
    assert(metal_capability != 0, "slang: Could not find 'metal' Capability");

    options: [..] CompilerOptionEntry;
    options.allocator = temp;
    array_add(*options,     { .Language, { .String, 0, 0, "slang", null } });
    array_add(*options,     { .Capability, .{ .Int, xx metal_capability, 0, null, null } });
    if debug_symbols
        array_add(*options, { .DebugInformation, .{ .Int, 2, 0, null, null } });

    target_profile := IGlobalSession_findProfile(global_session, "sm_6_0");
    assert(target_profile != 0, "Did not find 'sm_6_0' profile");

    target_desc := TargetDesc.{
        format = .SLANG_METAL,
        profile = target_profile,
        compilerOptionEntries = options.data,
        compilerOptionEntryCount = xx options.count,
    };

    source_dir := path_strip_filename(shader_path);
    search_paths := temp_c_string(source_dir);

    session_desc := SessionDesc.{
        targets = *target_desc,
        targetCount = 1,
        defaultMatrixLayoutMode = .ROW_MAJOR,
        searchPaths = *search_paths,
        searchPathCount = 1,
        compilerOptionEntries = options.data,
        compilerOptionEntryCount = xx options.count,
    };

    session: *ISession;
    IGlobalSession_createSession(global_session, *session_desc, *session);
    if !session then return false, {};
    defer ISlangUnknown_release(session);

    diagnostic_blob: *IBlob = null;
    slang_module := ISession_loadModule(session, temp_c_string(shader_path), *diagnostic_blob);
    log_blob_if_nonnull(*diagnostic_blob);
    if !slang_module then return false, {};

    entry_point_ptrs: [..] *IEntryPoint;
    entry_point_ptrs.allocator = temp;
    for entry_points {
        main := array_add(*entry_point_ptrs);
        IModule_findEntryPointByName(slang_module, temp_c_string(it), main);
        if main.* == null {
            log_error("slang: entry point '%' not found in %", it, shader_path);
            return false, {};
        } else {
            #if VERBOSE log("slang: entry point '%' found.", it);
        }
    }

    components: [..] *IComponentType;
    components.allocator = temp;
    array_add(*components, slang_module);
    for entry_point_ptrs {
        if it array_add(*components, it);
    }

    composed_program: *IComponentType;
    composite_result := ISession_createCompositeComponentType(session, components.data, components.count, *composed_program, *diagnostic_blob);
    log_blob_if_nonnull(*diagnostic_blob);
    if !SLANG_SUCCEEDED(composite_result) || !composed_program return false, {};
    defer ISlangUnknown_release(composed_program);

    linked_program: *slang.IComponentType;
    link_result := slang.IComponentType_link(composed_program, *linked_program, *diagnostic_blob);
    log_blob_if_nonnull(*diagnostic_blob);
    if !SLANG_SUCCEEDED(link_result) || !linked_program return false, {};
    defer ISlangUnknown_release(linked_program);

    metal_code: *slang.IBlob = null;
    code_result: SlangResult;
    if entry_points.count > 1 {
        // Multiple entry points
        code_result = slang.IComponentType_getTargetCode(linked_program, 0, *metal_code, *diagnostic_blob);
    } else {
        code_result = slang.IComponentType_getEntryPointCode(linked_program, 0, 0, *metal_code, *diagnostic_blob);
    }
    log_blob_if_nonnull(*diagnostic_blob);
    if !SLANG_SUCCEEDED(code_result) || !metal_code return false, {};
    defer slang.ISlangUnknown_release(metal_code);

    // Get the Metal source as a string
    metal_source: string = {
        data  =    ISlangBlob_getBufferPointer(metal_code),
        count = xx ISlangBlob_getBufferSize(metal_code),
    };

    #if VERBOSE log("slang: % slang bytes became % metal bytes", file_length(shader_path), metal_source.count);

    // Copy to a new allocation since the blob will be released
    result := copy_string(metal_source);

    if write_output {
        output_directory := path_strip_filename(shader_path);
        output_path := tprint("%/%.generated.metal", output_directory, path_strip_extension(path_filename(shader_path)));
        File.write_entire_file(output_path, result);
    }

    return true, { result.count, result.data };
}

gpu_internal_slang_shutdown :: () {
    if global_session != null {
        ISlangUnknown_release(global_session);
        global_session = null;
    }
    slang_shutdown();
}

#scope_file

create_session :: () {
    result := slang_createGlobalSession(SLANG_API_VERSION, *global_session);
    assert(SLANG_SUCCEEDED(result));
}

log_blob_if_nonnull :: (blob_ptr: **slang.IBlob) {
    if blob_ptr.* == null return;

    blob := blob_ptr.*;

    diagnostic_string := string.{
        data = ISlangBlob_getBufferPointer(blob),
        count = xx ISlangBlob_getBufferSize(blob),
    };

    log_error("%", diagnostic_string);

    ISlangUnknown_release(blob);
    blob_ptr.* = null;
}


global_session: *IGlobalSession;

using slang :: #import,file "../modules/slang/module.jai";
File :: #import "File";
VERBOSE :: false;
