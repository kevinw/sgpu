main :: () {
    opts := gpu_example_harness();

    result := gpu_init(.MESH_SHADERS);
    assert(result == .SUCCESS);
    defer gpu_shutdown();

    #if OS == .MACOS {
        #import "Objective_C";
        pool := objc_new(NSAutoreleasePool); defer release(pool);
    }

    window := create_window(1280, 720, "04_mesh_shaders");

    window_type: Native_Window_Type;
    #if      OS == .WINDOWS then window_type = .WIN32;
    else #if OS == .LINUX   then window_type = .X11;
    else #if OS == .MACOS   then window_type = .COCOA;
    else assert(false, "Unsupported OS");

    gpu_init_swapchain(xx window, window_type);
    defer gpu_destroy_swapchain();

    main_queue := gpu_get_queue(.MAIN, 0);

    success := false;
    task_shader: string;
    mesh_shader: string;
    pixel_shader: string;

    #if OS == .MACOS {
        success = true;
        mesh_shader = copy_string(METAL_TASK_AND_MESH_SHADER);
        task_shader = mesh_shader;
        pixel_shader = copy_string(METAL_FRAGMENT_SHADER);
    } else {
        success, task_shader_bytes := compile_shader("../shaders/meshlets_as.slang");
        assert(success);
        task_shader = cast(string) task_shader_bytes;
        success, mesh_shader_bytes := compile_shader("../shaders/meshlets_ms.slang");
        assert(success);
        mesh_shader = cast(string) mesh_shader_bytes;
        success, pixel_shader_bytes := compile_shader("../shaders/meshlets_ps.slang");
        pixel_shader = cast(string) pixel_shader_bytes;
    }
    assert(success);
    if task_shader.data != mesh_shader.data defer free(task_shader.data);
    defer free(mesh_shader.data);
    defer free(pixel_shader.data);

    blend_state: Gpu_Blend_Desc;
    raster_desc := Gpu_Raster_Desc.{
        cull = .CW,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
        blend_state = *blend_state,
    };
    depth_desc := Gpu_Depth_Stencil_Desc.{
        depth_test = .NEVER,
        depth_mode = .NONE,
    };

    mesh_desc := Gpu_Mesh_Pipeline_Desc.{
        task_shader = cast([]u8) task_shader,
        mesh_shader = cast([]u8) mesh_shader,
        pixel_shader = cast([]u8) pixel_shader,
        raster_desc = raster_desc,
        task_threads = .[1, 1, 1],
        mesh_threads = .[3, 1, 1],
    };
    graphics_pipeline := gpu_create_mesh_pipeline(mesh_desc);
    assert(graphics_pipeline != 0);
    defer gpu_free_pipeline(graphics_pipeline);

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
            capture_result := gpu_capture_start();
            if capture_result != .SUCCESS {
                log_error("gpu_capture_start failed with result %", capture_result);
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
            gpu_draw_meshlets(cmd_buff, 0, .[1, 1, 1]);
            gpu_end_render_pass(cmd_buff);
        }

        gpu_submit_and_present(cmd_buff);
        if capture_started && !capture_done {
            gpu_capture_end();
            capture_done = true;
        }
        #if OS == .MACOS {
            if opts.dump_framebuffer && frame_count == 0
                gpu_dump_to_bitmap("04_mesh_shaders.jpg");
        }
        frame_count += 1;
    }

    gpu_wait_idle();
    print("OK!\n");
}

#import,file "../module.jai"()(VALIDATION = true, DEBUG_ASSERTS = true);
#load "example_common.jai";
#import "Basic";
#import "Input";
#import "Window_Creation";

#scope_file

METAL_TASK_AND_MESH_SHADER :: #string END
#include <metal_stdlib>
#include <metal_graphics>
using namespace metal;

struct VertexOut {
    float4 pos [[position]];
    half3 color [[user(locn0)]];
};

[[object, max_total_threads_per_threadgroup(1)]]
void objectMain(mesh_grid_properties mgp) {
    mgp.set_threadgroups_per_grid(uint3(1, 1, 1));
}

[[mesh, max_total_threads_per_threadgroup(3)]]
void meshMain(
    uint tid [[thread_index_in_threadgroup]],
    metal::mesh<VertexOut, void, 3, 1, metal::topology::triangle> out_mesh
) {
    if (tid == 0) {
        out_mesh.set_primitive_count(1);
    }

    if (tid < 3) {
        float2 positions[3] = {
            float2(0.0, -0.5),
            float2(0.5, 0.5),
            float2(-0.5, 0.5),
        };

        VertexOut vert;
        vert.pos = float4(positions[tid], 0.0, 1.0);
        vert.color = half3(1.0h, 0.5h, 0.5h);
        out_mesh.set_vertex(tid, vert);
        out_mesh.set_index(tid, tid);
    }
}
END

METAL_FRAGMENT_SHADER :: #string END
#include <metal_stdlib>
#include <metal_graphics>
using namespace metal;

struct VertexOut {
    float4 pos [[position]];
    half3 color [[user(locn0)]];
};

[[fragment]]
float4 fragmentMain(VertexOut vert [[stage_in]]) {
    return float4(float3(vert.color), 1.0);
}
END
