#module_parameters(
    // Optionally enables Vulkan validation layers.
    VALIDATION := false,
    // Optionally enables debug assertions within the sgpu module
    DEBUG_ASSERTS := false,
    // Optionally includes an api for taking render doc captures
    RENDER_CAPTURE := false,
    // Optionally includes a slang shader compiler submodule
    SLANG_COMPILER := true
);

#if OS == .MACOS {
    #load "backend_metal/sgpu_metal.jai";
} else {
    #load "backend_vulkan/sgpu_vulkan.jai";
}
