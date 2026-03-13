# SGPU

Refreshingly simple graphics API inspired by Sebastian Aaltonen's [No Graphics API](https://www.sebastianaaltonen.com/blog/no-graphics-api).

## Run examples

You can compile and run each example individually:

```
cd examples
jai build.jai - 01_memory -run
jai build.jai - 02_compute -run
jai build.jai - 03_hello_square -run
```

Or to run all examples in a "single frame" test:

```
cd examples && ./run_examples.sh
```

## Upcoming Features

- Mesh shaders
- Optional shader hotreloading
- Optional integrated profiling support (Tracy)

## Texture Quad Sample

```jai
gpu_init();
defer gpu_shutdown();

// Using Jai's standard window library
// window creation can be replaced with glfw/sdl/native.
window := create_window(1280, 720, "Sample window");

// Initialize the swapchain with any native window handle
window_type: Native_Window_Type = #ifx OS == .WINDOWS then .WIN32 else .X11;
gpu_init_swapchain(window, window_type);
defer gpu_destroy_swapchain();

// Built in slang shader compiler
v_success, vertex_spv := compile_shader("../shaders/textured_vs.slang");
assert(v_success);
p_success, pixel_spv := compile_shader("../shaders/textured_ps.slang");
assert(p_success);

blend_state: Gpu_Blend_Desc;
raster_desc := Gpu_Raster_Desc.{
    cull = .CW,
    color_targets = .[
        .{format = .B8G8R8A8_UNORM}
    ],
    blend_state = *blend_state,
};

// Link the shaders into a pipeline object. Notably all pipeline objects in sgpu use an identical pipeline layout.
graphics_pipeline := gpu_create_graphics_pipeline(vertex_spv, pixel_spv, raster_desc);
defer gpu_free_pipeline(graphics_pipeline);


texture, view := load_texture("../sample.png", .R8G8B8A8_SRGB);
sampler := gpu_create_sampler(.{ });
defer gpu_free(texture);
defer gpu_free(sampler);

// Create a single arena in gpu memory to allocate vertex and index data
gpu_arena := gpu_make_arena(1024);
defer gpu_free_arena(gpu_arena);

vertex_buffer := gpu_alloc_view(*gpu_arena, Vector2, 4);
vertex_buffer.cpu[0] = .{0.5, 0.5};
vertex_buffer.cpu[1] = .{0.5, -0.5};
vertex_buffer.cpu[2] = .{-0.5, -0.5};
vertex_buffer.cpu[3] = .{-0.5, +0.5};

vertex_uvs := gpu_alloc_view(*gpu_arena, Vector2, 4);
vertex_uvs.cpu[0] = .{1.0, 1.0};
vertex_uvs.cpu[1] = .{1.0, 0.0};
vertex_uvs.cpu[2] = .{0.0, 0.0};
vertex_uvs.cpu[3] = .{0.0, 1.0};

index_buffer := gpu_alloc_view(*gpu_arena, u32, 6);
index_buffer.cpu[0] = 0;
index_buffer.cpu[1] = 3;
index_buffer.cpu[2] = 1;
index_buffer.cpu[3] = 1;
index_buffer.cpu[4] = 3;
index_buffer.cpu[5] = 2;

// Allocate a small block of memory where the vertex shader parameters will be stored.
vs_param_block := gpu_alloc_view(*gpu_arena, Gpu_Ptr, 2);
vs_param_block.cpu[0] = vertex_buffer.gpu;
vs_param_block.cpu[1] = vertex_uvs.gpu;

// Allocate a small block of memory where the pixel shader parameters will be stored.
pixel_data := gpu_alloc_view(*gpu_arena, u32, 2);
pixel_data.cpu[0] = view.(u32);
pixel_data.cpu[1] = sampler.(u32);

main_queue := gpu_get_queue(.MAIN, 0);

quit := false;
while !quit {
    update_window_events();
    for events_this_frame {
        if it.type == .QUIT then quit = true;
    }
    if get_window_resizes().count > 0 {
        gpu_swapchain_resize();
    }

    // Acquires the next available swapchain image. This will wait on the internal semaphores until a frame is ready
    swapchain_image := gpu_swapchain_acquire();
    if !swapchain_image {
        continue;
    }

    cmd_buff := gpu_start_command_recording(main_queue);
    // Execute a render pass
    {
        render_desc := Gpu_Render_Pass_Desc.{
            color_targets = .[
                .{
                    view = swapchain_image,
                    load_op = .CLEAR,
                    store_op = .STORE,
                    clear_color._float = .[0, 0, 0, 1],
                }
            ]
        };
        gpu_begin_render_pass(cmd_buff, render_desc);
        gpu_set_depth_stencil_state(cmd_buff, .{ depth_test = .NEVER });

        gpu_set_pipeline(cmd_buff, graphics_pipeline);

        gpu_draw_indexed_instanced(cmd_buff, vs_param_block.gpu, pixel_data.gpu, index_buffer.gpu, 6, 1);

        gpu_end_render_pass(cmd_buff);
    }

    // submit the command buffer for presentation.
    gpu_submit_and_present(main_queue, cmd_buff);
}

gpu_wait_idle();
```

## Recommended Memory Shapes

Use the explicit typed pair helpers when possible:

- `gpu_alloc_buffer(T)` for one struct/value
- `gpu_alloc_view(T, count)` for a span of elements
- `gpu_alloc_buffer(arena, ...)` for one arena-backed struct/value
- `gpu_alloc_view(arena, ...)` for arena-backed arrays and tables

In practice:

- prefer `Gpu_Buffer(T)` for scalar param/control blocks
- prefer `Gpu_View(T)` for vertices, indices, instance data, simulation state, and pointer tables
