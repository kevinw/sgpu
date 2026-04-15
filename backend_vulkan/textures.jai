#scope_export

gpu_texture_bindless_capacity_2d :: () -> s32 {
    return S32_MAX;
}

gpu_create_texture :: (desc: Gpu_Texture_Desc, optional_signal_texture_ready: [] Gpu_Timeline_Pair = .[]) -> Gpu_Result, Gpu_Texture {
    image_create_info := VkImageCreateInfo.{
        format = desc.format.(VkFormat),
        extent = VkExtent3D.{desc.dimensions[0], desc.dimensions[1], desc.dimensions[2]},
        imageType = desc.type.(VkImageType),
        mipLevels = desc.mip_count,
        arrayLayers = desc.layer_count,
        samples = desc.sample_count.(VkSampleCountFlagBits),
        usage = desc.usage.(VkImageUsageFlagBits),
        sharingMode = .CONCURRENT,
        queueFamilyIndexCount = num_queue_families,
        pQueueFamilyIndices = queue_family_indices.data,
        initialLayout = .UNDEFINED,
    };

    alloc_create_info := VmaAllocationCreateInfo.{
        requiredFlags = .DEVICE_LOCAL_BIT
    };

    image: VkImage;
    alloc: VmaAllocation;

    alloc_info: VmaAllocationInfo;
    vk_result := vmaCreateImage(vma, *image_create_info, *alloc_create_info, *image, *alloc, *alloc_info);
    return_if_error(vk_result, 0);

    handle := pool_add(*live_textures, .{desc = desc, vk_image = image, allocation = alloc});
    if handle == 0 {
        vmaDestroyImage(vma, image, alloc);
        return .ERROR_TEXTURE_LIMIT_EXCEEDED, 0;
    }

    default_view := create_texture_view_handle(handle, default_texture_view_desc(desc));
    if default_view == 0 {
        removed, texture := pool_remove(*live_textures, handle);
        if removed && texture.allocation {
            vmaDestroyImage(vma, texture.vk_image, texture.allocation);
        }
        return .ERROR_TEXTURE_LIMIT_EXCEEDED, 0;
    }

    texture := pool_get(live_textures, handle);
    texture.default_view = default_view;

    transfer_queue := gpu_get_queue(.MAIN, 0);
    result, cmd_buff := gpu_start_command_recording(transfer_queue);
    return_if_error(result, 0);

    vk_cmd_buff := get_cmd_buff(cmd_buff);

    image_barrier := VkImageMemoryBarrier2.{
        image = image,
        srcStageMask = cast(u64) VkPipelineStageFlags.TOP_OF_PIPE_BIT,
        dstStageMask = VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
        subresourceRange = .{
            baseMipLevel = 0,
            baseArrayLayer = 0,
            levelCount = desc.mip_count,
            layerCount = desc.layer_count,
            aspectMask = get_image_aspect_mask(desc.format),
        },
        oldLayout = .UNDEFINED,
        newLayout = .GENERAL,
    };

    dep_info := VkDependencyInfo.{
        imageMemoryBarrierCount = 1,
        pImageMemoryBarriers = *image_barrier,
    };

    vkCmdPipelineBarrier2(vk_cmd_buff, *dep_info);

    gpu_submit(cmd_buff, signals = optional_signal_texture_ready);

    return .SUCCESS, handle;
}

gpu_free :: (texture_handle: Gpu_Texture) {
    found, texture := pool_remove(*live_textures, texture_handle);
    if !found then return;

    for texture.views {
        cleanup_texture_view(it);
    }

    if texture.allocation {
        vmaDestroyImage(vma, texture.vk_image, texture.allocation);
    }
}


gpu_copy_to_texture :: (dest: Gpu_Texture, src: *void, mip: u32 = 0, layer_slice: [2] u32 = .[0, U32_MAX]) {
    texture := get_texture(dest);
    assert(texture != null);

    base_layer := layer_slice[0];
    copy_region := VkMemoryToImageCopy.{
        pHostPointer = src,
        memoryRowLength = 0,
        memoryImageHeight = 0,
        imageSubresource = VkImageSubresourceLayers.{
            aspectMask = get_image_aspect_mask(texture.desc.format),
            mipLevel = mip,
            baseArrayLayer = base_layer,
            layerCount = min(layer_slice[1], texture.desc.layer_count - base_layer),
        },
        imageExtent = VkExtent3D.{texture.desc.dimensions[0], texture.desc.dimensions[1], texture.desc.dimensions[2]}
    };

    copy_info := VkCopyMemoryToImageInfo.{
        dstImage = texture.vk_image,
        dstImageLayout = .GENERAL,
        regionCount = 1,
        pRegions = *copy_region,
    };
    vk_result := vkCopyMemoryToImage(vk_device, *copy_info);
    assert_vk_result(vk_result);
}

gpu_copy_from_texture :: (cmd: Gpu_Command_Buffer, dest: Gpu_Ptr, src: Gpu_Ptr, texture: Gpu_Texture) {

}

gpu_texture_view :: (texture_handle: Gpu_Texture, desc: Gpu_View_Desc = .{}) -> Gpu_Texture_View {
    texture := pool_get(live_textures, texture_handle);
    if !texture then return 0;

    final_desc := normalize_texture_view_desc(texture.desc, desc);
    if is_default_texture_view_desc(texture.desc, final_desc) {
        return texture.default_view;
    }

    return create_texture_view_handle(texture_handle, final_desc);
}

gpu_default_texture_view :: (texture_handle: Gpu_Texture) -> Gpu_Texture_View {
    texture := pool_get(live_textures, texture_handle);
    if !texture return 0;
    return texture.default_view;
}

gpu_texture_view_index :: (view_handle: Gpu_Texture_View) -> u32 {
    return cast(u32) view_handle;
}

gpu_texture_sampled_index :: (texture_handle: Gpu_Texture) -> u32 {
    return cast(u32) gpu_default_texture_view(texture_handle);
}

gpu_black_texture_view :: () -> Gpu_Texture_View {
    return fallback_black_view_handle;
}

create_texture_view_handle :: (texture_handle: Gpu_Texture, final_desc: Gpu_View_Desc) -> Gpu_Texture_View {
    texture := pool_get(live_textures, texture_handle);
    if !texture return 0;

    format := final_desc.format;

    create_info := VkImageViewCreateInfo.{
        image = texture.vk_image,
        viewType = texture.desc.type.(VkImageViewType),
        format = format.(VkFormat),
        subresourceRange = .{
            aspectMask = get_image_aspect_mask(format),
            baseMipLevel = final_desc.base_mip,
            levelCount = min(final_desc.mip_count, texture.desc.mip_count),
            baseArrayLayer = final_desc.base_layer,
            layerCount = min(final_desc.layer_count, texture.desc.layer_count),
        },
    };

    vk_view: VkImageView;
    vk_result := vkCreateImageView(vk_device, *create_info, null, *vk_view);
    assert_vk_result(vk_result);

    handle := pool_add(*live_views, .{final_desc, texture_handle, vk_view});

    if handle == 0 {
        log_error("Exceeded maximum number of texture views (%)!", live_views.max);
        vkDestroyImageView(vk_device, vk_view, null);
        return 0;
    }

    array_add(*texture.views, handle,, cpu_allocator);

    if texture.desc.usage & .SAMPLED != 0 {
        write_texture_descriptor(vk_view, handle);
    }
    if texture.desc.usage & .STORAGE != 0 {
        write_rw_texture_descriptor(vk_view, handle);
    }
    return handle;
}

gpu_texture_desc :: (view_hande: Gpu_Texture_View) -> bool, Gpu_Texture_Desc {
    view := get_texture_view(view_hande);
    if !view {
        return false, .{};
    }
    texture := pool_get(*live_textures, view.texture);
    if !texture {
        return false, .{};
    }
    return true, texture.desc;
}

gpu_texture_view_format :: (view_handle: Gpu_Texture_View) -> (format: Format, ok: bool) {
    view := get_texture_view(view_handle);
    if !view return .UNDEFINED, false;
    if view.desc.format != .UNDEFINED return view.desc.format, true;
    texture := pool_get(*live_textures, view.texture);
    if !texture return .UNDEFINED, false;
    return texture.desc.format, true;
}

gpu_create_sampler :: (desc: Gpu_Sampler_Desc) -> Gpu_Sampler {
    create_info := VkSamplerCreateInfo.{
        minFilter = desc.min_filter.(VkFilter),
        magFilter = desc.mag_filter.(VkFilter),
        mipmapMode = desc.mip_filter.(VkSamplerMipmapMode),
        addressModeU = desc.address_mode_u.(VkSamplerAddressMode),
        addressModeV = desc.address_mode_v.(VkSamplerAddressMode),
        addressModeW = desc.address_mode_w.(VkSamplerAddressMode),
        // MoltenVK does not support mip lod bias.
        mipLodBias = #ifx OS == .MACOS then 0. else desc.mip_lod_bias,
        anisotropyEnable = desc.enable_anisotropy.(VkBool32),
        compareEnable = (desc.compare_op != .NEVER).(VkBool32),
        compareOp = desc.compare_op.(VkCompareOp),
        minLod = desc.min_lod,
        maxLod = desc.max_lod,
        borderColor = desc.border_color.(VkBorderColor),
        unnormalizedCoordinates = desc.unnormalized_coordinates.(VkBool32)
    };

    vk_sampler: VkSampler;
    vk_result := vkCreateSampler(vk_device, *create_info, null, *vk_sampler);
    if vk_result != .SUCCESS {
        return 0;
    }

    handle := pool_add(*live_samplers, vk_sampler);
    if handle == 0 {
        log_error("Exceeded maximum number of texture samplers (%)!", live_samplers.max);
        return 0;
    }

    write_sampler_descriptor(vk_sampler, handle);

    return handle;
}

gpu_free :: (sampler: Gpu_Sampler) {
    removed, sampler := pool_remove(*live_samplers, sampler);
    if removed {
        vkDestroySampler(vk_device, sampler, null);
    }
}

#scope_module

Texture :: struct {
    desc: Gpu_Texture_Desc;
    vk_image: VkImage;
    allocation: VmaAllocation;
    default_view: Gpu_Texture_View;

    // retain a mapping of texture to all known views of that texture
    // so they can be destroyed when the texture is destroyed.
    views: [..] Gpu_Texture_View;
}

Texture_View :: struct {
    desc: Gpu_View_Desc;
    texture: Gpu_Texture;
    vk_view: VkImageView;
}

live_textures: Pool(Gpu_Texture, Texture, max = MAX_IMAGES);
// #todo: readwrite and readonly textures both share the same index space.
// This effectively drops the usable index space by half. Need to split views into separate pools.
live_views: Pool(Gpu_Texture_View, Texture_View, max = MAX_IMAGES);
live_samplers: Pool(Gpu_Sampler, VkSampler,max = MAX_SAMPLERS);
fallback_black_texture: Gpu_Texture;
fallback_black_view_handle: Gpu_Texture_View;
fallback_black_view: Texture_View;

get_image_aspect_mask :: (format: Format) -> VkImageAspectFlags {
    if format == {
        case .D16_UNORM; #through;
        case .X8_D24_UNORM_PACK32; #through;
        case .D32_SFLOAT;
            return .DEPTH_BIT;
        case .S8_UINT;
            return .STENCIL_BIT;
        case .D16_UNORM_S8_UINT; #through;
        case .D24_UNORM_S8_UINT; #through;
        case .D32_SFLOAT_S8_UINT;
            return .DEPTH_BIT | .STENCIL_BIT;
        case;
            return .COLOR_BIT;
    }
}

cleanup_texture_view :: (view_handle: Gpu_Texture_View) {
    removed, view := pool_remove(*live_views, view_handle);
    if removed {
        if view.vk_view != VK_NULL_HANDLE {
            if fallback_black_view.vk_view != VK_NULL_HANDLE {
                write_texture_descriptor(fallback_black_view.vk_view, view_handle);
                write_rw_texture_descriptor(fallback_black_view.vk_view, view_handle);
            }
            vkDestroyImageView(vk_device, view.vk_view, null);
        }
    }
}

get_texture :: (texture_handle: Gpu_Texture) -> *Texture{
    texture := pool_get(live_textures, texture_handle);
    return texture;
}

get_texture_view :: (view_handle: Gpu_Texture_View) -> *Texture_View {
    if view_handle == fallback_black_view_handle {
        if fallback_black_view.vk_view == VK_NULL_HANDLE return null;
        return *fallback_black_view;
    }
    view := pool_get(live_views, view_handle);
    return view;
}

default_texture_view_desc :: (desc: Gpu_Texture_Desc) -> Gpu_View_Desc {
    return .{
        format = desc.format,
        base_mip = 0,
        mip_count = desc.mip_count,
        base_layer = 0,
        layer_count = desc.layer_count,
    };
}

normalize_texture_view_desc :: (texture_desc: Gpu_Texture_Desc, view_desc: Gpu_View_Desc) -> Gpu_View_Desc {
    return .{
        format = ifx view_desc.format != .UNDEFINED then view_desc.format else texture_desc.format,
        base_mip = view_desc.base_mip,
        mip_count = ifx view_desc.mip_count != 0xFF then max(view_desc.mip_count, 1) else texture_desc.mip_count,
        base_layer = view_desc.base_layer,
        layer_count = ifx view_desc.layer_count != 0xFFFF then max(view_desc.layer_count, 1) else texture_desc.layer_count,
    };
}

is_default_texture_view_desc :: (texture_desc: Gpu_Texture_Desc, view_desc: Gpu_View_Desc) -> bool {
    return view_desc.format == texture_desc.format
        && view_desc.base_mip == 0
        && view_desc.mip_count == texture_desc.mip_count
        && view_desc.base_layer == 0
        && view_desc.layer_count == texture_desc.layer_count;
}

init_texture_defaults :: () {
    result, texture := gpu_create_texture(.{
        type = ._2D,
        dimensions = .[1, 1, 1],
        format = .R8G8B8A8_UNORM,
        usage = .SAMPLED | .STORAGE | .TRANSFER_DST,
    });
    assert(result == .SUCCESS, "Failed creating sgpu fallback black texture.");

    fallback_black_texture = texture;
    fallback_black_view_handle = 0;

    texture_info := get_texture(texture);
    assert(texture_info != null);
    default_view := get_texture_view(texture_info.default_view);
    assert(default_view != null);
    fallback_black_view = default_view.*;

    black_pixel := u32.[0x00000000];
    gpu_copy_to_texture(texture, black_pixel.data);
    write_texture_descriptor(default_view.vk_view, fallback_black_view_handle);
    write_rw_texture_descriptor(default_view.vk_view, fallback_black_view_handle);
}

shutdown_texture_defaults :: () {
    if fallback_black_texture != 0 {
        gpu_free(fallback_black_texture);
        fallback_black_texture = 0;
        fallback_black_view = .{};
    }
}
