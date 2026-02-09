#scope_export

gpu_create_semaphore :: (initial: u64) -> Gpu_Semaphore {
    mtl_event := MTLDevice.newSharedEvent(mtl_device);
    if mtl_event == null {
        return 0;
    }

    // Set initial value
    MTLSharedEvent.setSignaledValue(mtl_event, initial);

    handle := pool_add(*live_semaphores, .{mtl_event});
    if handle == 0 {
        log_error("Exceeded semaphore allocation capacity!");
        release(mtl_event);
        return 0;
    }

    return handle;
}

gpu_wait_semaphore :: (timeline: Gpu_Timeline_Pair) {
    semaphore := get_semaphore(timeline.semaphore);
    if semaphore == null || semaphore.mtl_event == null then return;

    // Use MTLSharedEvent's waitUntilSignaledValue for synchronous wait
    // This blocks until the event reaches the specified value
    success := MTLSharedEvent.waitUntilSignaledValue(semaphore.mtl_event, timeline.value, U64_MAX);
    if !success {
        log_error("Semaphore wait timed out");
    }
}

gpu_destroy_semaphore :: (semaphore_handle: Gpu_Semaphore) {
    removed, semaphore := pool_remove(*live_semaphores, semaphore_handle);
    if removed && semaphore.mtl_event != null {
        release(semaphore.mtl_event);
    }
}

gpu_signal_semaphore :: (queue_handle: Gpu_Queue, semaphore_handle: Gpu_Semaphore, value: u64) {
    queue := get_queue(queue_handle);
    if queue == null || queue.mtl4_queue == null then return;

    semaphore := get_semaphore(semaphore_handle);
    if semaphore == null || semaphore.mtl_event == null then return;

    MTL4CommandQueue.signalEvent(queue.mtl4_queue, semaphore.mtl_event, value);
}

gpu_wait_semaphore_on_queue :: (queue_handle: Gpu_Queue, semaphore_handle: Gpu_Semaphore, value: u64) {
    queue := get_queue(queue_handle);
    if queue == null || queue.mtl4_queue == null then return;

    semaphore := get_semaphore(semaphore_handle);
    if semaphore == null || semaphore.mtl_event == null then return;

    MTL4CommandQueue.waitForEvent(queue.mtl4_queue, semaphore.mtl_event, value);
}

gpu_get_semaphore_value :: (semaphore_handle: Gpu_Semaphore) -> u64 {
    using semaphore := get_semaphore(semaphore_handle);
    if semaphore == null || mtl_event == null then return 0;
    return mtl_event.signaledValue(mtl_event);
}

#scope_module

Semaphore :: struct {
    mtl_event: *MTLSharedEvent;
}

live_semaphores: Pool(Gpu_Semaphore, Semaphore);

get_semaphore :: (semaphore_handle: Gpu_Semaphore) -> *Semaphore {
    return pool_get(live_semaphores, semaphore_handle);
}

U64_MAX :: 0xFFFF_FFFF_FFFF_FFFF;
