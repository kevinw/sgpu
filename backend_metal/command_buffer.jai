
gpu_get_queue :: (queue_type: Gpu_Queue_Type, queue_index: u32) -> Gpu_Queue {
    for queues {
        if it.type == queue_type && it.index_in_type == queue_index {
            return (it_index + 1).(Gpu_Queue);
        }
    }

    return 0;
}

gpu_start_command_recording :: (queue_handle: Gpu_Queue) -> Gpu_Result, Gpu_Command_Buffer {
    queue := get_queue(queue_handle);
    if queue == null return .FATAL_ERROR_UNKNOWN, 0;

    allocator := queue.command_allocators[frame_index % MAX_FRAMES_IN_FLIGHT];
    assert(allocator != null);
    allocator.reset(allocator);

    cmd_buffer := get_available_command_buffer(queue);
    if cmd_buffer == null {
        log_error("Failed to create command buffer");
        return .ERROR_COMMAND_BUFFER_LIMIT_EXCEEDED, 0;
    }

    // Begin the command buffer with the allocator
    cmd_buffer.beginCommandBufferWithAllocator(cmd_buffer, allocator);

    // Store the command buffer info
    cmd_info: Command_Buffer_Info = { cmd_buffer = cmd_buffer, queue = queue_handle };

    // Find an empty slot in live command buffers
    found_slot := false;
    slot_index: s64 = -1;
    for * live_command_buffers {
        if it.cmd_buffer == null {
            assert(it.current_compute_encoder == null && it.current_render_encoder == null);
            it.* = cmd_info;
            slot_index = it_index;
            found_slot = true;
            break;
        }
    }

    if !found_slot {
        slot_index = live_command_buffers.count;
        array_add(*live_command_buffers, cmd_info);
    }

    cmd_buff_handle := cast(Gpu_Command_Buffer) (slot_index + 1);

    return .SUCCESS, cmd_buff_handle;
}

gpu_memcpy :: (cmd: Gpu_Command_Buffer, dest: Gpu_Ptr, src: Gpu_Ptr, num_bytes: s64) -> Gpu_Result {
    cmd_info := get_cmd_info(cmd);
    if cmd_info == null return .ERROR_INVALID_BUFFER;

    dest_result, dest_buffer, dest_offset := get_buffer_and_offset(dest);
    if dest_result != .SUCCESS return dest_result;

    src_result, src_buffer, src_offset := get_buffer_and_offset(src);
    if src_result != .SUCCESS return src_result;

    // End any render encoder before starting compute/blit
    end_current_render_encoder(cmd_info);

    // Get or create the MTL4 compute encoder (handles blit operations in Metal 4)
    compute_encoder := ensure_compute_encoder(cmd_info);
    if compute_encoder == null return .FATAL_ERROR_UNKNOWN;

    // Perform the copy using MTL4ComputeCommandEncoder
    MTL4ComputeCommandEncoder.copyFromBuffer(
        compute_encoder,
        src_buffer,
        src_offset.(NSUInteger),
        dest_buffer,
        dest_offset.(NSUInteger),
        num_bytes.(NSUInteger)
    );

    return .SUCCESS;
}

gpu_barrier :: (cmd: Gpu_Command_Buffer, src_stage: Stage, dst_stage: Stage) {
    using cmd_info := get_cmd_info(cmd);
    if cmd_info == null then return;

    // TODO!

    if current_compute_encoder != null  end_current_compute_encoder(cmd_info);
    if current_render_encoder != null   end_current_render_encoder(cmd_info);
}

gpu_submit :: (cmd_buff: Gpu_Command_Buffer, signals: [] Gpu_Timeline_Pair = .[], waits: [] Gpu_Timeline_Pair = .[]) {
    cmd_info := get_cmd_info(cmd_buff);
    return_if_null(cmd_info);

    queue := get_queue(cmd_info.queue);
    return_if_null(queue);

    // End any active encoder
    end_current_compute_encoder(cmd_info);
    end_current_render_encoder(cmd_info);

    // End the command buffer recording
    MTL4CommandBuffer.endCommandBuffer(cmd_info.cmd_buffer);

    // Submit via MTL4 command queue
    MTL4CommandQueue.commit(queue.mtl4_queue, *cmd_info.cmd_buffer, 1);
    free_command_buffer(queue, cmd_info);
}

gpu_wait_idle :: () {
    // Wait for all queues to complete using shared events
    for * queues {
        if it.mtl4_queue == null continue;
        // Create a shared event for synchronization
        event := mtl_device.newSharedEvent(mtl_device);
        assert(event != null);
        if event == null then continue;
        defer release(event);

        // Signal the event after all pending work
        signal_value: u64 = 1;
        it.mtl4_queue.signalEvent(it.mtl4_queue, event, signal_value);
        event.waitUntilSignaledValue(event, signal_value, milliseconds=U64_MAX);
    }

    for * live_command_buffers {
        using it;
        assert(it.current_compute_encoder == null);
        assert(it.current_render_encoder == null);
        assert(it.cmd_buffer == null);
    }
}

gpu_queue_wait_idle :: (queue_handle: Gpu_Queue) {
    queue := get_queue(queue_handle);
    if queue == null || queue.mtl4_queue == null then return;

    // Create a shared event for synchronization
    {
        event := MTLDevice.newSharedEvent(mtl_device);
        assert(event != null);
        defer release(event);

        // Signal the event after all pending work on this queue
        signal_value: u64 = 1;
        MTL4CommandQueue.signalEvent(queue.mtl4_queue, event, signal_value);
        MTLSharedEvent.waitUntilSignaledValue(event, signal_value, milliseconds=U64_MAX);
    }
}

gpu_begin_render_pass :: (cmd: Gpu_Command_Buffer, desc: Gpu_Render_Pass_Desc) -> Gpu_Result {
    cmd_info := get_cmd_info(cmd);
    if cmd_info == null then return .ERROR_INVALID_BUFFER;

    // End any active compute encoder before starting render
    end_current_compute_encoder(cmd_info);

    auto_release_temp();

    // Create MTL4 render pass descriptor
    pass_desc := objc_new_defer_release(MTL4RenderPassDescriptor);

    // Configure color attachments
    color_attachments := MTL4RenderPassDescriptor.colorAttachments(pass_desc);

    render_width: u32 = 0;
    render_height: u32 = 0;

    for desc.color_targets {
        view := get_texture_view(it.view);
        if view == null return .ERROR_INVALID_TEXTURE;

        if view.mtl_texture != null {
            // Use live Metal texture dimensions (swapchain-backed textures can change independently
            // from cached descriptor metadata).
            render_width = MTLTexture.width(view.mtl_texture).(u32);
            render_height = MTLTexture.height(view.mtl_texture).(u32);
        }

        using color_attachment := MTLRenderPassColorAttachmentDescriptorArray.objectAtIndexedSubscript(color_attachments, it_index.(NSUInteger));
        setTexture(color_attachment, view.mtl_texture);
        setLoadAction(color_attachment, load_op_to_mtl(it.load_op));
        setStoreAction(color_attachment, store_op_to_mtl(it.store_op));
        if it.load_op == .CLEAR {
            setClearColor(color_attachment, {
                red   = it.clear_color._float[0].(float64),
                green = it.clear_color._float[1].(float64),
                blue  = it.clear_color._float[2].(float64),
                alpha = it.clear_color._float[3].(float64),
            });
        }
    }

    // Configure depth attachment if present
    if desc.depth_target.view != 0 {
        view := get_texture_view(desc.depth_target.view);
        if view != null {
            if view.mtl_texture != null {
                // Keep viewport/scissor aligned to the actual depth attachment size.
                render_width = MTLTexture.width(view.mtl_texture).(u32);
                render_height = MTLTexture.height(view.mtl_texture).(u32);
            }

            depth_attachment := MTL4RenderPassDescriptor.depthAttachment(pass_desc);
            MTLRenderPassDepthAttachmentDescriptor.setTexture(depth_attachment, view.mtl_texture);
            MTLRenderPassDepthAttachmentDescriptor.setLoadAction(depth_attachment, load_op_to_mtl(desc.depth_target.load_op));
            MTLRenderPassDepthAttachmentDescriptor.setStoreAction(depth_attachment, store_op_to_mtl(desc.depth_target.store_op));
            MTLRenderPassDepthAttachmentDescriptor.setClearDepth(depth_attachment, desc.depth_target.clear_value.depth.(float64));
        }
    }

    // Configure stencil attachment if present
    if desc.stencil_target.view != 0 {
        view := get_texture_view(desc.stencil_target.view);
        if view != null {
            stencil_attachment := MTL4RenderPassDescriptor.stencilAttachment(pass_desc);
            MTLRenderPassStencilAttachmentDescriptor.setTexture(stencil_attachment, view.mtl_texture);
            MTLRenderPassStencilAttachmentDescriptor.setLoadAction(stencil_attachment, load_op_to_mtl(desc.stencil_target.load_op));
            MTLRenderPassStencilAttachmentDescriptor.setStoreAction(stencil_attachment, store_op_to_mtl(desc.stencil_target.store_op));
            MTLRenderPassStencilAttachmentDescriptor.setClearStencil(stencil_attachment, desc.stencil_target.clear_value.stencil);
        }
    }

    // Create the render command encoder
    render_encoder := MTL4CommandBuffer.renderCommandEncoderWithDescriptor(cmd_info.cmd_buffer, pass_desc);

    if render_encoder == null {
        log_error("Could not create render command encoder");
        return .FATAL_ERROR_UNKNOWN;
    }

    cmd_info.current_render_encoder = render_encoder;
    //cmd_info.render_width = render_width;
    //cmd_info.render_height = render_height;

    // TODO: are these needed for a new render encoder?

    // Set default viewport and scissor
    render_encoder.setViewport(render_encoder, {
        originX = 0, originY = 0,
        width = render_width.(float64), height = render_height.(float64),
        znear = 0, zfar = 1,
    });

    render_encoder.setScissorRect(render_encoder, { 0, 0, render_width.(NSUInteger), render_height.(NSUInteger), });

    return .SUCCESS;
}

gpu_end_render_pass :: (cmd: Gpu_Command_Buffer) {
    cmd_info := get_cmd_info(cmd);
    if cmd_info == null then return;

    end_current_render_encoder(cmd_info);
}

gpu_set_depth_stencil_state :: (cmd: Gpu_Command_Buffer, desc: Gpu_Depth_Stencil_Desc) {
    using cmd_info := get_cmd_info(cmd);
    if cmd_info == null || cmd_info.current_render_encoder == null then return;

    // Create depth stencil state
    depth_desc := objc_new_defer_release(MTLDepthStencilDescriptor);

    // Set depth compare function
    MTLDepthStencilDescriptor.setDepthCompareFunction(depth_desc, compare_op_to_mtl(desc.depth_test));

    // Set depth write enable
    depth_write := (desc.depth_mode & .WRITE) != 0;
    MTLDepthStencilDescriptor.setDepthWriteEnabled(depth_desc, ifx depth_write then YES else NO);

    // Configure front face stencil if needed
    if desc.stencil_front.test != .NEVER || desc.stencil_back.test != .NEVER {
        front_stencil := MTLDepthStencilDescriptor.frontFaceStencil(depth_desc);
        MTLStencilDescriptor.setStencilCompareFunction(front_stencil, compare_op_to_mtl(desc.stencil_front.test));
        MTLStencilDescriptor.setStencilFailureOperation(front_stencil, stencil_op_to_mtl(desc.stencil_front.fail_op));
        MTLStencilDescriptor.setDepthFailureOperation(front_stencil, stencil_op_to_mtl(desc.stencil_front.depth_fail_op));
        MTLStencilDescriptor.setDepthStencilPassOperation(front_stencil, stencil_op_to_mtl(desc.stencil_front.pass_op));
        MTLStencilDescriptor.setReadMask(front_stencil, desc.stencil_read_mask.(u32));
        MTLStencilDescriptor.setWriteMask(front_stencil, desc.stencil_write_mask.(u32));

        back_stencil := MTLDepthStencilDescriptor.backFaceStencil(depth_desc);
        MTLStencilDescriptor.setStencilCompareFunction(back_stencil, compare_op_to_mtl(desc.stencil_back.test));
        MTLStencilDescriptor.setStencilFailureOperation(back_stencil, stencil_op_to_mtl(desc.stencil_back.fail_op));
        MTLStencilDescriptor.setDepthFailureOperation(back_stencil, stencil_op_to_mtl(desc.stencil_back.depth_fail_op));
        MTLStencilDescriptor.setDepthStencilPassOperation(back_stencil, stencil_op_to_mtl(desc.stencil_back.pass_op));
        MTLStencilDescriptor.setReadMask(back_stencil, desc.stencil_read_mask.(u32));
        MTLStencilDescriptor.setWriteMask(back_stencil, desc.stencil_write_mask.(u32));
    }

    // Create depth stencil state
    depth_state := MTLDevice.newDepthStencilStateWithDescriptor(mtl_device, depth_desc);
    if depth_state != null {
        MTL4RenderCommandEncoder.setDepthStencilState(cmd_info.current_render_encoder, depth_state);
        release(depth_state);
    }

    // Set depth bias if needed
    if desc.depth_bias != 0 || desc.depth_bias_slope_factor != 0 {
        MTL4RenderCommandEncoder.setDepthBias(current_render_encoder, desc.depth_bias, desc.depth_bias_slope_factor, desc.depth_bias_clamp);
    }

    // Set stencil reference value
    if desc.stencil_front.reference != 0 || desc.stencil_back.reference != 0 {
        MTL4RenderCommandEncoder.setStencilFrontReferenceValue(current_render_encoder, desc.stencil_front.reference.(u32), desc.stencil_back.reference.(u32));
    }
}

gpu_set_pipeline :: (cmd: Gpu_Command_Buffer, pipeline_handle: Gpu_Pipeline) -> Gpu_Result {
    using cmd_info := get_cmd_info(cmd);
    if cmd_info == null then return .ERROR_INVALID_BUFFER;

    pipeline := pool_get(live_pipelines, pipeline_handle);
    if pipeline == null then return .ERROR_INVALID_PIPELINE;

    // Store the current pipeline in the command buffer info for later use during dispatch/draw
    current_pipeline = pipeline_handle;

    // Set the pipeline on the appropriate encoder
    if pipeline.type == .GRAPHICS && cmd_info.current_render_encoder != null {
        if pipeline.mtl_render_pipeline != null {
            MTL4RenderCommandEncoder.setRenderPipelineState(current_render_encoder, pipeline.mtl_render_pipeline);
        } else {
            log_error("pipeline.mtl_render_pipeline is null");
        }
    } else if pipeline.type == .COMPUTE && cmd_info.current_compute_encoder != null {
        if pipeline.mtl_compute_pipeline != null {
            MTL4ComputeCommandEncoder.setComputePipelineState(current_compute_encoder, pipeline.mtl_compute_pipeline);
        } else {
            log_error("pipeline.mtl_compute_pipeline is null");
        }
    }

    return .SUCCESS;
}

gpu_draw_instanced :: (cmd: Gpu_Command_Buffer, vertex_data: Gpu_Ptr, pixel_data: Gpu_Ptr, vertex_count: u32, instance_count: u32) -> Gpu_Result {
    using cmd_info := get_cmd_info(cmd);
    if cmd_info == null || cmd_info.current_render_encoder == null then return .ERROR_INVALID_PIPELINE /* TODO probably the wrong error */;

    pipeline := pool_get(live_pipelines, cmd_info.current_pipeline);
    if pipeline == null || pipeline.mtl_render_pipeline == null then return .ERROR_INVALID_PIPELINE /* TODO probably the wrong error */;

    if vertex_data == 0 {
        // Fragment-only direct payload path used by transpiled fullscreen effects where
        // the vertex stage has no resource reads and fragment expects buffer(0) as payload.
        argument_tables.fragment.setAddress(argument_tables.fragment, cast(MTLGPUAddress) pixel_data, 8, 0);
        current_render_encoder.setArgumentTable(current_render_encoder, argument_tables.fragment, cast(MTLRenderStages)(MTLRenderStage.Vertex | .Fragment));
    } else {
        // TODO: we might need more than one indirect buffer per queue per frame, if we're submitting lots of command buffers.
        // each frame/queue pair could draw from a pair of unused indirect buffers, and return them when the frame is over.
        indirect_buffer := get_indirect_params_buffer(get_queue(cmd_info.queue), vertex_data, pixel_data);

        // Set argument table with buffer addresses
        argument_tables.vertex.setAddress(argument_tables.vertex, indirect_buffer.gpuAddress(indirect_buffer), 0);
        current_render_encoder.setArgumentTable(current_render_encoder, argument_tables.vertex, cast(MTLRenderStages)(MTLRenderStage.Vertex | .Fragment));
    }

    current_render_encoder.drawPrimitives(current_render_encoder, .Triangle, 0, vertex_count.(NSUInteger), instance_count.(NSUInteger));

    return .SUCCESS;
}

// Binds buffer(0) directly to a single GPU address for both vertex and fragment stages.
// Useful for shaders that expect a direct storage/uniform buffer ABI instead of sgpu's
// indirect {vertex_params, fragment_params} table layout.
gpu_draw_instanced_direct :: (cmd: Gpu_Command_Buffer, data: Gpu_Ptr, vertex_count: u32, instance_count: u32) -> Gpu_Result {
    using cmd_info := get_cmd_info(cmd);
    if cmd_info == null || cmd_info.current_render_encoder == null then return .ERROR_INVALID_PIPELINE;

    pipeline := pool_get(live_pipelines, cmd_info.current_pipeline);
    if pipeline == null || pipeline.mtl_render_pipeline == null then return .ERROR_INVALID_PIPELINE;

    argument_tables.vertex.setAddress(argument_tables.vertex, cast(MTLGPUAddress) data, 0);
    current_render_encoder.setArgumentTable(current_render_encoder, argument_tables.vertex, cast(MTLRenderStages)(MTLRenderStage.Vertex | .Fragment));

    current_render_encoder.drawPrimitives(current_render_encoder, .Triangle, 0, vertex_count.(NSUInteger), instance_count.(NSUInteger));
    return .SUCCESS;
}

Indirect_Params :: struct {
    vertex_params: *void;
    fragment_params: *void;
}

get_indirect_params_buffer :: (using queue: *Queue, vertex_data: Gpu_Ptr, fragment_data: Gpu_Ptr) -> *MTLBuffer {
    index := frame_index % MAX_FRAMES_IN_FLIGHT;

    buf := indirect_param_buffers[index];
    assert(buf != null);

    cpu := cast(*Indirect_Params)buf.contents(buf);
    cpu.vertex_params   = xx vertex_data;
    cpu.fragment_params = xx fragment_data;

    if !did_log_indirect_params_once {
        did_log_indirect_params_once = true;
        log("SGPU_METAL_INDIRECT_PARAMS vertex_gpu=% fragment_gpu=% stored_vertex_ptr=% stored_fragment_ptr=%",
            vertex_data,
            fragment_data,
            cast(u64) xx cpu.vertex_params,
            cast(u64) xx cpu.fragment_params);
    }

    return buf;
}

gpu_draw_indexed_instanced :: (cmd: Gpu_Command_Buffer, vertex_data: Gpu_Ptr, pixel_data: Gpu_Ptr, index_data: Gpu_Ptr, index_count: u32, instance_count: u32, index_size: u32 = size_of(u32)) -> Gpu_Result {
    cmd_info := get_cmd_info(cmd);
    if cmd_info == null || cmd_info.current_render_encoder == null {
        log_error("gpu_draw_indexed_instanced: cmd_info or cmd_info.current_render_encoder is null");
        return .ERROR_INVALID_BUFFER;
    }

    using cmd_info;

    pipeline := pool_get(live_pipelines, cmd_info.current_pipeline);
    if pipeline == null || pipeline.mtl_render_pipeline == null {
        log_error("gpu_draw_indexed_instanced: pipeline is null or pipeline.mtl_render_pipeline is null");
        return .ERROR_INVALID_PIPELINE;
    }

    // TODO: we might need more than one indirect buffer per queue per frame, if we're submitting lots of command buffers.
    // each frame/queue pair could draw from a pair of unused indirect buffers, and return them when the frame is over.
    indirect_buffer := get_indirect_params_buffer(get_queue(cmd_info.queue), vertex_data, pixel_data);

    // Set argument table with buffer addresses
    indirect_gpu := indirect_buffer.gpuAddress(indirect_buffer);
    argument_tables.vertex.setAddress(argument_tables.vertex, indirect_gpu, 0);
    current_render_encoder.setArgumentTable(current_render_encoder, argument_tables.vertex, cast(MTLRenderStages)(MTLRenderStage.Vertex | .Fragment));

    if index_size != 4 && index_size != 2 then return .ERROR_INVALID_VERTEX_INDEX_SIZE;

    index_type: MTLIndexType = ifx index_size == 4 then .UInt32 else .UInt16;

    // Metal 4 uses GPU addresses for index buffers
    // The index_data is already a Gpu_Ptr (GPU address), so we use it directly
    index_buffer_address := cast(MTLGPUAddress) index_data;
    index_buffer_length := (index_count * index_size).(NSUInteger);

    MTL4RenderCommandEncoder.drawIndexedPrimitives(
        cmd_info.current_render_encoder,
        .Triangle,
        index_count.(NSUInteger),
        index_type,
        index_buffer_address,
        index_buffer_length,
        instance_count.(NSUInteger)
    );

    return .SUCCESS;
}

Gpu_Timeline_Pair :: struct {
    semaphore: Gpu_Semaphore;
    value: u64;
}

#scope_module

did_log_indirect_params_once := false;

init_queues :: () {
    auto_release_temp();

    create_command_queue :: (debug_label: string) -> *MTL4CommandQueue {
        desc := objc_new_defer_release(MTL4CommandQueueDescriptor);
        desc.setLabel(desc, to_temp_nsstring(debug_label));
        error: *NSError = null;
        cmd_queue := MTLDevice.newMTL4CommandQueueWithDescriptor(mtl_device, desc, *error);
        log_error_if_not_null(error);
        return cmd_queue;
    }

    create_command_allocator :: (debug_label: string) -> *MTL4CommandAllocator {
        desc := objc_new_defer_release(MTL4CommandAllocatorDescriptor);
        desc.setLabel(desc, to_temp_nsstring(debug_label));
        error: *NSError = null;
        cmd_allocator := MTLDevice.newCommandAllocatorWithDescriptor(mtl_device, desc, *error);
        log_error_if_not_null(error);
        return cmd_allocator;
    }

    // Create MTL4 command queues for each type
    mtl4_desc := objc_new_defer_release(MTL4CommandQueueDescriptor);

    queue_index := 0;

    init_queue :: (queue: *Queue, type: Gpu_Queue_Type, index_in_type: u32) {
        queue.type = type;
        queue.index_in_type = index_in_type;
        queue.mtl4_queue = create_command_queue(tprint("%", type));
        for i: 0..MAX_FRAMES_IN_FLIGHT-1 {
            queue.command_allocators[i] = create_command_allocator(tprint("%_alloc_%", type, i));
            buf := mtl_device.newBufferWithLength(mtl_device, size_of(Indirect_Params), xx MTLResource.StorageModeShared);
            buf.setLabel(buf, to_temp_nsstring(tprint("sgpu indirect params (%) %", type, i)));
            add_to_residency(buf);
            queue.indirect_param_buffers[i] = buf;
        }
        attach_residency_to_queue(queue.mtl4_queue);
    }

    // MAIN queue
    {
        queue := *queues[queue_index]; queue_index += 1;
        init_queue(queue, .MAIN, 0);
    }

    // COMPUTE queues (4 of them, but Metal doesn't really distinguish - they all go to same HW)
    for i: 0..MAX_COMPUTE_QUEUES-1 {
        queue := *queues[queue_index]; queue_index += 1;
        init_queue(queue, .COMPUTE, i.(u32));
    }

    // TRANSFER queues (2 of them)
    for i: 0..MAX_TRANSFER_QUEUES-1 {
        queue := *queues[queue_index]; queue_index += 1;
        init_queue(queue, .TRANSFER, i.(u32));
    }
}

shutdown_queues :: () {
    for * queues {
        release_and_set_null(*it.mtl4_queue);
        for allocator: it.command_allocators {
            if allocator release(allocator);
        }
        for indirect_buffer: it.indirect_param_buffers {
            if indirect_buffer release(indirect_buffer);
        }
        for cmd_buf: it.free_command_buffers {
            if cmd_buf release(cmd_buf);
        }
        array_free(it.free_command_buffers);
        it.* = {};
    }
}

get_queue :: (queue_handle: Gpu_Queue) -> *Queue {
    queue_index := queue_handle - 1;
    if queue_index < 0 || queue_index >= queues.count return null;
    return *queues[queue_index];
}

get_cmd_info :: (cmd: Gpu_Command_Buffer) -> *Command_Buffer_Info {
    index := cast(s64) cmd - 1;
    if index < 0 || index >= live_command_buffers.count return null;
    return *live_command_buffers[index];
}

ensure_compute_encoder :: (using cmd_info: *Command_Buffer_Info) -> *MTL4ComputeCommandEncoder {
    assert(cmd_info != null);
    current_compute_encoder = cmd_buffer.computeCommandEncoder(cmd_buffer);
    return current_compute_encoder;
}

end_current_compute_encoder :: (using cmd_info: *Command_Buffer_Info) {
    assert(cmd_info != null);

    if current_compute_encoder == null return;
    current_compute_encoder.endEncoding(current_compute_encoder);
    current_compute_encoder = null;
}

end_current_render_encoder :: (using cmd_info: *Command_Buffer_Info) {
    assert(cmd_info != null);

    if current_render_encoder == null return;
    current_render_encoder.endEncoding(current_render_encoder);
    current_render_encoder = null;
}

// Helper functions for Metal enum conversions
load_op_to_mtl :: (op: Load_Op) -> MTLLoadAction {
    if op == {
        case .LOAD;      return .Load;
        case .CLEAR;     return .Clear;
        case .DONT_CARE; return .DontCare;
    }
    return .DontCare;
}

store_op_to_mtl :: (op: Store_Op) -> MTLStoreAction {
    if op == {
        case .STORE;     return .Store;
        case .DONT_CARE; return .DontCare;
    }
    return .DontCare;
}

compare_op_to_mtl :: (op: Op) -> MTLCompareFunction {
    if op == {
        case .NEVER;            return .Never;
        case .LESS;             return .Less;
        case .EQUAL;            return .Equal;
        case .LESS_OR_EQUAL;    return .LessEqual;
        case .GREATER;          return .Greater;
        case .NOT_EQUAL;        return .NotEqual;
        case .GREATER_OR_EQUAL; return .GreaterEqual;
        case .ALWAYS;           return .Always;
    }
    return .Always;
}

stencil_op_to_mtl :: (op: Stencil_Op) -> MTLStencilOperation {
    if op == {
        case .KEEP;                return .Keep;
        case .ZERO;                return .Zero;
        case .REPLACE;             return .Replace;
        case .INVERT;              return .Invert;
        case .INCREMENT_AND_CLAMP; return .IncrementClamp;
        case .DECREMENT_AND_CLAMP; return .DecrementClamp;
        case .INCREMENT_AND_WRAP;  return .IncrementWrap;
        case .DECREMENT_AND_WARP;  return .DecrementWrap;
    }
    return .Keep;
}

Command_Buffer_Info :: struct {
    cmd_buffer: *MTL4CommandBuffer;
    queue: Gpu_Queue;
    current_compute_encoder: *MTL4ComputeCommandEncoder;
    current_render_encoder: *MTL4RenderCommandEncoder;
    current_pipeline: Gpu_Pipeline;
}

get_available_command_buffer :: (using queue: *Queue) -> *MTL4CommandBuffer {
    if free_command_buffers.count > 0 {
        cmd_buf := free_command_buffers[free_command_buffers.count - 1];
        free_command_buffers.count -= 1;
        return cmd_buf;
    }

    return mtl_device.newCommandBuffer(mtl_device);
}

free_command_buffer :: (using queue: *Queue, cmd_info: *Command_Buffer_Info) {
    assert(cmd_info.cmd_buffer != null);
    assert(cmd_info.current_render_encoder == null, "free_command_buffer had active render encoder: cmd_info = %", cmd_info);
    array_add(*free_command_buffers, cmd_info.cmd_buffer);
    if free_command_buffers.count > 100 {
        log(tprint("WARNING: Free command buffer count is high: %", free_command_buffers.count));
    }
    cmd_info.cmd_buffer = null;
}

Queue :: struct {
    mtl4_queue: *MTL4CommandQueue;
    index_in_type: u32;
    type: Gpu_Queue_Type;
    command_allocators: [MAX_FRAMES_IN_FLIGHT]*MTL4CommandAllocator;
    indirect_param_buffers: [MAX_FRAMES_IN_FLIGHT]*MTLBuffer;
    free_command_buffers: [..]*MTL4CommandBuffer;
}

live_command_buffers: [..] Command_Buffer_Info;
queues: [MAX_COMPUTE_QUEUES + MAX_TRANSFER_QUEUES + 1] Queue;
