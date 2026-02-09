SGPU_ENABLE_SHADER_LOGGING :: true; // @Perf

Gpu_Pipeline :: #type,distinct s64;
Gpu_Texture :: #type,distinct s64;
Gpu_Texture_View :: #type,distinct u32;
Gpu_Sampler :: #type,distinct u32;
Gpu_Depth_Stencil_State :: #type,distinct s64;
Gpu_Blend_State :: #type,distinct s64;
Gpu_Queue :: #type,distinct s64;
Gpu_Command_Buffer :: #type,distinct s64;
Gpu_Semaphore :: #type,distinct s64;

NULL_HANDLE :: 0;

Cull :: enum {
    NONE    :: 0x0;
    CCW     :: 0x1;
    CW      :: 0x2;
    ALL     :: 0x3;
}

Fill :: enum {
    FILL    :: 0;
    LINE    :: 1;
    POINT   :: 2;
}

Depth_Flags :: enum_flags u8 {
    NONE    :: 0;
    READ    :: 1 << 0;
    WRITE   :: 1 << 1;
}

Op :: enum {
    NEVER            :: 0;
    LESS             :: 1;
    EQUAL            :: 2;
    LESS_OR_EQUAL    :: 3;
    GREATER          :: 4;
    NOT_EQUAL        :: 5;
    GREATER_OR_EQUAL :: 6;
    ALWAYS           :: 7;
}

Load_Op :: enum {
    LOAD        :: 0;
    CLEAR       :: 1;
    DONT_CARE   :: 2;
}

Store_Op :: enum {
    STORE       :: 0;
    DONT_CARE   :: 1;
}

Stencil_Op :: enum {
    KEEP;
    ZERO;
    REPLACE;
    INVERT;
    INCREMENT_AND_CLAMP;
    DECREMENT_AND_CLAMP;
    INCREMENT_AND_WRAP;
    DECREMENT_AND_WARP;
}

Blend :: enum {
    ADD;
    SUBTRACT;
    REV_SUBTRACT;
    MIN;
    MAX;
}

Factor :: enum {
    ZERO                     :: 0;
    ONE                      :: 1;
    SRC_COLOR                :: 2;
    ONE_MINUS_SRC_COLOR      :: 3;
    DST_COLOR                :: 4;
    ONE_MINUS_DST_COLOR      :: 5;
    SRC_ALPHA                :: 6;
    ONE_MINUS_SRC_ALPHA      :: 7;
    DST_ALPHA                :: 8;
    ONE_MINUS_DST_ALPHA      :: 9;
    CONSTANT_COLOR           :: 10;
    ONE_MINUS_CONSTANT_COLOR :: 11;
    CONSTANT_ALPHA           :: 12;
    ONE_MINUS_CONSTANT_ALPHA :: 13;
    SRC_ALPHA_SATURATE       :: 14;
}

Component_Flags :: enum_flags {
    R   :: 0x01;
    G   :: 0x02;
    B   :: 0x04;
    A   :: 0x08;
    ALL :: R | G | B | A;
}

Topology :: enum {
    POINT_LIST      :: 0;
    LINE_LIST       :: 1;
    LINE_STRIP      :: 2;
    TRIANGLE_LIST   :: 3;
    TRIANGLE_STRIP  :: 4;
    TRIANGLE_FAN    :: 5;
}

Texture_Type :: enum {
    _1D         :: 0;
    _2D         :: 1;
    _3D         :: 2;
    CUBE        :: 3;
    _1D_ARRAY   :: 4;
    _2D_ARRAY   :: 5;
    CUBE_ARRAY  :: 6;
}

Format :: enum {
    UNDEFINED                                      :: 0;
    R4G4_UNORM_PACK8                               :: 1;
    R4G4B4A4_UNORM_PACK16                          :: 2;
    B4G4R4A4_UNORM_PACK16                          :: 3;
    R5G6B5_UNORM_PACK16                            :: 4;
    B5G6R5_UNORM_PACK16                            :: 5;
    R5G5B5A1_UNORM_PACK16                          :: 6;
    B5G5R5A1_UNORM_PACK16                          :: 7;
    A1R5G5B5_UNORM_PACK16                          :: 8;
    R8_UNORM                                       :: 9;
    R8_SNORM                                       :: 10;
    R8_USCALED                                     :: 11;
    R8_SSCALED                                     :: 12;
    R8_UINT                                        :: 13;
    R8_SINT                                        :: 14;
    R8_SRGB                                        :: 15;
    R8G8_UNORM                                     :: 16;
    R8G8_SNORM                                     :: 17;
    R8G8_USCALED                                   :: 18;
    R8G8_SSCALED                                   :: 19;
    R8G8_UINT                                      :: 20;
    R8G8_SINT                                      :: 21;
    R8G8_SRGB                                      :: 22;
    R8G8B8_UNORM                                   :: 23;
    R8G8B8_SNORM                                   :: 24;
    R8G8B8_USCALED                                 :: 25;
    R8G8B8_SSCALED                                 :: 26;
    R8G8B8_UINT                                    :: 27;
    R8G8B8_SINT                                    :: 28;
    R8G8B8_SRGB                                    :: 29;
    B8G8R8_UNORM                                   :: 30;
    B8G8R8_SNORM                                   :: 31;
    B8G8R8_USCALED                                 :: 32;
    B8G8R8_SSCALED                                 :: 33;
    B8G8R8_UINT                                    :: 34;
    B8G8R8_SINT                                    :: 35;
    B8G8R8_SRGB                                    :: 36;
    R8G8B8A8_UNORM                                 :: 37;
    R8G8B8A8_SNORM                                 :: 38;
    R8G8B8A8_USCALED                               :: 39;
    R8G8B8A8_SSCALED                               :: 40;
    R8G8B8A8_UINT                                  :: 41;
    R8G8B8A8_SINT                                  :: 42;
    R8G8B8A8_SRGB                                  :: 43;
    B8G8R8A8_UNORM                                 :: 44;
    B8G8R8A8_SNORM                                 :: 45;
    B8G8R8A8_USCALED                               :: 46;
    B8G8R8A8_SSCALED                               :: 47;
    B8G8R8A8_UINT                                  :: 48;
    B8G8R8A8_SINT                                  :: 49;
    B8G8R8A8_SRGB                                  :: 50;
    A8B8G8R8_UNORM_PACK32                          :: 51;
    A8B8G8R8_SNORM_PACK32                          :: 52;
    A8B8G8R8_USCALED_PACK32                        :: 53;
    A8B8G8R8_SSCALED_PACK32                        :: 54;
    A8B8G8R8_UINT_PACK32                           :: 55;
    A8B8G8R8_SINT_PACK32                           :: 56;
    A8B8G8R8_SRGB_PACK32                           :: 57;
    A2R10G10B10_UNORM_PACK32                       :: 58;
    A2R10G10B10_SNORM_PACK32                       :: 59;
    A2R10G10B10_USCALED_PACK32                     :: 60;
    A2R10G10B10_SSCALED_PACK32                     :: 61;
    A2R10G10B10_UINT_PACK32                        :: 62;
    A2R10G10B10_SINT_PACK32                        :: 63;
    A2B10G10R10_UNORM_PACK32                       :: 64;
    A2B10G10R10_SNORM_PACK32                       :: 65;
    A2B10G10R10_USCALED_PACK32                     :: 66;
    A2B10G10R10_SSCALED_PACK32                     :: 67;
    A2B10G10R10_UINT_PACK32                        :: 68;
    A2B10G10R10_SINT_PACK32                        :: 69;
    R16_UNORM                                      :: 70;
    R16_SNORM                                      :: 71;
    R16_USCALED                                    :: 72;
    R16_SSCALED                                    :: 73;
    R16_UINT                                       :: 74;
    R16_SINT                                       :: 75;
    R16_SFLOAT                                     :: 76;
    R16G16_UNORM                                   :: 77;
    R16G16_SNORM                                   :: 78;
    R16G16_USCALED                                 :: 79;
    R16G16_SSCALED                                 :: 80;
    R16G16_UINT                                    :: 81;
    R16G16_SINT                                    :: 82;
    R16G16_SFLOAT                                  :: 83;
    R16G16B16_UNORM                                :: 84;
    R16G16B16_SNORM                                :: 85;
    R16G16B16_USCALED                              :: 86;
    R16G16B16_SSCALED                              :: 87;
    R16G16B16_UINT                                 :: 88;
    R16G16B16_SINT                                 :: 89;
    R16G16B16_SFLOAT                               :: 90;
    R16G16B16A16_UNORM                             :: 91;
    R16G16B16A16_SNORM                             :: 92;
    R16G16B16A16_USCALED                           :: 93;
    R16G16B16A16_SSCALED                           :: 94;
    R16G16B16A16_UINT                              :: 95;
    R16G16B16A16_SINT                              :: 96;
    R16G16B16A16_SFLOAT                            :: 97;
    R32_UINT                                       :: 98;
    R32_SINT                                       :: 99;
    R32_SFLOAT                                     :: 100;
    R32G32_UINT                                    :: 101;
    R32G32_SINT                                    :: 102;
    R32G32_SFLOAT                                  :: 103;
    R32G32B32_UINT                                 :: 104;
    R32G32B32_SINT                                 :: 105;
    R32G32B32_SFLOAT                               :: 106;
    R32G32B32A32_UINT                              :: 107;
    R32G32B32A32_SINT                              :: 108;
    R32G32B32A32_SFLOAT                            :: 109;
    R64_UINT                                       :: 110;
    R64_SINT                                       :: 111;
    R64_SFLOAT                                     :: 112;
    R64G64_UINT                                    :: 113;
    R64G64_SINT                                    :: 114;
    R64G64_SFLOAT                                  :: 115;
    R64G64B64_UINT                                 :: 116;
    R64G64B64_SINT                                 :: 117;
    R64G64B64_SFLOAT                               :: 118;
    R64G64B64A64_UINT                              :: 119;
    R64G64B64A64_SINT                              :: 120;
    R64G64B64A64_SFLOAT                            :: 121;
    B10G11R11_UFLOAT_PACK32                        :: 122;
    E5B9G9R9_UFLOAT_PACK32                         :: 123;
    D16_UNORM                                      :: 124;
    X8_D24_UNORM_PACK32                            :: 125;
    D32_SFLOAT                                     :: 126;
    S8_UINT                                        :: 127;
    D16_UNORM_S8_UINT                              :: 128;
    D24_UNORM_S8_UINT                              :: 129;
    D32_SFLOAT_S8_UINT                             :: 130;
    BC1_RGB_UNORM_BLOCK                            :: 131;
    BC1_RGB_SRGB_BLOCK                             :: 132;
    BC1_RGBA_UNORM_BLOCK                           :: 133;
    BC1_RGBA_SRGB_BLOCK                            :: 134;
    BC2_UNORM_BLOCK                                :: 135;
    BC2_SRGB_BLOCK                                 :: 136;
    BC3_UNORM_BLOCK                                :: 137;
    BC3_SRGB_BLOCK                                 :: 138;
    BC4_UNORM_BLOCK                                :: 139;
    BC4_SNORM_BLOCK                                :: 140;
    BC5_UNORM_BLOCK                                :: 141;
    BC5_SNORM_BLOCK                                :: 142;
    BC6H_UFLOAT_BLOCK                              :: 143;
    BC6H_SFLOAT_BLOCK                              :: 144;
    BC7_UNORM_BLOCK                                :: 145;
    BC7_SRGB_BLOCK                                 :: 146;
}

Usage_Flags :: enum_flags {
    NONE                        :: 0x0;
    TRANSFER_SRC                :: 0x1;
    TRANSFER_DST                :: 0x2;
    SAMPLED                     :: 0x4;
    STORAGE                     :: 0x8;
    COLOR_ATTACHMENT            :: 0x10;
    DEPTH_STENCIL_ATTACHMENT    :: 0x20;
}

Stage :: enum {
    TOP_OF_PIPE             :: 0x00000001;
    DRAW_INDIRECT           :: 0x00000002;
    VERTEX_INPUT            :: 0x00000004;
    VERTEX_SHADER           :: 0x00000008;
    PIXEL_SHADER            :: 0x00000080;
    MESH_SHADER             :: 0x00100000;
    EARLY_FRAGMENT_TESTS    :: 0x00000100;
    LATE_FRAGMENT_TESTS     :: 0x00000200;
    COLOR_ATTACHMENT_OUTPUT :: 0x00000400;
    COMPUTE_SHADER          :: 0x00000800;
    TRANSFER                :: 0x00001000;
    BOTTOM_OF_PIPE          :: 0x00002000;
    HOST                    :: 0x00004000;
    ALL                     :: 0x00010000;
}

Gpu_Queue_Type :: enum u8 {
    MAIN        :: 0;
    COMPUTE     :: 1;
    TRANSFER    :: 2;
}

Gpu_Result :: enum s32 {
    SUCCESS :: 0;

    FATAL_MISSING_REQUIRED_EXTENSION;
    FATAL_MISSING_REQUIRED_FEATURE;
    FATAL_NO_SUITABLE_DEVICE_FOUND;
    FATAL_NO_GRAPHICS_QUEUE;
    FATAL_FAILED_TO_QUERY_QUEUE;

    FATAL_OUT_OF_GPU_MEMORY;
    FATAL_OUT_OF_CPU_MEMORY;

    ERROR_MISSING_OPTIONAL_EXTENSION;
    ERROR_COMMAND_BUFFER_LIMIT_EXCEEDED;
    ERROR_TEXTURE_LIMIT_EXCEEDED;

    ERROR_OUT_OF_BOUNDS;

    ERROR_INVALID_VERTEX_INDEX_SIZE;

    ERROR_UNKNOWN_GPU_POINTER;
    ERROR_INVALID_BUFFER;
    ERROR_INVALID_TEXTURE;
    ERROR_INVALID_TEXTURE_VIEW;
    ERROR_INVALID_PIPELINE;

    FATAL_ERROR_UNKNOWN;
}

Gpu_Optional_Features :: enum_flags {
    NONE                    :: 0;
    DESCRIPTOR_BUFFER       :: 1 << 1;
    SHADER_ATOMIC_INT64     :: 1 << 2;
    SHADER_INT16            :: 1 << 3;
    SHADER_INT64            :: 1 << 4;
    SHADER_INT8             :: 1 << 5;
    STORAGE_PUSH_CONSTANT_8 :: 1 << 6;
    MESH_SHADERS            :: 1 << 7;

    // -- nyi --
    RAY_TRACING             ;
}

Stencil_Desc :: struct {
    test: Op = .ALWAYS;
    fail_op: Stencil_Op = .KEEP;
    pass_op: Stencil_Op = .KEEP;
    depth_fail_op: Stencil_Op = .KEEP;
    reference: u8 = 0;
}

Gpu_Blend_Desc :: struct {
    color_op: Blend = .ADD;
    src_color_factor: Factor = .ONE;
    dst_color_factor: Factor = .ZERO;

    alpha_op: Blend = .ADD;
    src_alpha_factor: Factor = .ONE;
    dst_alpha_factor: Factor = .ZERO;

    color_write_mask: Component_Flags = .ALL;
}

Gpu_Depth_Stencil_Desc :: struct {
    depth_mode: Depth_Flags;
    depth_test: Op = .ALWAYS;

    depth_bias: float = 0.;
    depth_bias_slope_factor: float = 0.;
    depth_bias_clamp: float = 0.;

    stencil_read_mask: u8 = 0xff;
    stencil_write_mask: u8 = 0xff;

    stencil_front: Stencil_Desc;
    stencil_back: Stencil_Desc;
}

Rect_2D :: struct {
    x: u32;
    y: u32;
    width: u32;
    height: u32;
}

Viewport :: struct {
    x: float;
    y: float;
    width: float;
    height: float;
    min_depth: float;
    max_depth: float;
}

Color_Target :: struct {
    format: Format = .UNDEFINED;
}

Gpu_Raster_Desc :: struct {
    topology: Topology = .TRIANGLE_LIST;
    cull: Cull = .NONE;
    fill: Fill = .FILL;
    alpha_to_coverage := false;
    support_dual_source_blending := false;
    sample_count: u8 = 1;

    depth_format: Format = .UNDEFINED;
    stencil_format: Format = .UNDEFINED;

    color_targets: [] Color_Target;

    // Optional blend state baked into the pipeline.
    // else dynamic state.
    // blend state is duplicated to all color targets.
    blend_state: *Gpu_Blend_Desc;
}

Gpu_Texture_Desc :: struct {
    type: Texture_Type = ._2D;
    dimensions: [3] u32;

    mip_count: u8 = 1;
    layer_count: u16 = 1;
    sample_count: u32 = 1;

    format: Format = .UNDEFINED;
    usage: Usage_Flags = .NONE;
}

Gpu_View_Desc :: struct {
    format: Format = .UNDEFINED;
    base_mip: u8 = 0;
    mip_count: u8 = 0xFF;
    base_layer: u16 = 0;
    layer_count: u16 = 0xFFFF;
}

Gpu_Dispatch_Args :: struct {
    x: u32;
    y: u32;
    z: u32;
}

Gpu_Draw_Args :: struct {
    index_count: u32;
    instance_count: u32;
    first_index: u32;
    vertex_offset: s32;
    first_instance: u32;
}

Gpu_Sampler_Desc :: struct {
    Filter :: enum {
        NEAREST :: 0;
        LINEAR  :: 1;
    }

    Address_Mode :: enum {
        REPEAT                   :: 0;
        MIRRORED_REPEAT          :: 1;
        CLAMP_TO_EDGE            :: 2;
        CLAMP_TO_BORDER          :: 3;
        MIRROR_CLAMP_TO_EDGE     :: 4;
    }

    Border_Color :: enum {
        FLOAT_TRANSPARENT_BLACK :: 0;
        INT_TRANSPARENT_BLACK   :: 1;
        FLOAT_OPAQUE_BLACK      :: 2;
        INT_OPAQUE_BLACK        :: 3;
        FLOAT_OPAQUE_WHITE      :: 4;
        INT_OPAQUE_WHITE        :: 5;
    }

    min_filter: Filter = .LINEAR;
    mag_filter: Filter = .LINEAR;
    mip_filter: Filter = .LINEAR;

    address_mode_u: Address_Mode = .CLAMP_TO_EDGE;
    address_mode_v: Address_Mode = .CLAMP_TO_EDGE;
    address_mode_w: Address_Mode = .CLAMP_TO_EDGE;

    mip_lod_bias: float = 0.5;
    mip_lod: float = 0.;

    enable_anisotropy: bool = false;
    max_anisotropy: float = 0.;

    compare_op: Op = .ALWAYS;

    min_lod: float = 0.;
    max_lod: float = 1000.;

    border_color: Border_Color;

    unnormalized_coordinates: bool;
}

Gpu_Color_Value :: union {
    _float: [4] float;
    _uint: [4] u32;
    _int: [4] s32;
}

Gpu_Render_Pass_Attachment_Desc :: struct {
    view: Gpu_Texture_View;
    load_op: Load_Op;
    store_op: Store_Op;
    union {
        clear_color: Gpu_Color_Value;
        clear_value: struct {
            depth: float;
            stencil: u32;
        };
    };
}

Gpu_Render_Pass_Desc :: struct {
    depth_target: Gpu_Render_Pass_Attachment_Desc;
    stencil_target: Gpu_Render_Pass_Attachment_Desc;
    color_targets: [] Gpu_Render_Pass_Attachment_Desc;
}

gpu_init :: (optional_features: Gpu_Optional_Features = .DESCRIPTOR_BUFFER) -> Gpu_Result {
    init_objective_c();

    remember_allocator();
    requested_optional_features = optional_features;

    #if RENDER_CAPTURE gpu_capture_init();

    global_autorelease_pool = objc_new(NSAutoreleasePool);

    result := create_device();
    return_if_error(result);

    init_residency();
    init_queues();
    init_bindless();

    return result;
}

gpu_shutdown :: () {
    shutdown_swapchain();
    shutdown_bindless();
    shutdown_queues();
    shutdown_residency();
    release_and_set_null(*mtl_device);
    release_and_set_null(*global_autorelease_pool);
    #if SLANG_COMPILER gpu_internal_slang_shutdown();
}

#load "pool.jai";
#load "memory.jai";
#load "command_buffer.jai";
#load "textures.jai";
#load "bindless.jai";
#load "pipeline.jai";
#load "render_capture.jai";
#load "gpu_arena.jai";
#load "swapchain.jai";
#load "sync.jai";
#load "residency.jai";
#load "window_capture.jai";
#if SLANG_COMPILER #load "shader_compiler.jai";

Optional_Extension :: enum {
    DESCRIPTOR_BUFFER :: 0;
    MESH_SHADERS      :: 1;
}

Optional_Extension_Info :: struct {
    name: *u8;
    supported: bool;
}

is_optional_ext_supported :: (ext: Optional_Extension) -> bool {
    return optional_extensions[ext].supported;
}

global_autorelease_pool: *NSAutoreleasePool;
cpu_allocator: Allocator; // we remember the allocator passed into gpu_init and ensure all cpu allocations occur using that allocator.
optional_extensions: [#run enum_highest_value(Optional_Extension) + 1] Optional_Extension_Info;
requested_optional_features: Gpu_Optional_Features;
mtl_device: *MTLDevice;

MAX_BUFFERS  :: 256;
MAX_IMAGES   :: 1024;
MAX_SAMPLERS :: 10;

MAX_COMPUTE_QUEUES  :: 4;
MAX_TRANSFER_QUEUES :: 2;

MAX_FRAMES_IN_FLIGHT :: 3;

// 16 seems like a reasonable cap on this. Prevents some unnecessary heap allocations
MAX_ATTACHMENTS :: 16;

#scope_module

#import "Objective_C";
#import "Metal";
#import "Basic";
#import "String";
#import "Math";
#import "Bucket_Array";
#import "Atomics";

create_device :: () -> Gpu_Result {
    auto_release_temp();
    push_allocator(temp);
    mtl_device = MTLCreateSystemDefaultDevice();
    if mtl_device == null {
        return .FATAL_NO_SUITABLE_DEVICE_FOUND;
    }
    return .SUCCESS;
}

remember_allocator :: () {
    cpu_allocator = context.allocator;

    live_pipelines.allocator = cpu_allocator;
    live_textures.allocator = cpu_allocator;

    // TODO: more...
}

return_if_error :: (result: Gpu_Result, v: $T) #expand {
    if result != .SUCCESS {
        #if DEBUG_ASSERTS {
            debug_break();
        }
        `return result, v;
    }
}

return_if_error :: (result: Gpu_Result) #expand {
    if result != .SUCCESS {
        #if DEBUG_ASSERTS {
            debug_break();
        }
        `return result;
    }
}

return_if_null :: (ptr: *$T) #expand {
    if ptr == null {
        `return;
    }
}

debug_assert :: (arg: bool, message := "", args: ..Any, loc := #caller_location) #no_debug #expand {
    #if DEBUG_ASSERTS {
        assert(arg, message, args, loc);
    }
}

release_and_set_null :: (p: **$T/NSObject) {
    if p.* != null {
        release(p.*);
        p.* = null;
    }
}

to_temp_nsstring :: (str: string) -> *NSString #expand {
    result := NSString.initWithString(objc_alloc(NSString), str);
    `defer release(result);
    return result;
}

objc_new_defer_release :: ($type: Type) -> *type #expand {
    obj := objc_new(type);
    `defer release(obj);
    return obj;
}

objc_scope_new :: objc_new_defer_release;

log_error_if_not_null :: (error: *NSError, description: string = "") -> bool {
    if error == null return false;

    err_str := to_string(NSError.localizedDescription(error));
    if description {
        log_error("%: %", description, err_str);
    } else {
        log_error(err_str);
    }

    return true;
}

nserror_to_string :: (nsError: *NSError) -> string {
    // @Leak ?
    error_string := NSError.localizedDescription(nsError);
    error_string_utf8 := NSString.UTF8String(error_string);
    return to_string(error_string_utf8);
}
