/*

To build a single example:

    jai -quiet build.jai - 03_hello_square

or to build all examples:

    jai -quiet build.jai

or to build and run all examples in a single frame test mode:

    jai -quiet build.jai - -run_tests

*/


DEFAULT_EXAMPLES_TO_BUILD :: string.[
    "01_memory",
    "02_compute",
    "03_hello_square",
];

#scope_file

#run,stallable {
    set_build_options_dc(.{do_output = false});
    make_directory_if_it_does_not_exist("bin");

    // Arguments passed after " - " are treated as example names to build.
    files_to_build: [..]string;
    run_tests := false;
    for get_build_options().compile_time_command_line {
        if it.count > 0 && it[0] != #char "-" {
            array_add(*files_to_build, it);
        } else if it == "-run_tests" {
            run_tests = true;
        }
    }

    if files_to_build.count == 0 {
        log("Building all examples (%)", join(..DEFAULT_EXAMPLES_TO_BUILD, separator=", "));
        array_add(*files_to_build, ..DEFAULT_EXAMPLES_TO_BUILD);
    }

    for files_to_build {
        if !compile_example(it) {
            log_error("Failed to compile example '%'.", it);
            exit(1);
        }
    }

    copy_module_libraries_to_target("bin");

    if run_tests {
        if files_to_build.count == 0 {
            log_error("No examples were built, so no tests to run.");
            exit(1);
        }
        for files_to_build {
            log("Running test for '%'...", it);
            args: [..]string;
            defer array_free(args);
            array_add(*args, tprint("./%", it), "-max_frames", "1");
            run_command_checked(it, args, working_directory = "bin");
        }
        log("Ran % tests successfully: %", files_to_build.count, join(..files_to_build, separator=", "));
    }
}

compile_example :: (name: string) -> bool {
    w := compiler_create_workspace(name);
    options := get_build_options();
    {
        using options;
        output_type = .EXECUTABLE;
        output_executable_name = name;
        output_path = "bin";

        modules_paths: [..]string;
        array_add(*modules_paths, "../modules");
        array_add(*modules_paths, ..import_path);
        import_path = modules_paths;
        additional_linker_arguments = .["-sectcreate", "__TEXT", "__info_plist", "Info.plist"];
    }

    if OS == .LINUX {
        compiler_add_library_search_directory(gcc_lib_dir());
    }

    set_build_options(options, w);

    intercept_flags: Intercept_Flags = .SKIP_ALL; // We're only interested in the .COMPLETE message.
    compiler_begin_intercept(w, intercept_flags);
    defer compiler_end_intercept(w);

    add_build_file(tprint("%.jai", name), w);

    // Wait for .COMPLETE message, and return true if it didn't contain an error.
    while true {
        message := compiler_wait_for_message();
        if message.kind == .COMPLETE {
            message_complete := cast(*Message_Complete)message;
            return message_complete.error_code == .NONE;
        }
    }

    return false;
}

gcc_lib_dir :: () -> string {
    #import "Process";
    #import "String";

    cmd: [] string = .["gcc", "-print-libgcc-file-name"];
    process_result, output_string, error_string, timeout_reached := run_command(..cmd, capture_and_return_output = true);

    return path_strip_filename(output_string);
}

copy_module_libraries_to_target :: (output_path: string) {
    dir_list :: (path: string, recursive := false) -> [] string {
        dirs: [..] string;

        visitor :: (info: *File_Visit_Info, user_data: *[..] string) {
            array_add(user_data, copy_string(info.full_name));
        }

        visit_files(path, recursive, *dirs, visitor, visit_files=false, visit_directories=true);
        return dirs;
    }

    push_allocator(temp);

    module_directories := dir_list("../modules", recursive=false);
    for module : module_directories {
        #if OS == {
            case .WINDOWS;
                os_name := "win";
                lib_ext := ".dll";
            case .MACOS;
                os_name := "mac";
                lib_ext := ".dylib";
            case .LINUX;
                os_name := "linux";
                lib_ext := ".so";
        }
        module_lib_dir_name := tprint("%/%", module, os_name);
        if is_directory(module_lib_dir_name) {

            module_binary_list := file_list(module_lib_dir_name);
            for binary : module_binary_list {
                if ends_with(binary, lib_ext) {
                    copy_file(binary, tprint("%/%", output_path, path_filename(binary)));
                }
            }
        }
    }
}


run_command_checked :: (description: string, args: [] string, working_directory := "", timeout_ms := -1) {
    command := Process.get_quoted_command_string(args);
    result, output, error, timeout_reached := Process.run_command(..args, working_directory=working_directory, timeout_ms=timeout_ms);

    fail :: (message: string, args: .. Any) {
        log_error(message, ..args);
        exit(1);
    }

    if timeout_reached {
        fail("% timed out. Command: %", description, command);
    }

    if result.type == .FAILED_TO_LAUNCH {
        fail("% failed to launch. Command: %", description, command);
    }

    if result.type != .EXITED || result.exit_code != 0 {
        fail("% failed with exit code %. Command: %", description, result.exit_code, command);
    }
}

#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
Process :: #import "Process";
