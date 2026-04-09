#module_parameters()(
    // Optionally enables Vulkan/Metal validation layers.
    VALIDATION := false,
    // Optionally enables debug assertions within the sgpu module
    DEBUG_ASSERTS := false,
    // Optionally includes an api for taking render doc captures
    RENDER_CAPTURE := false,
    // Optionally includes a slang shader compiler submodule
    SLANG_COMPILER := true
);

Gpu_Ptr :: #type,distinct u64;

CPU_Struct :: struct (T: Type)  {
    GPU_Type :: T;

    #insert #run,stallable -> string {
        sb: String_Builder;
        for type_info(T).members {
            print_to_builder(*sb, "    %: ", it.name);
            if it.type.type == {
            case .POINTER;
                append(*sb, "Gpu_Ptr;\n");
                /*
                ti_pointer := it.type.(*Type_Info_Pointer);
                append(*sb, "Typed_Gpu_Ptr(");
                print_type_to_builder(*sb, ti_pointer.pointer_to);
                append(*sb, ");\n");
                */
            case;
                print_type_to_builder(*sb, it.type);
                append(*sb, ";\n");
            }
        }

        output := builder_to_string(*sb);

        //print("------\n");
        //log("%", output);
        //print("------\n");

        return output;
    };
}

Memory_Type :: enum {
    DEFAULT;
    GPU;
    READBACK;
}

gpu_log_memory_leaks :: () -> (has_leaks: bool) {
    has_leaks := false;

    show :: (table: $H, name: string) #expand {
        if table.count == 0 return;

        if !has_leaks log("NOTE: sgpu leaks detected:");
        log("%.count: %", name, gpu_allocations.count);
        for table log("  %", FormatStruct.{value=it});
        `has_leaks = true;
    }

    show(cpu_allocations, "cpu_allocations");
    show(gpu_allocations, "gpu_allocations");

    return has_leaks;
}

#if OS == .MACOS {
    #load "backend_metal/sgpu_metal.jai";
} else {
    gpu_commit_residency :: () {} // TODO
    gpu_push_frame :: () {} // TODO

    #load "backend_vulkan/sgpu_vulkan.jai";
}
