#scope_export

gpu_capture_start :: () -> Gpu_Result {
    main_queue := gpu_get_queue(.MAIN, 0); // TODO

    capture_manager := MTLCaptureManager.sharedCaptureManager();
    if capture_manager == null return .FATAL_ERROR_UNKNOWN;

    set_capture_object_on_descriptor :: (descriptor: *MTLCaptureDescriptor, queue_handle: Gpu_Queue) -> bool {
        if queue_handle != 0 {
            queue := get_queue(queue_handle);
            if queue == null || queue.mtl4_queue == null {
                log_error("gpu_capture_start_in_xcode: invalid queue handle %", queue_handle);
                return false;
            }
            descriptor.setCaptureObject(descriptor, cast(id)queue.mtl4_queue);
            return true;
        }

        descriptor.setCaptureObject(descriptor, cast(id)mtl_device);
        return true;
    }

    if capture_manager.supportsDestination(capture_manager, .DeveloperTools) {
        descriptor := objc_new_defer_release(MTLCaptureDescriptor);
        descriptor.setDestination(descriptor, .DeveloperTools);
        if set_capture_object_on_descriptor(descriptor, queue_handle) {
            error: *NSError = null;
            success := capture_manager.startCaptureWithDescriptor(capture_manager, descriptor, *error);
            if !log_error_if_not_null(error, "startCaptureWithDescriptor") && success {
                log("Metal capture started with destination DeveloperTools.");
                return .SUCCESS;
            }
            if !success log_error("MTLCaptureManager.startCaptureWithDescriptor returned false.");
        }
    }

    if capture_manager.supportsDestination(capture_manager, .GPUTraceDocument) {
        trace_path := sprint("/tmp/sgpu_metal_capture.%.gputrace", to_float64_seconds(current_time_monotonic()).(u64));
        capture_filepath = trace_path;
        descriptor := objc_new_defer_release(MTLCaptureDescriptor);
        descriptor.setDestination(descriptor, .GPUTraceDocument);
        if set_capture_object_on_descriptor(descriptor, queue_handle) {
            url := NSURL.fileURLWithPath(to_temp_nsstring(trace_path));
            descriptor.setOutputURL(descriptor, url);

            error: *NSError = null;
            success := capture_manager.startCaptureWithDescriptor(capture_manager, descriptor, *error);
            if !log_error_if_not_null(error, "startCaptureWithDescriptor") && success {
                log("Metal capture started with destination GPUTraceDocument at %", trace_path);
                return .SUCCESS;
            }
            if !success log_error("MTLCaptureManager.startCaptureWithDescriptor returned false.");
        }
    }

    log_error("No supported MTLCapture destination is available (DeveloperTools/GPUTraceDocument).");
    return .FATAL_ERROR_UNKNOWN;
}

gpu_capture_end :: (open := true) {
    capture_manager := MTLCaptureManager.sharedCaptureManager();
    if capture_manager == null return;
    if capture_manager.isCapturing(capture_manager) {
        log("Stopping Metal render capture.");
        capture_manager.stopCapture(capture_manager);
        if open && capture_filepath {
            Process.run_command("open", capture_filepath);
        }
    } else {
        log_error("gpu_capture_stop was called, but there is no current capture.");
    }

    if capture_filepath {
        free(capture_filepath);
        capture_filepath = "";
    }
}

#scope_file
capture_filepath: string;
Process :: #import "Process";
