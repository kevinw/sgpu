main :: () {
    gpu_init();

    ptr := gpu_malloc(1024);
    _, gpu_ptr := gpu_malloc(1024, .GPU);

    memset(ptr, 255, 1024);

    gpu_free(ptr);
    gpu_free(gpu_ptr);

    gpu_host_to_device_ptr(ptr);


    gpu_shutdown();
}

#import,file "../../simp_gpu/module.jai"(VALIDATION = true);
