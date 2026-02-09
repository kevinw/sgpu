#scope_export

gpu_create_texture :: (desc: Gpu_Texture_Desc) -> Gpu_Texture {
    // Set usage flags
    mtl_usage: MTLTextureUsage = 0;
    if desc.usage & .SAMPLED mtl_usage |= .ShaderRead;
    if desc.usage & .STORAGE mtl_usage |= .ShaderWrite;
    if desc.usage & .COLOR_ATTACHMENT mtl_usage |= .RenderTarget;
    if desc.usage & .DEPTH_STENCIL_ATTACHMENT mtl_usage |= .RenderTarget;

    mtl_desc := objc_new(MTLTextureDescriptor);
    defer release(mtl_desc);
    {
        using mtl_desc;
        setTextureType(mtl_desc, desc.type.(MTLTextureType));
        setPixelFormat(mtl_desc, format_to_mtl(desc.format));
        setWidth(mtl_desc, desc.dimensions[0].(NSUInteger));
        setHeight(mtl_desc, desc.dimensions[1].(NSUInteger));
        setDepth(mtl_desc, desc.dimensions[2].(NSUInteger));
        setMipmapLevelCount(mtl_desc, desc.mip_count.(NSUInteger));
        setArrayLength(mtl_desc, max(1, desc.layer_count).(NSUInteger));
        setSampleCount(mtl_desc, max(1, desc.sample_count).(NSUInteger));
        setUsage(mtl_desc, mtl_usage);
        setStorageMode(mtl_desc, .Private); // Set storage mode (private for GPU-only textures)
    }

    mtl_texture := MTLDevice.newTextureWithDescriptor(mtl_device, mtl_desc);
    if mtl_texture == null {
        return 0;
    }

    handle := pool_add(*live_textures, {
        desc = desc,
        mtl_texture = mtl_texture,
    });

    return handle;
}

gpu_free :: (texture_handle: Gpu_Texture) {
    removed, texture := pool_remove(*live_textures, texture_handle);
    if removed && texture.mtl_texture != null {
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

    return handle;
}

gpu_free_texture_view :: (view_handle: Gpu_Texture_View) {
    removed, view := pool_remove(*live_texture_views, view_handle);
    if removed {
        // Only release if this is a view we created (not the original texture)
        texture := pool_get(live_textures, view.texture);
        if texture != null && view.mtl_texture != texture.mtl_texture {
            release(view.mtl_texture);
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

live_textures: Pool(Gpu_Texture, Texture, max = MAX_IMAGES);
live_texture_views: Pool(Gpu_Texture_View, Texture_View, max = MAX_IMAGES * 2);

get_texture :: (handle: Gpu_Texture) -> *Texture {
    return pool_get(live_textures, handle);
}

get_texture_view :: (handle: Gpu_Texture_View) -> *Texture_View {
    return pool_get(live_texture_views, handle);
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
