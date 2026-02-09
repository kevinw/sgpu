USE_DEBUG_COMMIT :: false;

#scope_export

Native_Window_Type :: enum {
    UNKNOWN;
    WIN32;
    X11;
    WAYLAND;
    COCOA;
}

// Push and defer a pop in the parent scope, an autorelease pool for this frame
gpu_push_frame :: () #expand {
    assert(frame_autorelease_pool == null);
    frame_autorelease_pool = objc_new(NSAutoreleasePool);
    `defer release_and_set_null(*frame_autorelease_pool);
}

gpu_init_swapchain :: (native_window: u64, window_type: Native_Window_Type) {
    assert(window_type == .COCOA, "Only Cocoa windows are supported on Metal");

    native_window_handle = native_window;
    native_window_type = window_type;

    // Get the CAMetalLayer from the NSWindow
    ns_window := cast(*NSWindow) native_window;
    swapchain_layer = ns_window_get_metal_layer(ns_window);
    assert(swapchain_layer != null, "Failed to get CAMetalLayer from window");

    // Configure the CAMetalLayer
    {
        using swapchain_layer;
        setDevice(swapchain_layer, mtl_device);
        setPixelFormat(swapchain_layer, .BGRA8Unorm);
        setFramebufferOnly(swapchain_layer, YES);
        update_metal_layer_drawable_size(ns_window);

        // Get the initial drawable size
        drawable_size := drawableSize(swapchain_layer);

        if drawable_size.width == 0 && drawable_size.height == 0
            log_error("ZERO drawable_size: %", drawable_size);

        surface_width  = cast(u32) drawable_size.width;
        surface_height = cast(u32) drawable_size.height;
    }


    // Create the frame completion event for synchronization
    frame_completion_event = mtl_device.newSharedEvent(mtl_device);
    assert(frame_completion_event != null);
    if frame_completion_event != null {
        // Use 1-based frame completion values:
        // frame N submission signals value N+1 when finished.
        frame_completion_event.setSignaledValue(frame_completion_event, 0);
    }
}

gpu_swapchain_resize :: () {
    // Wait for any pending work to complete
    gpu_wait_idle();

    update_metal_layer_drawable_size(xx native_window_handle);

    // Get the new drawable size
    drawable_size := CAMetalLayer.drawableSize(swapchain_layer);
    surface_width  = cast(u32) drawable_size.width;
    surface_height = cast(u32) drawable_size.height;
    cleanup_swapchain_views();
}

gpu_destroy_swapchain :: () {
    cleanup_swapchain_views();
    swapchain_layer = null;
}

gpu_swapchain_acquire :: () -> Gpu_Result, Gpu_Texture_View {
    // Wait if the CPU is trying to submit more than MAX_FRAMES_IN_FLIGHT before the GPU can get to them.
    if frame_index >= MAX_FRAMES_IN_FLIGHT {
        value_to_wait := frame_index - MAX_FRAMES_IN_FLIGHT + 1;
        frame_completion_event.waitUntilSignaledValue(frame_completion_event, value_to_wait, U64_MAX);
    }

    // Get the next drawable from the layer
    current_drawable = CAMetalLayer.nextDrawable(swapchain_layer);
    if current_drawable == null {
        log_error("Failed to get next drawable from CAMetalLayer.");
        sleep_milliseconds(10);
        return .SUCCESS, 0;  // No drawable available (timeout or error)
    }

    // TODO: gpu_swapchain_aquire doesn't specify the 0th MAIN queue, but we're adding the CAMetalLayer's residencySet
    // here to it. Might need to add a queue argument to gpu_swaphchain_acquire?
    // Not sure how it fits into the sgpu API yet.
    {
        using queue := get_queue(gpu_get_queue(.MAIN, 0));
        if queue == null {
            log_error("gpu_swapchain_acquire: Failed to get main queue");
            return .FATAL_ERROR_UNKNOWN, 0;
        }
        assert(mtl4_queue != null);

        layer_residency_set := swapchain_layer.residencySet(swapchain_layer);
        assert(layer_residency_set != null);
        mtl4_queue.addResidencySet(mtl4_queue, layer_residency_set);
    }

    // Get the drawable's texture
    drawable_texture := CAMetalDrawable.texture(current_drawable);
    if drawable_texture == null {
        log_error("Drawable has no texture.");
        return .SUCCESS, 0;
    }

    // Create or update the texture view for this drawable
    current_swapchain_view = create_swapchain_texture_view(drawable_texture);

    return .SUCCESS, current_swapchain_view;
}

gpu_submit_and_present :: (cmd_buff: Gpu_Command_Buffer, signals: [] Gpu_Timeline_Pair = .[], waits: [] Gpu_Timeline_Pair = .[]) {
    cmd_info := get_cmd_info(cmd_buff);
    if cmd_info == null then return;

    queue := get_queue(cmd_info.queue);
    if queue == null then return;

    // End any active encoder (render or compute)
    end_current_compute_encoder(cmd_info);
    end_current_render_encoder(cmd_info);
    assert(cmd_info.current_render_encoder == null);

    // End the command buffer recording
    cmd_info.cmd_buffer.endCommandBuffer(cmd_info.cmd_buffer);

    using queue;
    if current_drawable {
        mtl4_queue.waitForDrawable(mtl4_queue, current_drawable);
    }

    #if USE_DEBUG_COMMIT {
        block_context = context;
        block.isa = xx _NSConcreteGlobalBlock;
        block.invoke = cast(*void)on_commit_feedback;

        commit_options := objc_scope_new(MTL4CommitOptions);
        commit_options.addFeedbackHandler(commit_options, *block);

        mtl4_queue.commit(mtl4_queue, commandBuffers=*cmd_info.cmd_buffer, count=1, options=commit_options);
    } else {
        mtl4_queue.commit(mtl4_queue, commandBuffers=*cmd_info.cmd_buffer, count=1);
    }

    if current_drawable {
        mtl4_queue.signalDrawable(mtl4_queue, current_drawable);
        current_drawable.present(current_drawable);
    }

    // Signal completion for this frame as frame_index + 1 so waits can never target 0.
    mtl4_queue.signalEvent(mtl4_queue, frame_completion_event, frame_index + 1);
    assert(cmd_info.current_render_encoder == null);
    free_command_buffer(queue, cmd_info);
    frame_index += 1;
}

#scope_module

on_commit_feedback :: (block: *Objective_C_Block_Basic, feedback: *MTL4CommitFeedback) #c_call {
    push_context block_context {
        error := feedback.error(feedback);
        if error != null log_error("ERROR: %", nserror_to_string(error));
        log("start time: %", feedback.GPUStartTime(feedback));
        log("end time:   %", feedback.GPUEndTime(feedback));
    }
}

// Boilerplate for getting an Objective-C block callback hooked up
block_desc: Objective_C_Block_Basic_Descriptor = .{ size = size_of(Objective_C_Block_Basic) };
block: Objective_C_Block_Basic = .{ descriptor = *block_desc };
block_context: #Context;

native_window_handle: u64;
native_window_type: Native_Window_Type;
swapchain_layer: *CAMetalLayer;
surface_width: u32;
surface_height: u32;

current_drawable: *CAMetalDrawable;
current_swapchain_view: Gpu_Texture_View;

frame_completion_event: *MTLSharedEvent;
frame_index: u64 = 0;

// Swapchain texture tracking
Swapchain_Texture_Entry :: struct {
    texture_handle: Gpu_Texture;
    view_handle: Gpu_Texture_View;
    mtl_texture: *MTLTexture;
}

swapchain_textures: [..] Swapchain_Texture_Entry;

create_swapchain_texture_view :: (mtl_texture: *MTLTexture) -> Gpu_Texture_View {
    // Check if we already have a view for this texture
    for * swapchain_textures {
        if it.mtl_texture == mtl_texture {
            return it.view_handle;
        }
    }

    // Create new texture and view handles
    width := MTLTexture.width(mtl_texture).(u32);
    height := MTLTexture.height(mtl_texture).(u32);

    texture_desc := Gpu_Texture_Desc.{
        type = ._2D,
        dimensions = .[width, height, 1],
        mip_count = 1,
        layer_count = 1,
        sample_count = 1,
        format = .B8G8R8A8_UNORM,
        usage = .COLOR_ATTACHMENT | .TRANSFER_DST,
    };

    // Add to textures pool
    texture_handle := pool_add(*live_textures, .{
        desc = texture_desc,
        mtl_texture = mtl_texture,
    });
    if texture_handle == 0 {
        log_error("create_swapchain_texture_view: live_textures pool exhausted (MAX_IMAGES=%)", MAX_IMAGES);
        return 0;
    }

    // Create texture view
    view_handle := pool_add(*live_texture_views, .{
        texture = texture_handle,
        mtl_texture = mtl_texture,
        desc = .{
            format = .B8G8R8A8_UNORM,
            base_mip = 0,
            mip_count = 1,
            base_layer = 0,
            layer_count = 1,
        },
    });
    if view_handle == 0 {
        log_error("create_swapchain_texture_view: live_texture_views pool exhausted");
        pool_remove(*live_textures, texture_handle);
        return 0;
    }

    // Track this swapchain texture
    entry: Swapchain_Texture_Entry;
    entry.texture_handle = texture_handle;
    entry.view_handle = view_handle;
    entry.mtl_texture = mtl_texture;
    array_add(*swapchain_textures, entry);

    return view_handle;
}

cleanup_swapchain_views :: () {
    for swapchain_textures {
        pool_remove(*live_texture_views, it.view_handle);
        pool_remove(*live_textures, it.texture_handle);
    }
    array_reset(*swapchain_textures);
    current_swapchain_view = NULL_HANDLE;
}

ns_window_get_metal_layer :: (window: *NSWindow) -> *CAMetalLayer {
    content_view := NSWindow.contentView(window);
    if !content_view {
        log_error("window has no contentView");
        return null;
    }

    // log("Window's contentView: %", content_view);
    // log("Window's contentView hierarchy:\n%", subtree_description(content_view));

    layer := NSView.layer(content_view);
    if !layer {
        log_error("window's contentView has no layer");
        return null;
    }

    // log("Layer of contentView: %", layer);

    // Check if the layer is a CAMetalLayer
    if !is_kind_of_class(cast(id) layer, objc_getClass("CAMetalLayer")) {
        log_error("window's contentView's layer is not a CAMetalLayer, but a %", to_string(class_getName(object_getClass(cast(id) layer))));
        return null;
    }

    return cast(*CAMetalLayer) layer;
}

is_kind_of_class :: (obj: id, class: Class) -> bool {
    sel := sel_registerName("isKindOfClass:");
    func: (id, Selector, Class) -> BOOL #c_call;
    func = xx objc_msgSend;
    return func(obj, sel, class) == YES;
}

subtree_description :: (ns_view: *NSView) -> string {
    sel := sel_registerName("_subtreeDescription");
    func: (*NSView, Selector) -> *NSString #c_call;
    func = xx objc_msgSend;
    str := func(ns_view, sel);
    return to_string(str);
}

shutdown_swapchain :: () {
    release_and_set_null(*frame_completion_event);
}

update_metal_layer_drawable_size :: (window: *NSWindow) {
    sz := window.frame(window).size;
    width := sz.width;
    height := sz.height;

    r := NSRect.{ .{0, 0}, .{ xx width, xx height }};
    r = window.convertRectToBacking(window, .{.{0, 0}, .{xx width, xx height}});
    layer := ns_window_get_metal_layer(window);
    layer.setDrawableSize(layer, r.size);
}


frame_autorelease_pool: *NSAutoreleasePool;

#import "Objective_C";
#import "Objective_C/AppKit";
