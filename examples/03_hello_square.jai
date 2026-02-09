WRITE_SHADER_OUTPUT :: true;

main :: () {
    opts := gpu_example_harness();

    result := gpu_init();
    assert(result == .SUCCESS);
    defer gpu_shutdown();

    #import "Objective_C"; pool := objc_new(NSAutoreleasePool); defer release(pool);

    window := create_window(1280, 720, "03_hello_square");

    window_type: Native_Window_Type;
    #if      OS == .WINDOWS then window_type = .WIN32;
    else #if OS == .LINUX   then window_type = .X11;
    else #if OS == .MACOS   then window_type = .COCOA;
    else assert(false, "Unsupported OS");

    gpu_init_swapchain(cast(u64)window, window_type);
    defer gpu_destroy_swapchain();

    main_queue := gpu_get_queue(.MAIN, 0);

    #if 1 {
        success, vertex_spv := compile_shader("../shaders/hello_square_vs.slang", write_output = WRITE_SHADER_OUTPUT); assert(success); assert(success);
        defer array_free(vertex_spv);
        success=, pixel_spv := compile_shader("../shaders/hello_square_ps.slang", write_output = WRITE_SHADER_OUTPUT); assert(success); assert(success);
        defer array_free(pixel_spv);
    } else {
        vertex_spv, ok := File.read_entire_file("shaders/hello_square_vs.metal"); assert(ok);
        defer array_free(vertex_spv);
        pixel_spv, ok= := File.read_entire_file("shaders/hello_square_ps.metal"); assert(ok);
        defer array_free(pixel_spv);
    }

    blend_state: Gpu_Blend_Desc;
    raster_desc := Gpu_Raster_Desc.{
        cull = .CW,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
        blend_state = *blend_state,
    };
    depth_desc := Gpu_Depth_Stencil_Desc.{
        depth_test = .ALWAYS,
        depth_mode = .NONE,
    };

    graphics_pipeline := gpu_create_graphics_pipeline(vertex_spv, pixel_spv, raster_desc);
    defer gpu_free_pipeline(graphics_pipeline);

    Vertex2D :: struct {
        x: float;
        y: float;
    }

    gpu_arena := gpu_make_arena(1024);
    defer gpu_free_arena(gpu_arena);

    vertex_buffer, vertex_gpu := gpu_arena_alloc(*gpu_arena, [4] Vertex2D);
    vertex_buffer.* = .[
        .{ 0.5,   0.5 },
        .{ 0.5,  -0.5 },
        .{ -0.5, -0.5 },
        .{ -0.5, +0.5 },
    ];

    V3 :: struct { x: float; y: float; z: float; }
    V4 :: struct { x: float; y: float; z: float; w: float; }

    vertex_colors, colors_gpu := gpu_arena_alloc(*gpu_arena, [4] V4);
    vertex_colors.* = .[
        {1, 0, 0, 1},
        {0, 1, 0, 1},
        {0, 0, 1, 1},
        {1, 1, 1, 1},
    ];

    param_block, vertex_params_gpu := gpu_arena_alloc(*gpu_arena, [2] Gpu_Ptr);
    param_block.* = .[vertex_gpu, colors_gpu];

    index_buffer, index_gpu := gpu_arena_alloc(*gpu_arena, [6] u32);
    index_buffer.* = .[
        0, 3, 1,
        1, 3, 2,
    ];

    pixel_data, pixel_gpu := gpu_arena_alloc(*gpu_arena, [3] float);
    pixel_data.* = .[1., 0., 1.];

    gpu_commit_residency();

    frame_count: s64 = 0;
    capture_started := false;
    capture_done := false;
    quit := false;
    while !quit && (frame_count < opts.max_frames || opts.max_frames == 0) {
        gpu_push_frame();

        update_window_events();
        for events_this_frame {
            if it.type == .QUIT then quit = true;
        }
        if get_window_resizes().count > 0 {
            gpu_swapchain_resize();
        }

        result=, swapchain_image := gpu_swapchain_acquire();
        assert(result == .SUCCESS);
        if !swapchain_image continue;

        result=, cmd_buff := gpu_start_command_recording(main_queue);
        assert(result == .SUCCESS);

        if opts.capture_frame && !capture_started {
            capture_result := gpu_capture_start_in_xcode(main_queue);
            if capture_result != .SUCCESS {
                log_error("gpu_capture_start_in_xcode failed with result %", capture_result);
            } else {
                capture_started = true;
            }
        }

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
            gpu_set_depth_stencil_state(cmd_buff, depth_desc);

            gpu_set_pipeline(cmd_buff, graphics_pipeline);

            gpu_draw_indexed_instanced(cmd_buff, vertex_params_gpu, pixel_gpu, index_gpu, 6, 1);

            gpu_end_render_pass(cmd_buff);
        }

        gpu_submit_and_present(cmd_buff);
        if capture_started && !capture_done {
            gpu_capture_stop(open = true);
            capture_done = true;
        }
        if frame_count == 0 gpu_dump_to_bitmap("03_hello_square.jpg");
        frame_count += 1;
    }

    gpu_wait_idle();
    print("OK!\n");
}

#import,file "../module.jai"(VALIDATION = true, DEBUG_ASSERTS = true); // #import "sgpu" in your own code
#load "example_common.jai";
#import "Window_Creation";
#import "Input";
File :: #import "File";
