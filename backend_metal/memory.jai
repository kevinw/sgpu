Gpu_Ptr :: #type,distinct u64;

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

gpu_malloc :: ($type: Type, memory_type: Memory_Type = .DEFAULT, label := "") -> (mapped: *type, gpu: Gpu_Ptr) {
    cpu_ptr, gpu_ptr := gpu_malloc(size_of(type), memory_type, label);
    return cpu_ptr.(*type), gpu_ptr;
}

gpu_malloc :: (size: s64, memory_type: Memory_Type = .DEFAULT, label := "") -> (mapped: *void, gpu: Gpu_Ptr) {
    // Determine Metal storage mode based on memory type
    options: MTLResourceOptions;
    if #complete memory_type == {
        case .DEFAULT;
            // Shared storage - accessible by both CPU and GPU
            options = cast(MTLResourceOptions) MTLResource.StorageModeShared;
        case .GPU;
            // Private storage - only accessible by GPU
            options = cast(MTLResourceOptions) MTLResource.StorageModePrivate;
        case .READBACK;
            // Shared storage for readback (same as DEFAULT on unified memory architecture)
            options = cast(MTLResourceOptions) MTLResource.StorageModeShared;
    }

    // Create the Metal buffer
    mtl_buffer := MTLDevice.newBufferWithLength(mtl_device, size.(NSUInteger), options);
    assert(mtl_buffer != null);
    if mtl_buffer == null {
        log_error("Could not create MTLBuffer with size % and options %", size, options);
        return null, 0;
    }

    if label {
        mtl_buffer.setLabel(mtl_buffer, to_temp_nsstring(label));
    }

    add_to_residency(mtl_buffer);

    // Get the GPU address
    gpu_ptr := cast(Gpu_Ptr) mtl_buffer.gpuAddress(mtl_buffer);
    if gpu_ptr == 0 {
        // Failed to get GPU address - this shouldn't happen on modern Metal
        // Release the buffer (Metal uses reference counting, but we created it)
        release(mtl_buffer);
        return null, 0;
    }

    // Build allocation info
    result: Alloc_Info = {
        mtl_buffer = mtl_buffer,
        gpu_ptr = gpu_ptr,
        type = memory_type,
        size = size,
    };

    // Get CPU pointer if applicable
    mapped: *void = null;
    if memory_type != .GPU {
        mapped = MTLBuffer.contents(mtl_buffer);
        table_add(*cpu_allocations, mapped, result);
        // log("added cpu_allocation(cpu=%, gpu=%), new cpu_allocations.count is %", mapped, gpu_ptr, cpu_allocations.count);
    }

    table_add(*gpu_allocations, gpu_ptr, result);
    array_add(*gpu_memory_ranges, .{start = gpu_ptr, end = gpu_ptr + size.(Gpu_Ptr)});

    return mapped, gpu_ptr;
}

gpu_free :: (ptr: *void) {
    removed, alloc := table_remove(*cpu_allocations, ptr);
    // log("after gpu_free(cpu=%), cpu_allocations.count is %", ptr, cpu_allocations.count);
    if !removed {
        log_error("gpu_free: allocation for cpu ptr % not found", ptr);
        return;
    }

    release(alloc.mtl_buffer);

    removed = table_remove(*gpu_allocations, alloc.gpu_ptr);
    debug_assert(removed);

    removed = remove_gpu_memory_range(alloc.gpu_ptr);
    debug_assert(removed);
}

gpu_free :: (gpu_ptr: Gpu_Ptr) {
    removed, alloc := table_remove(*gpu_allocations, gpu_ptr);
    if removed {
        release(alloc.mtl_buffer);

        removed = remove_gpu_memory_range(alloc.gpu_ptr);
        debug_assert(removed);
    }
}

gpu_host_to_device_ptr :: (host: *void) -> Gpu_Ptr {
    found, alloc := table_find(*cpu_allocations, host);
    if found {
        return alloc.gpu_ptr;
    }
    return 0;
}

#scope_module

Alloc_Info :: struct {
    mtl_buffer: *MTLBuffer;
    gpu_ptr: Gpu_Ptr;
    type: Memory_Type;
    size: s64;
}

/** Maps the mapped cpu accessible pointer to a given gpu memory allocation */
cpu_allocations: Table(*void, Alloc_Info);
/** Maps the gpu accessible pointer to a given gpu memory allocation */
gpu_allocations: Table(Gpu_Ptr, Alloc_Info);

Gpu_Memory_Range :: struct {
    start: Gpu_Ptr;
    end: Gpu_Ptr;
}

// Store memory ranges for lookup during copies
gpu_memory_ranges: [..] Gpu_Memory_Range;

find_memory_range :: (ptr: Gpu_Ptr) -> Gpu_Result, Gpu_Memory_Range {
    for gpu_memory_ranges {
        if ptr >= it.start && ptr < it.end then return .SUCCESS, it;
    }
    return .ERROR_UNKNOWN_GPU_POINTER, .{};
}

remove_gpu_memory_range :: (start_ptr: Gpu_Ptr) -> bool {
    for gpu_memory_ranges {
        if it.start == start_ptr {
            remove it;
            return true;
        }
    }
    return false;
}

get_buffer :: (gpu_ptr: Gpu_Ptr) -> *MTLBuffer {
    found, alloc := table_find(*gpu_allocations, gpu_ptr);
    if !found {
        return null;
    }
    return alloc.mtl_buffer;
}

get_buffer_and_offset :: (gpu_ptr: Gpu_Ptr) -> Gpu_Result, *MTLBuffer, s64 {
    result, range := find_memory_range(gpu_ptr);
    if result != .SUCCESS then return result, null, 0;
    debug_assert(range.start != 0);

    mtl_buffer := get_buffer(range.start);
    debug_assert(mtl_buffer != null);
    return .SUCCESS, mtl_buffer, (gpu_ptr - range.start).(s64);
}

#import "Hash_Table";
