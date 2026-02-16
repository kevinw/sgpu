#scope_export

// Call this after you've added a batch of allocations
gpu_commit_residency :: () {
    assert(global_residency_set != null);
    MTLResidencySet.commit(global_residency_set);
}

#scope_module

global_residency_set: *MTLResidencySet;

init_residency :: () {
    desc := objc_scope_new(MTLResidencySetDescriptor);
    desc.setInitialCapacity(desc, 128);

    error: *NSError = null;
    global_residency_set = MTLDevice.newResidencySetWithDescriptor(mtl_device, desc, *error);
    if log_error_if_not_null(error) {
        assert(false);
    }
    assert(global_residency_set != null);
}

shutdown_residency :: () {
    if global_residency_set != null {
        release(global_residency_set);
        global_residency_set = null;
    }
}

// Call this after creating any MTLBuffer, MTLTexture, or pipeline
add_to_residency :: (allocation: *MTLAllocation) {
    assert(global_residency_set != null);
    assert(allocation != null);
    global_residency_set.addAllocation(global_residency_set, allocation);
}

remove_from_residency :: (allocation: *MTLAllocation) {
    if global_residency_set == null return;
    if allocation == null return;
    global_residency_set.removeAllocation(global_residency_set, allocation);
}


// Attach residency set to a queue (call during queue init)
attach_residency_to_queue :: (queue: *MTL4CommandQueue) {
    assert(global_residency_set != null);
    assert(queue != null);
    queue.addResidencySet(queue, global_residency_set);
}
