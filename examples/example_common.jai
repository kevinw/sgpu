EXTRA_CHECKS :: true;
SHOW_MEMORY_LEAKS :: true;

#if EXTRA_CHECKS {
    Debug :: #import "Debug";

    Example_Options :: struct {
        max_frames: int;        @"?Stop after the given number of frames (0 for infinite)."
        capture_frame: bool;    @"?Invoke one programmatic Metal capture in Xcode tools."
        dump_framebuffer: bool; @"?Dump the first frame's framebuffer to an image file."
    }

    gpu_example_harness :: () -> Example_Options #expand {
        Debug.init();

        // Check for optional command-line arguments for automated testing.
        // -singleframe: run a fixed small frame count.
        // -captureframe: invoke one programmatic Metal capture in Xcode tools.
        args_ok, args, is_set := parse_arguments(Example_Options);
        if !args_ok exit(1);

        #if SHOW_MEMORY_LEAKS `defer exit_with_error_on_memory_leak();

        return args;
    }

    exit_with_error_on_memory_leak :: () {
        has_leaks := false;
        has_leaks |= show_jai_mem_leaks();
        has_leaks |= gpu_log_memory_leaks();
        if has_leaks {
            exit(1);
        }
    }

    show_jai_mem_leaks :: (options: Leak_Report_Options = .{}) -> (has_leaks: bool) {
        report := make_leak_report(options);
        defer deinit(*report);
        log_leak_report(report, options);

        has_leaks := false;
        for report.sorted_summaries if it.count > 0 {
            has_leaks = true;
        }
        return has_leaks;
    }
} else {
    example_debug_harness :: () #expand {}
}

// TODO: let the user specify these module parameters to basic, and use #if #exists ?
#import "Basic"()(
    MEMORY_DEBUGGER=EXTRA_CHECKS,
    VISUALIZE_MEMORY_DEBUGGER=false,
    TEMP_ALLOCATOR_POISON_FREED_MEMORY=EXTRA_CHECKS,
);

#import "Command_Line";
