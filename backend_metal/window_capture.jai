#import "macOS";

CoreGraphics :: #library,system "CoreGraphics";
CoreFoundation :: #library,system "CoreFoundation";
ImageIO :: #library,system "ImageIO";

CGWindowListCreateImage :: (screenBounds: NSRect, listOption: CGWindowListOption, windowID: CGWindowID, imageOption: CGWindowImageOption) -> CGImageRef #foreign CoreGraphics;
CGImageDestinationCreateWithURL :: (url: CFURLRef, type: CFStringRef, count: u32, options: *void) -> CGImageDestinationRef #foreign ImageIO;
CGImageDestinationAddImage :: (destination: CGImageDestinationRef, image: CGImageRef, properties: *void) #foreign ImageIO;
CGImageDestinationFinalize :: (destination: CGImageDestinationRef) -> BOOL #foreign ImageIO;
// CGWindowLevel :: #type,distinct s32;
CGWindowID :: #type,distinct u32;
CGImageRef :: *void;
CFURLRef :: #type *void;
CFStringRef :: #type *void;
CGImageDestinationRef :: #type *void;
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
