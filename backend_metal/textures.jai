#scope_export

gpu_create_texture :: (desc: Gpu_Texture_Desc) -> Gpu_Texture {
    // Set usage flags
    mtl_usage: MTLTextureUsage = 0;
    if (desc.usage & Usage_Flags.SAMPLED) != 0                  mtl_usage |= cast(MTLTextureUsage) MTLTextureUsage_1.ShaderRead;
    if (desc.usage & Usage_Flags.STORAGE) != 0                  mtl_usage |= cast(MTLTextureUsage) MTLTextureUsage_1.ShaderWrite;
    if (desc.usage & Usage_Flags.COLOR_ATTACHMENT) != 0         mtl_usage |= cast(MTLTextureUsage) MTLTextureUsage_1.RenderTarget;
    if (desc.usage & Usage_Flags.DEPTH_STENCIL_ATTACHMENT) != 0 mtl_usage |= cast(MTLTextureUsage) MTLTextureUsage_1.RenderTarget;

    mtl_desc := objc_new(MTLTextureDescriptor);
    defer release(mtl_desc);
    {
        using mtl_desc;
        setTextureType(mtl_desc, texture_type_to_mtl(desc.type));
        setPixelFormat(mtl_desc, format_to_mtl(desc.format));
        setWidth(mtl_desc, desc.dimensions[0].(NSUInteger));
        setHeight(mtl_desc, desc.dimensions[1].(NSUInteger));
        setDepth(mtl_desc, desc.dimensions[2].(NSUInteger));
        setMipmapLevelCount(mtl_desc, desc.mip_count.(NSUInteger));
        setArrayLength(mtl_desc, max(1, desc.layer_count).(NSUInteger));
        setSampleCount(mtl_desc, max(1, desc.sample_count).(NSUInteger));
        setUsage(mtl_desc, mtl_usage);
        // CPU upload path uses replaceRegion, which requires CPU-visible storage.
        if (desc.usage & Usage_Flags.TRANSFER_DST) != 0 {
            setStorageMode(mtl_desc, .Shared);
        } else {
            setStorageMode(mtl_desc, .Private);
        }
    }

    mtl_texture := MTLDevice.newTextureWithDescriptor(mtl_device, mtl_desc);
    if mtl_texture == null {
        return 0;
    }
    add_to_residency(xx mtl_texture);

    handle := pool_add(*live_textures, {
        desc = desc,
        mtl_texture = mtl_texture,
    });

    return handle;
}

gpu_free :: (texture_handle: Gpu_Texture) {
    removed, texture := pool_remove(*live_textures, texture_handle);
    if removed && texture.mtl_texture != null {
        remove_from_residency(xx texture.mtl_texture);
        release(texture.mtl_texture);
    }
}

gpu_texture_view :: (texture_handle: Gpu_Texture, view_desc: Gpu_View_Desc = .{}) -> Gpu_Texture_View {
    texture := pool_get(live_textures, texture_handle);
    if texture == null then return 0;

    // Use texture's format if view doesn't specify one
    format := ifx view_desc.format != .UNDEFINED then view_desc.format else texture.desc.format;
    mip_count := ifx view_desc.mip_count > 0 then view_desc.mip_count else texture.desc.mip_count;
    layer_count := ifx view_desc.layer_count > 0 then view_desc.layer_count else texture.desc.layer_count;

    // For simple case, just use the texture directly
    // Metal allows creating texture views for format reinterpretation
    mtl_texture_view := texture.mtl_texture;

    // If we need a different format, create a texture view
    if format != texture.desc.format {
        mtl_texture_view = MTLTexture.newTextureViewWithPixelFormat(
            texture.mtl_texture,
            format_to_mtl(format)
        );
        if mtl_texture_view == null {
            return 0;
        }
    }

    final_desc := Gpu_View_Desc.{
        format = format,
        base_mip = view_desc.base_mip,
        mip_count = mip_count,
        base_layer = view_desc.base_layer,
        layer_count = layer_count,
    };

    handle := pool_add(*live_texture_views, .{
        texture = texture_handle,
        mtl_texture = mtl_texture_view,
        desc = final_desc,
    });

    if handle != 0 {
        bindless_set_texture_resource(handle, mtl_texture_view);
    }

    return handle;
}

gpu_free_texture_view :: (view_handle: Gpu_Texture_View) {
    removed, view := pool_remove(*live_texture_views, view_handle);
    if removed {
        bindless_set_texture_resource(view_handle, null);

        // Only release if this is a view we created (not the original texture)
        texture := pool_get(live_textures, view.texture);
        if texture != null && view.mtl_texture != texture.mtl_texture {
            release(view.mtl_texture);
        }
    }
}

gpu_texture_view_size :: (view_handle: Gpu_Texture_View) -> (width: u32, height: u32, ok: bool) {
    view := get_texture_view(view_handle);
    if !view return 0, 0, false;
    texture := get_texture(view.texture);
    if !texture return 0, 0, false;
    return texture.desc.dimensions[0], texture.desc.dimensions[1], true;
}

gpu_readback_texture_view_bgra8 :: (view_handle: Gpu_Texture_View, out_pixels: []u8, bytes_per_row: s64) -> bool {
    view := get_texture_view(view_handle);
    if !view || !view.mtl_texture return false;
    texture := get_texture(view.texture);
    if !texture return false;
    if texture.desc.format != .B8G8R8A8_UNORM && texture.desc.format != .B8G8R8A8_SRGB return false;
    if bytes_per_row < cast(s64) texture.desc.dimensions[0] * 4 return false;

    required_bytes := bytes_per_row * cast(s64) texture.desc.dimensions[1];
    if cast(s64) out_pixels.count < required_bytes return false;

    region := MTLRegion.{
        origin = .{ x = 0, y = 0, z = 0 },
        size = .{
            width = cast(NSUInteger) texture.desc.dimensions[0],
            height = cast(NSUInteger) texture.desc.dimensions[1],
            depth = 1,
        },
    };
    MTLTexture.getBytes(view.mtl_texture,
                        out_pixels.data,
                        cast(NSUInteger) bytes_per_row,
                        region,
                        0);
    return true;
}

gpu_copy_to_texture :: (dest: Gpu_Texture, src: *void, mip: u32 = 0, layer_slice: [2] u32 = .[0, U32_MAX]) {
    texture := get_texture(dest);
    if !texture || !texture.mtl_texture || src == null return;
    if mip != 0 return;
    if layer_slice[0] != 0 return;

    bytes_per_pixel := format_bytes_per_pixel(texture.desc.format);
    if bytes_per_pixel == 0 {
        log_error("gpu_copy_to_texture: unsupported format %", texture.desc.format);
        return;
    }

    region := MTLRegion.{
        origin = .{ x = 0, y = 0, z = 0 },
        size = .{
            width = cast(NSUInteger) texture.desc.dimensions[0],
            height = cast(NSUInteger) texture.desc.dimensions[1],
            depth = 1,
        },
    };
    bytes_per_row := cast(NSUInteger) texture.desc.dimensions[0] * bytes_per_pixel;
    MTLTexture.replaceRegion(texture.mtl_texture, region, 0, src, bytes_per_row);
}

gpu_create_sampler :: (desc: Gpu_Sampler_Desc) -> Gpu_Sampler {
    mtl_desc := objc_new(MTLSamplerDescriptor);
    defer release(mtl_desc);

    using mtl_desc;
    setMinFilter(mtl_desc, sampler_filter_to_mtl_minmag(desc.min_filter));
    setMagFilter(mtl_desc, sampler_filter_to_mtl_minmag(desc.mag_filter));
    setMipFilter(mtl_desc, sampler_filter_to_mtl_mip(desc.mip_filter));
    setSAddressMode(mtl_desc, sampler_address_mode_to_mtl(desc.address_mode_u));
    setTAddressMode(mtl_desc, sampler_address_mode_to_mtl(desc.address_mode_v));
    setRAddressMode(mtl_desc, sampler_address_mode_to_mtl(desc.address_mode_w));
    setLodBias(mtl_desc, desc.mip_lod_bias);
    setMaxAnisotropy(mtl_desc, max(cast(NSUInteger) 1, desc.max_anisotropy.(NSUInteger)));
    setCompareFunction(mtl_desc, op_to_mtl_compare(desc.compare_op));
    setLodMinClamp(mtl_desc, desc.min_lod);
    setLodMaxClamp(mtl_desc, desc.max_lod);
    setBorderColor(mtl_desc, sampler_border_color_to_mtl(desc.border_color));
    setNormalizedCoordinates(mtl_desc, (!desc.unnormalized_coordinates).(BOOL));
    setSupportArgumentBuffers(mtl_desc, YES);

    mtl_sampler := MTLDevice.newSamplerStateWithDescriptor(mtl_device, mtl_desc);
    if mtl_sampler == null return 0;

    handle := pool_add(*live_samplers, .{
        mtl_sampler = mtl_sampler,
    });
    if handle == 0 {
        release(mtl_sampler);
        log_error("Exceeded maximum number of texture samplers (%)!", live_samplers.max);
        return 0;
    }

    bindless_set_sampler_resource(handle, MTLSamplerState.gpuResourceID(mtl_sampler));
    return handle;
}

gpu_free :: (sampler_handle: Gpu_Sampler) {
    removed, sampler := pool_remove(*live_samplers, sampler_handle);
    if removed {
        bindless_set_sampler_resource(sampler_handle, .{});
        if sampler.mtl_sampler != null {
            release(sampler.mtl_sampler);
        }
    }
}

#scope_module

Texture :: struct {
    desc: Gpu_Texture_Desc;
    mtl_texture: *MTLTexture;
}

Texture_View :: struct {
    texture: Gpu_Texture;
    mtl_texture: *MTLTexture;
    desc: Gpu_View_Desc;
}

Sampler :: struct {
    mtl_sampler: *MTLSamplerState;
}

live_textures: Pool(Gpu_Texture, Texture, max = MAX_IMAGES);
live_texture_views: Pool(Gpu_Texture_View, Texture_View, max = MAX_IMAGES * 2);
live_samplers: Pool(Gpu_Sampler, Sampler, max = MAX_SAMPLERS);

get_texture :: (handle: Gpu_Texture) -> *Texture {
    return pool_get(live_textures, handle);
}

get_texture_view :: (handle: Gpu_Texture_View) -> *Texture_View {
    return pool_get(live_texture_views, handle);
}

sampler_filter_to_mtl_minmag :: (filter: Gpu_Sampler_Desc.Filter) -> MTLSamplerMinMagFilter {
    if filter == .NEAREST return .Nearest;
    return .Linear;
}

sampler_filter_to_mtl_mip :: (filter: Gpu_Sampler_Desc.Filter) -> MTLSamplerMipFilter {
    if filter == .NEAREST return .Nearest;
    return .Linear;
}

sampler_address_mode_to_mtl :: (mode: Gpu_Sampler_Desc.Address_Mode) -> MTLSamplerAddressMode {
    if mode == {
        case .REPEAT;               return .Repeat;
        case .MIRRORED_REPEAT;      return .MirrorRepeat;
        case .CLAMP_TO_EDGE;        return .ClampToEdge;
        case .CLAMP_TO_BORDER;      return .ClampToBorderColor;
        case .MIRROR_CLAMP_TO_EDGE; return .MirrorClampToEdge;
    }
    return .ClampToEdge;
}

sampler_border_color_to_mtl :: (color: Gpu_Sampler_Desc.Border_Color) -> MTLSamplerBorderColor {
    if color == {
        case .FLOAT_TRANSPARENT_BLACK; return .TransparentBlack;
        case .INT_TRANSPARENT_BLACK;   return .TransparentBlack;
        case .FLOAT_OPAQUE_BLACK;      return .OpaqueBlack;
        case .INT_OPAQUE_BLACK;        return .OpaqueBlack;
        case .FLOAT_OPAQUE_WHITE;      return .OpaqueWhite;
        case .INT_OPAQUE_WHITE;        return .OpaqueWhite;
    }
    return .TransparentBlack;
}

op_to_mtl_compare :: (op: Op) -> MTLCompareFunction {
    if op == {
        case .NEVER;            return .Never;
        case .LESS;             return .Less;
        case .EQUAL;            return .Equal;
        case .LESS_OR_EQUAL;    return .LessEqual;
        case .GREATER;          return .Greater;
        case .NOT_EQUAL;        return .NotEqual;
        case .GREATER_OR_EQUAL; return .GreaterEqual;
        case .ALWAYS;           return .Always;
    }
    return .Always;
}

format_bytes_per_pixel :: (format: Format) -> NSUInteger {
    if format == {
        case .R8_UNORM; #through;
        case .R8_SNORM; #through;
        case .R8_UINT; #through;
        case .R8_SINT;
            return 1;
        case .R8G8_UNORM; #through;
        case .R8G8_SNORM; #through;
        case .R8G8_UINT; #through;
        case .R8G8_SINT; #through;
        case .R16_UNORM; #through;
        case .R16_SNORM; #through;
        case .R16_UINT; #through;
        case .R16_SINT; #through;
        case .R16_SFLOAT;
            return 2;
        case .R8G8B8A8_UNORM; #through;
        case .R8G8B8A8_SNORM; #through;
        case .R8G8B8A8_UINT; #through;
        case .R8G8B8A8_SINT; #through;
        case .R8G8B8A8_SRGB; #through;
        case .B8G8R8A8_UNORM; #through;
        case .B8G8R8A8_SRGB; #through;
        case .R16G16_UNORM; #through;
        case .R16G16_SNORM; #through;
        case .R16G16_UINT; #through;
        case .R16G16_SINT; #through;
        case .R16G16_SFLOAT; #through;
        case .R32_UINT; #through;
        case .R32_SINT; #through;
        case .R32_SFLOAT; #through;
        case .A2R10G10B10_UNORM_PACK32; #through;
        case .A2R10G10B10_UINT_PACK32;
            return 4;
        case .R16G16B16A16_UNORM; #through;
        case .R16G16B16A16_SNORM; #through;
        case .R16G16B16A16_UINT; #through;
        case .R16G16B16A16_SINT; #through;
        case .R16G16B16A16_SFLOAT; #through;
        case .R32G32_UINT; #through;
        case .R32G32_SINT; #through;
        case .R32G32_SFLOAT;
            return 8;
        case .R32G32B32A32_UINT; #through;
        case .R32G32B32A32_SINT; #through;
        case .R32G32B32A32_SFLOAT;
            return 16;
    }
    return 0;
}

texture_type_to_mtl :: (type: Texture_Type) -> MTLTextureType {
    if type == {
        case ._1D;        return ._1D;
        case ._2D;        return ._2D;
        case ._3D;        return ._3D;
        case .CUBE;       return .Cube;
        case ._1D_ARRAY;  return ._1DArray;
        case ._2D_ARRAY;  return ._2DArray;
        case .CUBE_ARRAY; return .CubeArray;
    }
    return ._2D;
}

format_to_mtl :: (format: Format) -> MTLPixelFormat {
    if format == {
        case .UNDEFINED;            return .Invalid;
        case .R8_UNORM;             return .R8Unorm;
        case .R8_SNORM;             return .R8Snorm;
        case .R8_UINT;              return .R8Uint;
        case .R8_SINT;              return .R8Sint;
        case .R16_UNORM;            return .R16Unorm;
        case .R16_SNORM;            return .R16Snorm;
        case .R16_UINT;             return .R16Uint;
        case .R16_SINT;             return .R16Sint;
        case .R16_SFLOAT;           return .R16Float;
        case .R8G8_UNORM;           return .RG8Unorm;
        case .R8G8_SNORM;           return .RG8Snorm;
        case .R8G8_UINT;            return .RG8Uint;
        case .R8G8_SINT;            return .RG8Sint;
        case .R32_UINT;             return .R32Uint;
        case .R32_SINT;             return .R32Sint;
        case .R32_SFLOAT;           return .R32Float;
        case .R16G16_UNORM;         return .RG16Unorm;
        case .R16G16_SNORM;         return .RG16Snorm;
        case .R16G16_UINT;          return .RG16Uint;
        case .R16G16_SINT;          return .RG16Sint;
        case .R16G16_SFLOAT;        return .RG16Float;
        case .R8G8B8A8_UNORM;       return .RGBA8Unorm;
        case .R8G8B8A8_SNORM;       return .RGBA8Snorm;
        case .R8G8B8A8_UINT;        return .RGBA8Uint;
        case .R8G8B8A8_SINT;        return .RGBA8Sint;
        case .R8G8B8A8_SRGB;        return .RGBA8Unorm_sRGB;
        case .B8G8R8A8_UNORM;       return .BGRA8Unorm;
        case .B8G8R8A8_SRGB;        return .BGRA8Unorm_sRGB;
        case .A2R10G10B10_UNORM_PACK32; return .RGB10A2Unorm;
        case .A2R10G10B10_UINT_PACK32;  return .RGB10A2Uint;
        case .R32G32_UINT;          return .RG32Uint;
        case .R32G32_SINT;          return .RG32Sint;
        case .R32G32_SFLOAT;        return .RG32Float;
        case .R16G16B16A16_UNORM;   return .RGBA16Unorm;
        case .R16G16B16A16_SNORM;   return .RGBA16Snorm;
        case .R16G16B16A16_UINT;    return .RGBA16Uint;
        case .R16G16B16A16_SINT;    return .RGBA16Sint;
        case .R16G16B16A16_SFLOAT;  return .RGBA16Float;
        case .R32G32B32A32_UINT;    return .RGBA32Uint;
        case .R32G32B32A32_SINT;    return .RGBA32Sint;
        case .R32G32B32A32_SFLOAT;  return .RGBA32Float;
        case .B10G11R11_UFLOAT_PACK32; return .RG11B10Float;
        case .E5B9G9R9_UFLOAT_PACK32;  return .RGB9E5Float;
        case .D16_UNORM;            return .Depth16Unorm;
        case .D32_SFLOAT;           return .Depth32Float;
        case .S8_UINT;              return .Stencil8;
        case .D24_UNORM_S8_UINT;    return .Depth24Unorm_Stencil8;
        case .D32_SFLOAT_S8_UINT;   return .Depth32Float_Stencil8;
        case .BC1_RGB_UNORM_BLOCK;  return .BC1_RGBA;
        case .BC1_RGB_SRGB_BLOCK;   return .BC1_RGBA_sRGB;
        case .BC1_RGBA_UNORM_BLOCK; return .BC1_RGBA;
        case .BC1_RGBA_SRGB_BLOCK;  return .BC1_RGBA_sRGB;
        case .BC2_UNORM_BLOCK;      return .BC2_RGBA;
        case .BC2_SRGB_BLOCK;       return .BC2_RGBA_sRGB;
        case .BC3_UNORM_BLOCK;      return .BC3_RGBA;
        case .BC3_SRGB_BLOCK;       return .BC3_RGBA_sRGB;
        case .BC4_UNORM_BLOCK;      return .BC4_RUnorm;
        case .BC4_SNORM_BLOCK;      return .BC4_RSnorm;
        case .BC5_UNORM_BLOCK;      return .BC5_RGUnorm;
        case .BC5_SNORM_BLOCK;      return .BC5_RGSnorm;
        case .BC6H_UFLOAT_BLOCK;    return .BC6H_RGBUfloat;
        case .BC6H_SFLOAT_BLOCK;    return .BC6H_RGBFloat;
        case .BC7_UNORM_BLOCK;      return .BC7_RGBAUnorm;
        case .BC7_SRGB_BLOCK;       return .BC7_RGBAUnorm_sRGB;
    }
    return .Invalid;
}

mtl_to_format :: (mtl_format: MTLPixelFormat) -> Format {
    if mtl_format == {
        case .Invalid;              return .UNDEFINED;
        case .R8Unorm;              return .R8_UNORM;
        case .R8Snorm;              return .R8_SNORM;
        case .R8Uint;               return .R8_UINT;
        case .R8Sint;               return .R8_SINT;
        case .R16Unorm;             return .R16_UNORM;
        case .R16Snorm;             return .R16_SNORM;
        case .R16Uint;              return .R16_UINT;
        case .R16Sint;              return .R16_SINT;
        case .R16Float;             return .R16_SFLOAT;
        case .RG8Unorm;             return .R8G8_UNORM;
        case .RG8Snorm;             return .R8G8_SNORM;
        case .RG8Uint;              return .R8G8_UINT;
        case .RG8Sint;              return .R8G8_SINT;
        case .R32Uint;              return .R32_UINT;
        case .R32Sint;              return .R32_SINT;
        case .R32Float;             return .R32_SFLOAT;
        case .RG16Unorm;            return .R16G16_UNORM;
        case .RG16Snorm;            return .R16G16_SNORM;
        case .RG16Uint;             return .R16G16_UINT;
        case .RG16Sint;             return .R16G16_SINT;
        case .RG16Float;            return .R16G16_SFLOAT;
        case .RGBA8Unorm;           return .R8G8B8A8_UNORM;
        case .RGBA8Snorm;           return .R8G8B8A8_SNORM;
        case .RGBA8Uint;            return .R8G8B8A8_UINT;
        case .RGBA8Sint;            return .R8G8B8A8_SINT;
        case .RGBA8Unorm_sRGB;      return .R8G8B8A8_SRGB;
        case .BGRA8Unorm;           return .B8G8R8A8_UNORM;
        case .BGRA8Unorm_sRGB;      return .B8G8R8A8_SRGB;
        case .RGB10A2Unorm;         return .A2R10G10B10_UNORM_PACK32;
        case .RGB10A2Uint;          return .A2R10G10B10_UINT_PACK32;
        case .RG32Uint;             return .R32G32_UINT;
        case .RG32Sint;             return .R32G32_SINT;
        case .RG32Float;            return .R32G32_SFLOAT;
        case .RGBA16Unorm;          return .R16G16B16A16_UNORM;
        case .RGBA16Snorm;          return .R16G16B16A16_SNORM;
        case .RGBA16Uint;           return .R16G16B16A16_UINT;
        case .RGBA16Sint;           return .R16G16B16A16_SINT;
        case .RGBA16Float;          return .R16G16B16A16_SFLOAT;
        case .RGBA32Uint;           return .R32G32B32A32_UINT;
        case .RGBA32Sint;           return .R32G32B32A32_SINT;
        case .RGBA32Float;          return .R32G32B32A32_SFLOAT;
        case .RG11B10Float;         return .B10G11R11_UFLOAT_PACK32;
        case .RGB9E5Float;          return .E5B9G9R9_UFLOAT_PACK32;
        case .Depth16Unorm;         return .D16_UNORM;
        case .Depth32Float;         return .D32_SFLOAT;
        case .Stencil8;             return .S8_UINT;
        case .Depth24Unorm_Stencil8; return .D24_UNORM_S8_UINT;
        case .Depth32Float_Stencil8; return .D32_SFLOAT_S8_UINT;
    }
    return .UNDEFINED;
}
