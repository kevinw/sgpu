#import "macOS";

CoreGraphics :: #library,system "CoreGraphics";
CoreFoundation :: #library,system "CoreFoundation";
ImageIO :: #library,system "ImageIO";

CGWindowListCreateImage :: (screenBounds: NSRect, listOption: CGWindowListOption, windowID: CGWindowID, imageOption: CGWindowImageOption) -> CGImageRef #foreign CoreGraphics;
CGImageGetWidth :: (image: CGImageRef) -> u64 #foreign CoreGraphics;
CGImageGetHeight :: (image: CGImageRef) -> u64 #foreign CoreGraphics;
CGImageGetBytesPerRow :: (image: CGImageRef) -> u64 #foreign CoreGraphics;
CGImageGetDataProvider :: (image: CGImageRef) -> CGDataProviderRef #foreign CoreGraphics;
CGImageDestinationCreateWithURL :: (url: CFURLRef, type: CFStringRef, count: u32, options: *void) -> CGImageDestinationRef #foreign ImageIO;
CGImageDestinationAddImage :: (destination: CGImageDestinationRef, image: CGImageRef, properties: *void) #foreign ImageIO;
CGImageDestinationFinalize :: (destination: CGImageDestinationRef) -> BOOL #foreign ImageIO;
// CGWindowLevel :: #type,distinct s32;
CGWindowID :: #type,distinct u32;
CGImageRef :: *void;
CFURLRef :: #type *void;
CFStringRef :: #type *void;
CGImageDestinationRef :: #type *void;
CGDataProviderRef :: #type *void;
CFDataRef :: #type *void;
CGDataProviderCopyData :: (provider: CGDataProviderRef) -> CFDataRef #foreign CoreGraphics;
CFDataGetBytePtr :: (data: CFDataRef) -> *u8 #foreign CoreFoundation;
CFDataGetLength :: (data: CFDataRef) -> s64 #foreign CoreFoundation;
CFNumberType :: enum u32 {
    kCFNumberFloatType :: 12;
}
CFNumberRef :: #type *void;
CFNumberCreate :: (allocator: *void, type: CFNumberType, value: *void) -> CFNumberRef #foreign CoreFoundation;
CFRelease :: (cf: *void) #foreign CoreFoundation;

CGWindowListOption :: enum u32 {
    All	:: 0;
    OnScreenOnly :: 1;
    OnScreenAboveWindow :: 2;
    OnScreenBelowWindow :: 4;
    IncludingWindow :: 8;
    ExcludeDesktopElements :: 16;
}

CGWindowImageOption :: enum u32 {
    Default :: 0;
    BoundsIgnoreFraming :: 1;
    ShouldBeOpaque :: 2;
    OnlyShadows :: 4;
    BestResolution :: 8;
    NominalResolution :: 16;
}

gpu_dump_to_bitmap :: (filename: string) {
    window := cast(*NSWindow) native_window_handle;
    img := CGWindowListCreateImage(.{}, .IncludingWindow, windowNumber(window), .BestResolution | .BoundsIgnoreFraming);
    assert(img != null);
    defer CFRelease(img);

    props := CreateJPEGProperties(0.9);
    defer CFRelease(props);

    url := NSURL.fileURLWithPath(to_temp_nsstring(filename));

    dest := CGImageDestinationCreateWithURL(url, temp_cfstring("public.jpeg"), 1, null);
    defer CFRelease(dest);
    CGImageDestinationAddImage(dest, img, props);
    CGImageDestinationFinalize(dest);
}

gpu_validate_window_readback_non_black :: () -> bool {
    window := cast(*NSWindow) native_window_handle;
    img := CGWindowListCreateImage(.{}, .IncludingWindow, windowNumber(window), .BestResolution | .BoundsIgnoreFraming);
    if img == null return false;
    defer CFRelease(img);

    provider := CGImageGetDataProvider(img);
    if provider == null return false;
    data := CGDataProviderCopyData(provider);
    if data == null return false;
    defer CFRelease(data);

    bytes := CFDataGetBytePtr(data);
    if bytes == null return false;
    data_len := CFDataGetLength(data);
    width := cast(s64) CGImageGetWidth(img);
    height := cast(s64) CGImageGetHeight(img);
    bytes_per_row := cast(s64) CGImageGetBytesPerRow(img);
    if width <= 1 || height <= 1 return false;
    if bytes_per_row < width * 4 return false;
    if data_len < bytes_per_row * height return false;

    Sample_Point :: struct { x, y: float; }
    sample_points: [5] Sample_Point;
    sample_points[0] = .{0.5, 0.5};
    sample_points[1] = .{0.25, 0.25};
    sample_points[2] = .{0.75, 0.25};
    sample_points[3] = .{0.25, 0.75};
    sample_points[4] = .{0.75, 0.75};

    non_black := 0;
    min_luma: float = 999.0;
    max_luma: float = -1.0;
    sum_luma: float = 0.0;
    for sample_points {
        px := clamp(cast(s64) floor(it.x * cast(float) width), 0, width - 1);
        py := clamp(cast(s64) floor(it.y * cast(float) height), 0, height - 1);
        offset := py * bytes_per_row + px * 4;
        p := bytes + offset;
        b := cast(float) p[0] / 255.0;
        g := cast(float) p[1] / 255.0;
        r := cast(float) p[2] / 255.0;
        luma := 0.2126 * r + 0.7152 * g + 0.0722 * b;
        if luma > 0.02 non_black += 1;
        min_luma = min(min_luma, luma);
        max_luma = max(max_luma, luma);
        sum_luma += luma;
    }
    avg_luma := sum_luma / cast(float) sample_points.count;
    log("READBACK_SUMMARY backend=rd_metal samples=% non_black=% avg_luma=% min_luma=% max_luma=%",
        sample_points.count, non_black, avg_luma, min_luma, max_luma);

    ok := (non_black >= 2) && (max_luma > 0.05) && ((max_luma - min_luma) > 0.02);
    if !ok log_error("READBACK_FAIL backend=rd_metal");
    return ok;
}

temp_cfstring :: (s: string) -> CFStringRef #expand {
    cfstr := CFStringCreateWithBytes(null, s.data, s.count, .UTF8, false);
    `defer CFRelease(cfstr);
    return cfstr;
}

temp_cfnumber :: (f: float) -> CFNumberRef #expand {
    q := CFNumberCreate(null, .kCFNumberFloatType, *f);
    `defer CFRelease(q);
    return q;
}

CreateJPEGProperties :: (quality: float) -> CFNumberRef {
    keys   := (*void).[ temp_cfstring("kCGImageDestinationLossyCompressionQuality") ];
    values := (*void).[ temp_cfnumber(quality) ];
    dict   := CFDictionaryCreate(null, keys.data, values.data, 1, *kCFTypeDictionaryKeyCallBacks, *kCFTypeDictionaryValueCallBacks);
    return dict; // caller must CFRelease
}

windowNumber :: (window: *NSWindow) -> CGWindowID {
    func: (*void, Selector) -> CGWindowID #c_call;
    func = xx objc_msgSend;
    return func(window, sel_registerName("windowNumber"));
}
