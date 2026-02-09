main :: () {
    gpu_example_harness();

    result := gpu_init();
    defer gpu_shutdown();
    assert(result == .SUCCESS);

    COUNT :: 1024;

    buffer_cpu, buffer_gpu := gpu_malloc([COUNT] float);
    assert(buffer_cpu != null);
    defer gpu_free(buffer_cpu);

    for 0..COUNT-1 {
        buffer_cpu.*[it] = 0.0;
    }

    // Compile Slang shader to Metal with MTL4 argument table bindless support
    // The Slang shader uses preprocessor directives to generate Metal-compatible code
    success, compiled_shader := compile_shader("../shaders/compute.slang"); assert(success, "Failed to compile shader");
    defer if compiled_shader array_free(compiled_shader);

    pipeline := gpu_create_compute_pipeline(compiled_shader);
    defer gpu_free_pipeline(pipeline);

    // We will use the dedicated compute queue here but we could also use the MAIN queue.
    // It is required to support compute operations as well as graphics
    compute_queue := gpu_get_queue(.COMPUTE, 0);
    result=, cmd_buff := gpu_start_command_recording(compute_queue);
    assert(result == .SUCCESS);

    result = gpu_set_pipeline(cmd_buff, pipeline);
    assert(result == .SUCCESS);

    // All shaders invocations in SGPU take as input a pointer to a block of user allocated memory.
    // That memory can be a block of parameters or it can be data to mutate. Entirely up to the programmer.
    // If the shader has no parameters, it is fine to pass null or 0 to those arguments.
    //
    // A common pattern is to use an arena allocator to push parameter structs into gpu memory.
    // See later samples for examples of this.
    //
    // In this case, the output data pointer is simply passed to the shader as this user_data ptr so it can write to it.
    // With MTL4 bindless, gpu_dispatch uses the global argument table
    // The buffer pointer is set in the argument table at index 0
    gpu_dispatch(cmd_buff, buffer_gpu, .[(COUNT + 63) / 64, 1, 1]);

    gpu_submit(cmd_buff);
    gpu_wait_idle();


    for 0..COUNT-1 {
        assert(buffer_cpu.*[it] == 1.0, "Expected the compute shader to set each buffer value to 1.0, but the %th value was %", it, buffer_cpu.*[it]);
    }

    print("OK!\n");
}

#import,file "../module.jai"(VALIDATION = true, SLANG_COMPILER = true);
#load "example_common.jai";
