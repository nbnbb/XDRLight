// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 nbnbb. Third-party notices: THIRD_PARTY.md.
#import <Cocoa/Cocoa.h>
#import <MetalKit/MetalKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dlfcn.h>
#import <signal.h>
#import <sys/file.h>
#import <fcntl.h>
#import <unistd.h>
#import <math.h>
#import "Temperature.h"
#import "OnlineUpdater.h"
#import "ControlPanel.h"
#import <ServiceManagement/ServiceManagement.h>

// HDR trigger + gamma technique informed by BrightIntosh (GPL-3.0).
// Calibration distinguishes 500-nit and 600-nit SDR XDR panel generations.
typedef int (*BrightnessGet)(CGDirectDisplayID, float *);
typedef int (*BrightnessSet)(CGDirectDisplayID, float);
static int exitStatus = 0;
static BrightnessGet getBrightness;
static BrightnessSet setBrightness;
static void loadBrightness(void) {
    void *lib = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY);
    if (lib) { getBrightness = dlsym(lib, "DisplayServicesGetBrightness"); setBrightness = dlsym(lib, "DisplayServicesSetBrightness"); }
}
static NSScreen *builtIn(void) {
    for (NSScreen *screen in NSScreen.screens) {
        CGDirectDisplayID did = [screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
        if (CGDisplayIsBuiltin(did)) return screen;
    }
    return nil;
}
// Model table follows BrightIntosh's supported XDR MacBook Pro list (GPL-3.0).
// Newer 600-nit SDR panels (M3 generation onward) use a different reference.
static float XDRRefEDR = 3.2f, XDRMaxBoost = .59f;
static NSString *XDRModelIdentifier(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"));
    if (!service) return nil;
    NSString *model = nil;
    CFTypeRef data = IORegistryEntryCreateCFProperty(service, CFSTR("model"), kCFAllocatorDefault, 0);
    if (data && CFGetTypeID(data) == CFDataGetTypeID()) {
        NSString *text = [[NSString alloc] initWithData:(__bridge NSData *)data encoding:NSUTF8StringEncoding];
        model = [text stringByTrimmingCharactersInSet:NSCharacterSet.controlCharacterSet];
    }
    if (data) CFRelease(data);
    IOObjectRelease(service);
    return model;
}
static NSArray<NSString *> *XDR600NitModels(void) {
    return @[@"Mac15,3", @"Mac15,6", @"Mac15,7", @"Mac15,8", @"Mac15,9", @"Mac15,10", @"Mac15,11", @"Mac16,1", @"Mac16,5", @"Mac16,6", @"Mac16,7", @"Mac16,8", @"Mac17,2", @"Mac17,6", @"Mac17,7", @"Mac17,8", @"Mac17,9"];
}
static BOOL XDRModelSupported(NSString *model) {
    if (!model) return NO;
    NSArray *older = @[@"MacBookPro18,1", @"MacBookPro18,2", @"MacBookPro18,3", @"MacBookPro18,4", @"Mac14,5", @"Mac14,6", @"Mac14,9", @"Mac14,10"];
    return [older containsObject:model] || [XDR600NitModels() containsObject:model];
}
// Native vector companion of the prism app icon. Template rendering adapts
// to macOS light/dark menu bars and remains crisp at Retina scale.
static NSImage *PrismMenuIcon(BOOL active) {
    NSImage *image = [NSImage imageWithSize:NSMakeSize(22, 18) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        (void)rect;
        [NSColor.blackColor set];
        NSBezierPath *prism = [NSBezierPath bezierPath];
        [prism moveToPoint:NSMakePoint(4, 3)];
        [prism lineToPoint:NSMakePoint(10, 15)];
        [prism lineToPoint:NSMakePoint(16, 3)];
        [prism closePath];
        prism.lineWidth = 1.6; prism.lineJoinStyle = NSLineJoinStyleRound;
        if (active) [prism fill]; else [prism stroke];
        NSBezierPath *light = [NSBezierPath bezierPath]; light.lineWidth = 1.5; light.lineCapStyle = NSLineCapStyleRound;
        [light moveToPoint:NSMakePoint(1, 11)]; [light lineToPoint:NSMakePoint(5.4, 9)];
        [light moveToPoint:NSMakePoint(15.3, 9)]; [light lineToPoint:NSMakePoint(21, 11)];
        [light moveToPoint:NSMakePoint(16, 7)]; [light lineToPoint:NSMakePoint(21, 7)];
        [light moveToPoint:NSMakePoint(16.3, 5)]; [light lineToPoint:NSMakePoint(21, 3)];
        [light stroke]; return YES;
    }];
    image.template = YES;
    image.accessibilityDescription = active ? @"XDRLight 棱镜 · 亮度增强开启" : @"XDRLight 棱镜 · 亮度增强关闭";
    return image;
}

@interface HDRView : MTKView <MTKViewDelegate>
@property id<MTLCommandQueue> queue;
@property NSUInteger completedFrames;
@property BOOL failed;
@property NSDate *lastFrameDate;
@end
@implementation HDRView
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame device:MTLCreateSystemDefaultDevice()];
    if (self) {
        _queue = [self.device newCommandQueue];
        self.autoResizeDrawable = NO; self.drawableSize = CGSizeMake(1, 1);
        self.colorPixelFormat = MTLPixelFormatRGBA16Float;
        CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearSRGB);
        self.colorspace = cs; CGColorSpaceRelease(cs);
        ((CAMetalLayer *)self.layer).wantsExtendedDynamicRangeContent = YES;
        self.clearColor = MTLClearColorMake(1.6, 1.6, 1.6, 1);
        self.preferredFramesPerSecond = 5; self.delegate = self;
    }
    return self;
}
- (void)drawInMTKView:(MTKView *)view {
    MTLRenderPassDescriptor *pass = view.currentRenderPassDescriptor;
    id<CAMetalDrawable> drawable = view.currentDrawable;
    if (!pass || !drawable || !_queue) return;
    id<MTLCommandBuffer> buffer = [_queue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:pass];
    if (!encoder) { self.failed = YES; return; }
    [encoder endEncoding]; [buffer presentDrawable:drawable];
    __weak HDRView *weakSelf = self;
    [buffer addCompletedHandler:^(id<MTLCommandBuffer> b) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (b.status == MTLCommandBufferStatusCompleted) { weakSelf.completedFrames++; weakSelf.lastFrameDate = NSDate.date; }
            else weakSelf.failed = YES;
        });
    }];
    [buffer commit];
}
- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {}
@end

@interface Controller : NSObject <NSApplicationDelegate, NSMenuDelegate> {
    CGGammaValue red[256], green[256], blue[256];
    uint32_t count;
    CGDirectDisplayID display;
    float originalBrightness;
    BOOL savedBrightness;
    BOOL savedGamma;
    float lastGain;
    NSUInteger gammaRecoveries;
    NSUInteger gammaConflicts;
    NSDate *lastGammaRecovery;
}
@property NSStatusItem *item;
@property ControlPanel *panel;
@property NSMenuItem *strengthSliderItem;
@property NSTextField *strengthMenuValue;
@property BOOL wantsBoost;
@property BOOL sleeping;
@property NSDate *sleepObservedAt;
@property BOOL sessionInactive;
@property BOOL recoveryBlocked;
@property BOOL diagnostic;
@property float targetBacklight;
@property NSDate *resumeNotBefore;
@property NSWindow *trigger;
@property HDRView *hdr;
@property NSTimer *timer;
@property BOOL enabled;
@property CGFloat strength;
@property NSDate *started;
@property NSString *status;
@property NSMutableArray *signals;
@property OnlineUpdater *onlineUpdater;
@property TemperatureReader *temperatureReader;
@property NSTimer *monitorTimer;
@property NSMenuItem *screenTemperatureItem;
@property NSMenuItem *batteryTemperatureItem;
@property NSMenuItem *thermalItem;
@property NSMenuItem *edrItem;
@property NSMenuItem *refreshItem;
@property NSMenuItem *summaryItem;
@property NSTextField *headerStatus;
@property NSSwitch *headerSwitch;
@property NSTextField *backlightMenuValue;
@property double screenTemperature;
@property double batteryTemperature;
@property NSDateFormatter *timeFormatter;
- (BOOL)enableBoost;
- (void)disableBoost;
@end
@implementation Controller
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    [NSDistributedNotificationCenter.defaultCenter addObserver:self selector:@selector(showPanel:) name:@"local.xdrlight.ShowPanel" object:nil];
    loadBrightness();
    NSString *model = XDRModelIdentifier();
    if ([XDR600NitModels() containsObject:model]) { XDRRefEDR = 2.66f; XDRMaxBoost = .50f; }
    self.temperatureReader = [TemperatureReader new];
    self.screenTemperature = NAN; self.batteryTemperature = NAN;
    self.timeFormatter = [NSDateFormatter new]; self.timeFormatter.dateFormat = @"HH:mm:ss";
    self.diagnostic = [NSProcessInfo.processInfo.arguments containsObject:@"--probe"] || [NSProcessInfo.processInfo.arguments containsObject:@"--restore"] || [NSProcessInfo.processInfo.arguments containsObject:@"--panel-preview"] || [NSProcessInfo.processInfo.arguments containsObject:@"--self-test"] || [NSProcessInfo.processInfo.arguments containsObject:@"--soak-test"] || [NSProcessInfo.processInfo.arguments containsObject:@"--menu-health"] || [NSProcessInfo.processInfo.arguments containsObject:@"--recovery-test"] || [NSProcessInfo.processInfo.arguments containsObject:@"--render-stall-test"] || [NSProcessInfo.processInfo.arguments containsObject:@"--exit-code-test"] || [NSProcessInfo.processInfo.arguments containsObject:@"--conflict-test"];
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--exit-code-test"]) { exitStatus=7; [NSApp terminate:nil]; return; }
    NSUserDefaults *prefs = NSUserDefaults.standardUserDefaults;
    self.strength = !self.diagnostic && [prefs objectForKey:@"BoostStrength"] ? fmin(1,fmax(0,[prefs doubleForKey:@"BoostStrength"])) : 1;
    self.targetBacklight = !self.diagnostic && [prefs objectForKey:@"TargetBacklight"] ? fmin(1,fmax(.05,[prefs floatForKey:@"TargetBacklight"])) : 1;
    self.wantsBoost = !self.diagnostic && ([prefs objectForKey:@"KeepBoost"] ? [prefs boolForKey:@"KeepBoost"] : YES);
    self.status = self.wantsBoost ? @"正在准备持续增强" : @"已关闭";
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--restore"]) {
        CGDisplayRestoreColorSyncSettings(); printf("ColorSync restored\n"); [NSApp terminate:nil]; return;
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--probe"]) {
        NSScreen *s = builtIn();
        printf("Built-in: %s; current EDR: %.3f; potential EDR: %.3f\n", s.localizedName.UTF8String ?: "none", s.maximumExtendedDynamicRangeColorComponentValue, s.maximumPotentialExtendedDynamicRangeColorComponentValue);
        [self printMonitor];
        [NSApp terminate:nil]; return;
    }
    if (!self.diagnostic && !XDRModelSupported(model) && ![prefs boolForKey:@"AllowUnsupportedModel"]) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"这台 Mac 可能不支持 XDRLight";
        alert.informativeText = [NSString stringWithFormat:@"XDRLight 只适用于带内置 Liquid Retina XDR 屏幕的 14 / 16 英寸 MacBook Pro（M1 Pro / M1 Max 及更新机型）。\n\n这台 Mac 的型号是 %@，不在已支持列表中。MacBook Air、13 英寸 MacBook Pro、iMac、Mac mini 等没有 XDR 屏幕，无法增强亮度。", model ?: @"未知"];
        [alert addButtonWithTitle:@"退出"]; [alert addButtonWithTitle:@"仍要尝试"];
        [NSApp activateIgnoringOtherApps:YES];
        if ([alert runModal] == NSAlertFirstButtonReturn) { [NSApp terminate:nil]; return; }
        [prefs setBool:YES forKey:@"AllowUnsupportedModel"];
    }
    if (!self.diagnostic) self.onlineUpdater = [OnlineUpdater new];
    [NSUserDefaults.standardUserDefaults registerDefaults:@{@"NSStatusItem Preferred Position XDRLightPrismMenuBar": @220}];
    self.item = [NSStatusBar.systemStatusBar statusItemWithLength:28];
    self.item.autosaveName = @"XDRLightPrismMenuBar";
    self.item.visible = !self.diagnostic || [NSProcessInfo.processInfo.arguments containsObject:@"--panel-preview"] || [NSProcessInfo.processInfo.arguments containsObject:@"--menu-health"];
    self.item.button.image = PrismMenuIcon(NO);
    NSMenu *menu = [NSMenu new]; menu.delegate = self; self.item.menu = menu;
    [self updateMenu];
    [self refreshMonitor:nil];
    self.monitorTimer = [NSTimer timerWithTimeInterval:2 target:self selector:@selector(refreshMonitor:) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.monitorTimer forMode:NSRunLoopCommonModes];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshMonitor:) name:NSProcessInfoThermalStateDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(displayChanged:) name:NSApplicationDidChangeScreenParametersNotification object:nil];
    NSNotificationCenter *workspace = NSWorkspace.sharedWorkspace.notificationCenter;
    [workspace addObserver:self selector:@selector(displayChanged:) name:NSWorkspaceWillSleepNotification object:nil];
    [workspace addObserver:self selector:@selector(displayChanged:) name:NSWorkspaceScreensDidSleepNotification object:nil];
    [workspace addObserver:self selector:@selector(displayChanged:) name:NSWorkspaceSessionDidResignActiveNotification object:nil];
    for (NSString *name in @[NSWorkspaceDidWakeNotification, NSWorkspaceScreensDidWakeNotification, NSWorkspaceSessionDidBecomeActiveNotification])
        [workspace addObserver:self selector:@selector(resumeAfterSystem:) name:name object:nil];
    self.signals = [NSMutableArray new];
    for (NSNumber *number in @[@(SIGTERM), @(SIGINT), @(SIGHUP)]) {
        int sig = number.intValue; signal(sig, SIG_IGN);
        dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, sig, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(source, ^{ [NSApp terminate:nil]; });
        dispatch_resume(source); [self.signals addObject:source];
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--recovery-test"]) {
        self.wantsBoost=YES; [self enableBoost];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            [self displayChanged:[NSNotification notificationWithName:NSWorkspaceScreensDidSleepNotification object:nil]];
            BOOL suspended=self.wantsBoost && !self.enabled && self.sleeping;
            [self resumeAfterSystem:[NSNotification notificationWithName:NSWorkspaceScreensDidWakeNotification object:nil]];
            self.resumeNotBefore=nil; [self refreshMonitor:nil];
            BOOL resumed=self.enabled && self.wantsBoost && !self.sleeping;
            [self enforceThermalState:NSProcessInfoThermalStateSerious];
            BOOL cooled=self.wantsBoost && !self.enabled && self.resumeNotBefore!=nil;
            self.resumeNotBefore=nil; [self refreshMonitor:nil];
            BOOL thermalResumed=self.enabled;
            [self stopKeeping:nil]; BOOL stopped=!self.wantsBoost && !self.enabled;
            printf("SleepSuspended=%d WakeResumed=%d ThermalSuspended=%d ThermalResumed=%d ManualStop=%d\n",suspended,resumed,cooled,thermalResumed,stopped);
            exitStatus=suspended&&resumed&&cooled&&thermalResumed&&stopped?0:1; [NSApp terminate:nil];
        });
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--menu-health"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            printf("MenuVisible=%d WindowVisible=%d Frame=%s IconSize=%s\n", self.item.visible, self.item.button.window.visible, NSStringFromRect(self.item.button.window.frame).UTF8String, NSStringFromSize(self.item.button.image.size).UTF8String);
            NSScreen *s = builtIn(); printf("RightMenuArea=%s\n", NSStringFromRect(s.auxiliaryTopRightArea).UTF8String);
            [NSApp terminate:nil];
        });
    }
    if (!self.diagnostic) {
        // Only greet with the panel on first launch; login-item launches stay quiet.
        if (![prefs boolForKey:@"PanelShownOnce"]) { [self showPanel:nil]; [prefs setBool:YES forKey:@"PanelShownOnce"]; }
        [self savePreferences];
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--panel-preview"]) [self showPanel:nil];
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--enable"]) { [self enableBoost]; [self updateMenu]; }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--soak-test"]) {
        self.wantsBoost=YES;
        BOOL ok = [self enableBoost];
        __block NSUInteger samples = 0; __block BOOL sustained = ok;
        NSTimer *soak = [NSTimer timerWithTimeInterval:5 repeats:YES block:^(NSTimer *t) {
            samples++;
            CGGammaValue r[256], g[256], b[256]; uint32_t n = 0;
            CGError result = CGGetDisplayTransferByTable(display, 256, r, g, b, &n);
            BOOL applied = result == kCGErrorSuccess && n == count && lastGain > 1;
            for (uint32_t i = 0; applied && i < n; i++) applied = fabsf(r[i]-red[i]*lastGain)<.003 && fabsf(g[i]-green[i]*lastGain)<.003 && fabsf(b[i]-blue[i]*lastGain)<.003;
            float brightness = NAN; if (getBrightness) getBrightness(display, &brightness);
            printf("t=%lus enabled=%d EDR=%.3f gain=%.3f gammaOK=%d frames=%lu backlight=%.3f thermal=%ld recoveries=%lu status=%s\n", (unsigned long)samples*5, self.enabled, builtIn().maximumExtendedDynamicRangeColorComponentValue, lastGain, applied, (unsigned long)self.hdr.completedFrames, brightness, (long)NSProcessInfo.processInfo.thermalState, (unsigned long)gammaRecoveries, self.status.UTF8String);
            fflush(stdout); sustained = sustained && self.enabled && applied;
            if (samples == 7) { self.strength=.25; [self tick:nil]; }
            if (samples == 11) { self.strength=.75; [self tick:nil]; }
            if (samples == 15) { self.strength=1; [self tick:nil]; }
            if (samples == 4) { CGDisplayRestoreColorSyncSettings(); printf("Injected one-time ColorSync reset\n"); fflush(stdout); }
            if (samples == 60) {
                BOOL recovered = gammaRecoveries > 0;
                [self disableBoost];
                result = CGGetDisplayTransferByTable(display, 256, r, g, b, &n);
                BOOL restored = result == kCGErrorSuccess && n == count;
                for (uint32_t i=0; restored && i<n; i++) restored = fabsf(r[i]-red[i])<.001 && fabsf(g[i]-green[i])<.001 && fabsf(b[i]-blue[i])<.001;
                printf("Sustained300Seconds=%d InjectedResetRecovered=%d GammaRestored=%d\n", sustained, recovered, restored); fflush(stdout);
                exitStatus = sustained && recovered && restored ? 0 : 1;
                [t invalidate]; [NSApp terminate:nil];
            }
        }];
        [NSRunLoop.mainRunLoop addTimer:soak forMode:NSRunLoopCommonModes];
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--conflict-test"]) {
        NSScreen *screen=builtIn();
        CGDirectDisplayID did=[screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
        static CGGammaValue baseR[256],baseG[256],baseB[256];
        static uint32_t baseCount=0;
        if (!screen || CGGetDisplayTransferByTable(did,256,baseR,baseG,baseB,&baseCount)!=kCGErrorSuccess || !baseCount) { exitStatus=1; [NSApp terminate:nil]; return; }
        CGGammaValue elevatedR[256],elevatedG[256],elevatedB[256];
        for (uint32_t i=0;i<baseCount;i++) { elevatedR[i]=baseR[i]*1.2; elevatedG[i]=baseG[i]*1.2; elevatedB[i]=baseB[i]*1.2; }
        BOOL injected=CGSetDisplayTransferByTable(did,baseCount,elevatedR,elevatedG,elevatedB)==kCGErrorSuccess;
        BOOL rejected=injected && ![self enableBoost] && !self.enabled && self.recoveryBlocked;
        CGSetDisplayTransferByTable(did,baseCount,baseR,baseG,baseB);
        self.recoveryBlocked=NO; self.wantsBoost=YES;
        BOOL started=[self enableBoost];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,4*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            BOOL rendered=self.hdr.completedFrames>0;
            CGGammaValue externalR[256],externalG[256],externalB[256],actualR[256],actualG[256],actualB[256]; uint32_t n=0;
            for (uint32_t i=0;i<baseCount;i++) { externalR[i]=baseR[i]*.80; externalG[i]=baseG[i]*.85; externalB[i]=baseB[i]*.90; }
            BOOL changed=CGSetDisplayTransferByTable(did,baseCount,externalR,externalG,externalB)==kCGErrorSuccess;
            [self tick:nil];
            BOOL paused=changed && !self.enabled && self.recoveryBlocked;
            BOOL preserved=CGGetDisplayTransferByTable(did,256,actualR,actualG,actualB,&n)==kCGErrorSuccess && n==baseCount;
            for (uint32_t i=0;preserved && i<n;i++) preserved=fabsf(actualR[i]-externalR[i])<.003 && fabsf(actualG[i]-externalG[i])<.003 && fabsf(actualB[i]-externalB[i])<.003;
            // This test owns the injected curve and restores its original snapshot.
            CGSetDisplayTransferByTable(did,baseCount,baseR,baseG,baseB);
            printf("ElevatedBaselineRejected=%d ForeignCurvePaused=%d ForeignCurvePreserved=%d\n",rejected,paused,preserved);
            exitStatus=rejected&&started&&rendered&&paused&&preserved?0:1; [NSApp terminate:nil];
        });
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--render-stall-test"]) {
        BOOL startedOK=[self enableBoost];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,4*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            BOOL rendered=self.hdr.completedFrames>0;
            self.hdr.paused=YES;
            self.hdr.lastFrameDate=[NSDate dateWithTimeIntervalSinceNow:-10];
            self.wantsBoost=YES;
            [self tick:nil];
            BOOL stopped=!self.enabled && self.recoveryBlocked && !self.trigger && !savedGamma && !savedBrightness;
            [self refreshMonitor:nil];
            BOOL stayedStopped=!self.enabled;
            printf("RenderedBeforeStall=%d StalledRendererStopped=%d RecoveryBlocked=%d\n", rendered, stopped, stayedStopped);
            exitStatus=startedOK&&rendered&&stopped&&stayedStopped?0:1;
            [NSApp terminate:nil];
        });
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--self-test"]) {
        BOOL ok = [self enableBoost];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            CGFloat edr = builtIn().maximumExtendedDynamicRangeColorComponentValue;
            NSUInteger frames = self.hdr.completedFrames;
            CGGammaValue r[256], g[256], b[256]; uint32_t n = 0;
            CGError query = CGGetDisplayTransferByTable(display, 256, r, g, b, &n);
            float expected = red[count ? count - 1 : 0] * lastGain;
            BOOL applied = query == kCGErrorSuccess && n == count && fabsf(r[n ? n-1 : 0] - expected) < .01;
            printf("Enabled=%d HDRFrames=%lu EDR=%.3f Gain=%.3f GammaApplied=%d\n", ok && self.enabled, (unsigned long)frames, edr, lastGain, applied);
            BOOL passed = ok && self.enabled && frames > 0 && edr > 1.05 && lastGain > 1 && applied;
            BOOL checkBrightness = savedBrightness;
            [self disableBoost];
            query = CGGetDisplayTransferByTable(display, 256, r, g, b, &n);
            BOOL restored = query == kCGErrorSuccess && n == count;
            for (uint32_t i = 0; restored && i < n; i++) restored = fabsf(r[i]-red[i]) < .001 && fabsf(g[i]-green[i]) < .001 && fabsf(b[i]-blue[i]) < .001;
            float currentBrightness = 0;
            BOOL brightnessRestored = !checkBrightness || (getBrightness(display, &currentBrightness) == 0 && fabsf(currentBrightness-originalBrightness) < .01);
            [self printMonitor];
            printf("GammaRestored=%d BrightnessRestored=%d\n", restored, brightnessRestored); fflush(stdout);
            BOOL reenabled = [self enableBoost];
            [self enforceThermalState:NSProcessInfoThermalStateSerious];
            BOOL protection = reenabled && !self.enabled && !self.trigger && !savedGamma && !savedBrightness;
            BOOL protectionBrightness = !checkBrightness || (getBrightness(display, &currentBrightness) == 0 && fabsf(currentBrightness-originalBrightness) < .01);
            printf("SimulatedSeriousThermalShutdown=%d BrightnessRestored=%d\n", protection, protectionBrightness);
            exitStatus = passed && restored && brightnessRestored && protection && protectionBrightness ? 0 : 1;
            [NSApp terminate:nil];
        });
    }
}
static const CGFloat XDRMenuWidth = 276;
- (NSMenuItem *)addTo:(NSMenu *)menu title:(NSString *)title action:(SEL)action key:(NSString *)key {
    NSMenuItem *entry = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key]; entry.target = self; [menu addItem:entry]; return entry;
}
- (void)add:(NSString *)title action:(SEL)action key:(NSString *)key { [self addTo:self.item.menu title:title action:action key:key]; }
- (NSTextField *)menuLabel:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight secondary:(BOOL)secondary {
    NSTextField *label = [NSTextField labelWithString:text ?: @""];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = secondary ? NSColor.secondaryLabelColor : NSColor.labelColor;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}
// Header row: name + live status on the left, the one on/off switch on the right.
- (void)addHeader {
    CGFloat w = XDRMenuWidth;
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0,0,w,52)]; view.autoresizingMask = NSViewWidthSizable;
    NSTextField *title = [self menuLabel:@"XDRLight 亮度增强" size:13 weight:NSFontWeightSemibold secondary:NO];
    title.frame = NSMakeRect(16,27,w-90,18); [view addSubview:title];
    self.headerStatus = [self menuLabel:@"" size:11 weight:NSFontWeightRegular secondary:YES];
    self.headerStatus.frame = NSMakeRect(16,9,w-90,15); [view addSubview:self.headerStatus];
    NSSwitch *sw = [NSSwitch new]; sw.controlSize = NSControlSizeSmall; sw.target = self; sw.action = @selector(boostSwitched:);
    sw.accessibilityLabel = @"持续增强"; sw.toolTip = @"开启后持续保持高亮度，睡眠唤醒和降温后自动恢复";
    NSSize size = sw.intrinsicContentSize; if (size.width < 10 || size.height < 10) size = NSMakeSize(32,18);
    sw.frame = NSMakeRect(w-16-size.width, round((52-size.height)/2), size.width, size.height); sw.autoresizingMask = NSViewMinXMargin;
    [view addSubview:sw]; self.headerSwitch = sw;
    NSMenuItem *item = [NSMenuItem new]; item.view = view; [self.item.menu addItem:item];
    [self refreshHeader];
}
- (NSTextField *)addSlider:(NSString *)title value:(double)value min:(double)min action:(SEL)action enabled:(BOOL)enabled tip:(NSString *)tip {
    CGFloat w = XDRMenuWidth;
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0,0,w,50)]; view.autoresizingMask = NSViewWidthSizable;
    NSTextField *name = [self menuLabel:title size:13 weight:NSFontWeightRegular secondary:NO];
    name.frame = NSMakeRect(16,27,150,17); if (!enabled) name.textColor = NSColor.tertiaryLabelColor; [view addSubview:name];
    NSTextField *val = [self menuLabel:[NSString stringWithFormat:@"%.0f%%", value*100] size:13 weight:NSFontWeightRegular secondary:YES];
    val.font = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightRegular]; val.alignment = NSTextAlignmentRight;
    val.frame = NSMakeRect(w-16-70,27,70,17); val.autoresizingMask = NSViewMinXMargin; [view addSubview:val];
    NSSlider *slider = [NSSlider sliderWithValue:value minValue:min maxValue:1 target:self action:action];
    slider.frame = NSMakeRect(14,4,w-28,22); slider.autoresizingMask = NSViewWidthSizable; slider.continuous = YES; slider.enabled = enabled;
    slider.accessibilityLabel = title; slider.toolTip = tip; [view addSubview:slider];
    NSMenuItem *item = [NSMenuItem new]; item.view = view; [self.item.menu addItem:item];
    return val;
}
- (void)addHiddenKey:(NSString *)key action:(SEL)action object:(id)object {
    NSMenuItem *entry = [[NSMenuItem alloc] initWithTitle:@"" action:action keyEquivalent:key];
    entry.target = self; entry.representedObject = object; entry.hidden = YES; entry.allowsKeyEquivalentWhenHidden = YES;
    [self.item.menu addItem:entry];
}
- (void)updateMenu {
    NSMenu *menu = self.item.menu; [menu removeAllItems]; menu.minimumWidth = XDRMenuWidth;
    [self addHeader];
    [menu addItem:NSMenuItem.separatorItem];
    self.backlightMenuValue = [self addSlider:@"屏幕亮度" value:self.targetBacklight min:.05 action:@selector(adjustBacklight:) enabled:setBrightness!=NULL
                                          tip:setBrightness ? @"内置屏幕背光" : @"系统亮度接口不可用，请使用亮度键"];
    self.strengthMenuValue = [self addSlider:@"增强强度" value:self.strength min:0 action:@selector(adjustBoost:) enabled:YES
                                         tip:@"菜单打开时按 ⌘1–⌘4 快速切换 25 / 50 / 75 / 100%"];
    [menu addItem:NSMenuItem.separatorItem];
    // Diagnostics live one level down; the top level shows a single summary line.
    NSMenu *details = [NSMenu new];
    self.thermalItem = [self monitorEntryIn:details];
    self.edrItem = [self monitorEntryIn:details];
    self.batteryTemperatureItem = [self monitorEntryIn:details];
    self.screenTemperatureItem = [self monitorEntryIn:details];
    [details addItem:NSMenuItem.separatorItem];
    self.refreshItem = [self monitorEntryIn:details];
    self.summaryItem = [[NSMenuItem alloc] initWithTitle:@"运行状态" action:nil keyEquivalent:@""];
    self.summaryItem.submenu = details; [menu addItem:self.summaryItem];
    NSMenu *more = [NSMenu new];
    SMAppServiceStatus loginStatus=SMAppService.mainAppService.status;
    NSMenuItem *login=[self addTo:more title:loginStatus==SMAppServiceStatusRequiresApproval ? @"登录启动待系统批准…" : @"登录时启动" action:@selector(toggleLogin:) key:@""];
    login.state=loginStatus==SMAppServiceStatusEnabled?NSControlStateValueOn:NSControlStateValueOff;
    [self addTo:more title:@"控制面板…" action:@selector(showPanel:) key:@"l"];
    [more addItem:NSMenuItem.separatorItem];
    // Update entries only appear once a feed exists; hold Option to set one.
    NSString *feed = [NSUserDefaults.standardUserDefaults stringForKey:@"XDRUpdateServiceURL"];
    if (!feed.length) feed = [NSBundle.mainBundle objectForInfoDictionaryKey:@"SUFeedURL"];
    BOOL option = (NSEvent.modifierFlags & NSEventModifierFlagOption) != 0;
    if (feed.length) [self addTo:more title:@"检查更新…" action:@selector(checkUpdates:) key:@""];
    if (option) [self addTo:more title:@"设置更新服务地址…" action:@selector(configureUpdates:) key:@""];
    if (feed.length || option) [more addItem:NSMenuItem.separatorItem];
    [self addTo:more title:@"关于 / 使用说明" action:@selector(about:) key:@""];
    NSMenuItem *moreItem = [[NSMenuItem alloc] initWithTitle:@"设置" action:nil keyEquivalent:@""]; moreItem.submenu = more; [menu addItem:moreItem];
    [menu addItem:NSMenuItem.separatorItem];
    [self add:@"退出并恢复" action:@selector(quit:) key:@"q"];
    [self addHiddenKey:@"b" action:@selector(toggle:) object:nil];
    NSArray *levels = @[@25, @50, @75, @100];
    for (NSUInteger i = 0; i < levels.count; i++) [self addHiddenKey:[NSString stringWithFormat:@"%lu", (unsigned long)i+1] action:@selector(changeStrength:) object:levels[i]];
    [self refreshMonitor:nil];
}
- (NSMenuItem *)monitorEntryIn:(NSMenu *)menu {
    NSMenuItem *entry = [[NSMenuItem alloc] initWithTitle:@"读取中…" action:nil keyEquivalent:@""];
    [menu addItem:entry]; return entry;
}
- (void)refreshHeader {
    self.headerSwitch.state = self.wantsBoost ? NSControlStateValueOn : NSControlStateValueOff;
    NSString *text = self.status ?: @"";
    if (!self.wantsBoost && !self.enabled && [text isEqualToString:@"已关闭"]) text = @"已关闭 · 打开右侧开关开始增强";
    self.headerStatus.stringValue = text; self.headerStatus.toolTip = text;
    self.item.button.image = PrismMenuIcon(self.enabled);
}
- (void)boostSwitched:(NSSwitch *)sender {
    BOOL on = sender.state == NSControlStateValueOn;
    if (on == self.wantsBoost) return;
    self.wantsBoost = on; self.recoveryBlocked = NO; self.resumeNotBefore = nil;
    if (on) [self enableBoost]; else [self disableBoost];
    [self savePreferences]; [self refreshHeader]; [self refreshPanel];
}
- (void)refreshMonitor:(id)sender {
    // Read afresh each time; unavailable values never retain stale temperatures.
    self.screenTemperature = [self.temperatureReader readCelsius:"TL0P"];
    self.batteryTemperature = [self.temperatureReader readCelsius:"TB0T"];
    if (!isfinite(self.batteryTemperature)) self.batteryTemperature = [self.temperatureReader readCelsius:"TB1T"];
    // Hide the screen sensor row entirely when this Mac does not expose it.
    self.screenTemperatureItem.hidden = !isfinite(self.screenTemperature);
    self.screenTemperatureItem.title = isfinite(self.screenTemperature)
        ? [NSString stringWithFormat:@"屏幕传感器 TL0P：%.1f°C（位置未确认）", self.screenTemperature] : @"屏幕温度：不可用";
    self.batteryTemperatureItem.title = isfinite(self.batteryTemperature)
        ? [NSString stringWithFormat:@"电池温度：%.1f°C", self.batteryTemperature] : @"电池温度：暂不可用";
    NSProcessInfoThermalState thermal = NSProcessInfo.processInfo.thermalState;
    self.thermalItem.title = [NSString stringWithFormat:@"整机热状态：%@", ThermalLabel(thermal)];
    NSScreen *screen = builtIn();
    if (self.sleeping && self.sleepObservedAt && -self.sleepObservedAt.timeIntervalSinceNow>3 && screen && !CGDisplayIsAsleep([screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue])) { self.sleeping=NO; self.resumeNotBefore=[NSDate dateWithTimeIntervalSinceNow:3]; }
    self.edrItem.title = screen ? [NSString stringWithFormat:@"实时 HDR 余量：%.2f×", screen.maximumExtendedDynamicRangeColorComponentValue] : @"HDR 余量：没有内置屏幕";
    NSString *summary = [NSString stringWithFormat:@"运行状态：%@", ThermalLabel(thermal)];
    if (isfinite(self.batteryTemperature)) summary = [summary stringByAppendingFormat:@" · 电池 %.1f°C", self.batteryTemperature];
    self.summaryItem.title = summary;
    self.refreshItem.title = [NSString stringWithFormat:@"%@ 更新 · 每 2 秒刷新", [self.timeFormatter stringFromDate:NSDate.date]];
    self.item.button.toolTip = [NSString stringWithFormat:@"%@\n%@\n%@", self.status, self.thermalItem.title, self.screenTemperatureItem.title];
    [self enforceThermalState:thermal];
    if (self.wantsBoost && !self.enabled && !self.sleeping && !self.sessionInactive && !self.recoveryBlocked && thermal < NSProcessInfoThermalStateSerious && (!self.resumeNotBefore || self.resumeNotBefore.timeIntervalSinceNow <= 0)) {
        [self enableBoost];
    }
    [self refreshHeader];
    [self refreshPanel];
}
- (void)enforceThermalState:(NSProcessInfoThermalState)thermal {
    if (thermal >= NSProcessInfoThermalStateSerious && self.wantsBoost) {
        self.resumeNotBefore=[NSDate dateWithTimeIntervalSinceNow:10];
        if (self.enabled) [self disableBoost];
        self.status=@"温度较高，冷却后自动恢复";
    } else if (self.enabled && thermal >= NSProcessInfoThermalStateSerious) {
        [self disableBoost]; self.status=@"整机热状态较高，增强已关闭";
    }
}
- (void)printMonitor {
    [self refreshMonitor:nil];
    printf("DisplaySensorTL0P=%s BatteryC=%.2f ThermalState=%ld (%s)\n",
        isfinite(self.screenTemperature) ? [[NSString stringWithFormat:@"%.2f", self.screenTemperature] UTF8String] : "unavailable",
        self.batteryTemperature, (long)NSProcessInfo.processInfo.thermalState,
        ThermalLabel(NSProcessInfo.processInfo.thermalState).UTF8String);
}
- (void)menuWillOpen:(NSMenu *)menu { [self updateMenu]; }
- (void)toggle:(id)sender {
    self.wantsBoost=!self.wantsBoost; self.recoveryBlocked=NO; self.resumeNotBefore=nil;
    if (self.wantsBoost) [self enableBoost]; else [self disableBoost];
    [self savePreferences]; [self updateMenu]; [self refreshPanel];
}
- (void)changeStrength:(NSMenuItem *)sender { self.strength = [sender.representedObject doubleValue]/100; [self savePreferences]; if (self.enabled) [self tick:nil]; [self updateMenu]; [self refreshPanel]; }
- (void)savePreferences {
    if (self.diagnostic) return;
    [NSUserDefaults.standardUserDefaults setBool:self.wantsBoost forKey:@"KeepBoost"];
    [NSUserDefaults.standardUserDefaults setDouble:self.strength forKey:@"BoostStrength"];
    [NSUserDefaults.standardUserDefaults setFloat:self.targetBacklight forKey:@"TargetBacklight"];
}
- (void)adjustBoost:(NSSlider *)slider {
    self.strength=slider.doubleValue; [self savePreferences];
    if (self.enabled) [self tick:nil];
    self.strengthMenuValue.stringValue=[NSString stringWithFormat:@"%.0f%%", self.strength*100];
    [self refreshHeader]; [self refreshPanel];
}
- (void)adjustBacklight:(NSSlider *)slider {
    self.targetBacklight=slider.floatValue; [self savePreferences];
    NSScreen *s=builtIn(); CGDirectDisplayID did=[s.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
    if (!setBrightness || !s || setBrightness(did,self.targetBacklight)!=0) self.status=@"无法调节背光，请使用系统亮度键";
    self.backlightMenuValue.stringValue=[NSString stringWithFormat:@"%.0f%%", self.targetBacklight*100];
    [self refreshHeader]; [self refreshPanel];
}
- (void)keepChanged:(NSButton *)button {
    self.wantsBoost=button.state==NSControlStateValueOn; self.recoveryBlocked=NO; self.resumeNotBefore=nil;
    if (self.wantsBoost) [self enableBoost]; else [self disableBoost];
    [self savePreferences]; [self updateMenu]; [self refreshPanel];
}
- (void)stopKeeping:(id)sender { self.wantsBoost=NO; self.recoveryBlocked=NO; [self disableBoost]; [self savePreferences]; [self updateMenu]; [self refreshPanel]; }
- (void)showPanel:(id)sender {
    if (self.diagnostic && ![NSProcessInfo.processInfo.arguments containsObject:@"--panel-preview"]) return;
    if (!self.panel) self.panel=[[ControlPanel alloc] initWithOwner:self];
    [self refreshPanel]; [NSApp activateIgnoringOtherApps:YES]; [self.panel showWindow:sender]; [self.panel.window makeKeyAndOrderFront:sender];
}
- (void)refreshPanel {
    if (!self.panel) return;
    self.panel.keepButton.state=self.wantsBoost?NSControlStateValueOn:NSControlStateValueOff;
    self.panel.backlightSlider.floatValue=self.targetBacklight;
    self.panel.backlightSlider.enabled=setBrightness!=NULL;
    self.panel.backlightValue.stringValue=[NSString stringWithFormat:@"%.0f%%",self.targetBacklight*100];
    self.panel.boostSlider.doubleValue=self.strength;
    self.panel.boostValue.stringValue=[NSString stringWithFormat:@"%.0f%%",self.strength*100];
    self.panel.stateLabel.stringValue=self.status ?: @"";
    self.panel.thermalLabel.stringValue=self.thermalItem.title ?: @"";
    self.panel.edrLabel.stringValue=self.edrItem.title ?: @"";
    self.panel.temperatureLabel.stringValue=isfinite(self.batteryTemperature)?[NSString stringWithFormat:@"电池 %.1f°C · 屏幕温度未读取到",self.batteryTemperature]:@"温度传感器暂不可用";
    if (isfinite(self.screenTemperature)) self.panel.temperatureLabel.stringValue=[NSString stringWithFormat:@"电池 %@ · TL0P %.1f°C*",isfinite(self.batteryTemperature)?[NSString stringWithFormat:@"%.1f°C",self.batteryTemperature]:@"不可用",self.screenTemperature];
    self.panel.temperatureLabel.toolTip=@"TL0P 的物理位置未确认，不能当作实测屏幕温度。";
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)visible { [self showPanel:nil]; return YES; }
- (void)resumeAfterSystem:(NSNotification *)note {
    if ([note.name isEqualToString:NSWorkspaceSessionDidBecomeActiveNotification]) self.sessionInactive=NO;
    else self.sleeping=NO;
    self.resumeNotBefore=[NSDate dateWithTimeIntervalSinceNow:3];
    if (self.wantsBoost) self.status=@"等待屏幕就绪，自动恢复增强";
}
- (BOOL)enableBoost {
    if (self.enabled) return YES;
    if (NSProcessInfo.processInfo.thermalState >= NSProcessInfoThermalStateSerious) {
        self.status = @"整机热状态较高，请冷却后再开启"; return NO;
    }
    NSScreen *screen = builtIn();
    if (!screen || screen.maximumPotentialExtendedDynamicRangeColorComponentValue <= 1) { self.status = @"没有可用的内置 XDR 屏幕"; return NO; }
    display = [screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
    if (CGDisplayIsAsleep(display)) { self.sleeping=YES; self.sleepObservedAt=NSDate.date; self.status=@"屏幕休眠中，等待唤醒"; return NO; }
    for (NSRunningApplication *app in NSWorkspace.sharedWorkspace.runningApplications) {
        NSString *name=app.localizedName.lowercaseString;
        if ([@[@"vivid",@"brightintosh",@"lunar",@"f.lux",@"flux",@"betterdisplay"] containsObject:name ?: @""]) {
            self.recoveryBlocked=YES; self.status=[NSString stringWithFormat:@"请先退出 %@，避免亮度或色彩冲突",app.localizedName]; return NO;
        }
    }
    if (CGGetDisplayTransferByTable(display, 256, red, green, blue, &count) != kCGErrorSuccess || !count) { self.status = @"无法读取色彩状态"; return NO; }
    for (uint32_t i=0;i<count;i++) {
        if (!isfinite(red[i]) || !isfinite(green[i]) || !isfinite(blue[i]) || fmaxf(red[i],fmaxf(green[i],blue[i]))>1.02f) {
            self.recoveryBlocked=YES; self.status=@"色彩曲线已有增强或异常，请先退出其他色彩工具"; return NO;
        }
    }
    savedGamma = YES;
    savedBrightness = getBrightness && setBrightness && getBrightness(display, &originalBrightness) == 0;
    if (savedBrightness && setBrightness(display, self.targetBacklight) != 0) savedBrightness = NO;
    NSRect rect = NSMakeRect(NSMinX(screen.frame), NSMaxY(screen.frame)-1, 1, 1);
    self.trigger = [[NSWindow alloc] initWithContentRect:rect styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    self.trigger.releasedWhenClosed = NO; self.trigger.opaque = NO; self.trigger.backgroundColor = NSColor.clearColor;
    self.trigger.ignoresMouseEvents = YES; self.trigger.hasShadow = NO; self.trigger.level = NSScreenSaverWindowLevel;
    self.trigger.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary | NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorIgnoresCycle;
    self.hdr = [[HDRView alloc] initWithFrame:NSMakeRect(0, 0, 1, 1)]; self.trigger.contentView = self.hdr;
    if (!self.hdr.device || !self.hdr.queue) { [self disableBoost]; self.recoveryBlocked=YES; self.status = @"Metal 不可用"; return NO; }
    self.enabled = YES; self.started = NSDate.date; lastGain = 1; gammaRecoveries = 0; gammaConflicts = 0; lastGammaRecovery = nil;
    [self.trigger orderFrontRegardless]; self.status = @"等待 HDR 就绪";
    self.timer = [NSTimer timerWithTimeInterval:1 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes]; return YES;
}
- (void)tick:(id)sender {
    if (!self.enabled) return;
    [self enforceThermalState:NSProcessInfo.processInfo.thermalState];
    if (!self.enabled) return;
    NSScreen *screen = builtIn();
    if (!screen || [screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue] != display || CGDisplayIsAsleep(display)) { self.sleeping=screen && CGDisplayIsAsleep(display); if (self.sleeping) self.sleepObservedAt=NSDate.date; [self disableBoost]; self.status=@"屏幕暂不可用，等待恢复"; [self updateMenu]; return; }
    if (self.wantsBoost && getBrightness && setBrightness) {
        float current=0;
        if (getBrightness(display,&current)==0 && fabsf(current-self.targetBacklight)>.01) setBrightness(display,self.targetBacklight);
    }
    [self.trigger orderFrontRegardless];
    [self.hdr draw];
    CGFloat edr = screen.maximumExtendedDynamicRangeColorComponentValue;
    if (self.hdr.failed || (self.hdr.completedFrames == 0 && -self.started.timeIntervalSinceNow > 8) || (self.hdr.lastFrameDate && -self.hdr.lastFrameDate.timeIntervalSinceNow > 8)) { [self disableBoost]; self.recoveryBlocked=YES; self.status = @"HDR 渲染失败，请重新开启"; [self updateMenu]; return; }
    if (edr <= 1.05) {
        if (lastGain > 1) { CGSetDisplayTransferByTable(display, count, red, green, blue); lastGain = 1; }
        self.status = @"系统暂未提供 HDR 余量，自动等待"; return;
    }
    // BrightIntosh's 500-nit SDR XDR calibration. Headroom is OS-reported,
    // not a physical luminance measurement. Cap gamma to the calibrated range.
    float gain = 1 + XDRMaxBoost * (1 - (fminf(fmaxf(edr, XDRRefEDR), 16)-XDRRefEDR)/(16-XDRRefEDR)) * self.strength;
    BOOL drifted = NO;
    BOOL baselineReset = YES;
    if (lastGain > 1) {
        CGGammaValue currentR[256], currentG[256], currentB[256]; uint32_t currentCount = 0;
        if (CGGetDisplayTransferByTable(display, 256, currentR, currentG, currentB, &currentCount) == kCGErrorSuccess && currentCount == count) {
            for (uint32_t i = 0; i < count; i++) {
                if (fabsf(currentR[i]-red[i])>.003 || fabsf(currentG[i]-green[i])>.003 || fabsf(currentB[i]-blue[i])>.003) baselineReset=NO;
                if (fabsf(currentR[i]-red[i]*lastGain) > .003 || fabsf(currentG[i]-green[i]*lastGain) > .003 || fabsf(currentB[i]-blue[i]*lastGain) > .003) { drifted = YES; }
            }
        }
    }
    if (drifted && !baselineReset) {
        // A new profile or foreign curve owns the current state; do not overwrite it.
        savedGamma=NO; [self disableBoost]; self.recoveryBlocked=YES;
        self.status=@"检测到其他色彩调整，已暂停；退出相关工具后重新开启"; [self updateMenu]; return;
    }
    if (drifted) {
        gammaConflicts = lastGammaRecovery && -lastGammaRecovery.timeIntervalSinceNow < 15 ? gammaConflicts+1 : 1;
        if (gammaConflicts > 3) {
            [self disableBoost]; self.recoveryBlocked=YES; self.status = @"色彩调整持续冲突，请关闭其他色彩工具再开启"; [self updateMenu]; return;
        }
        gammaRecoveries++; lastGammaRecovery = NSDate.date;
    }
    if (fabsf(gain-lastGain) > .002 || drifted) {
        CGGammaValue r[256], g[256], b[256];
        for (uint32_t i = 0; i < count; i++) { r[i] = red[i]*gain; g[i] = green[i]*gain; b[i] = blue[i]*gain; }
        if (CGSetDisplayTransferByTable(display, count, r, g, b) != kCGErrorSuccess) { [self disableBoost]; self.recoveryBlocked=YES; self.status = @"系统拒绝增强，已恢复"; return; }
        lastGain = gain;
    }
    self.status = [NSString stringWithFormat:@"增强 %.0f%% · EDR %.2f", self.strength*100, edr];
}
- (void)disableBoost {
    [self.timer invalidate]; self.timer = nil;
    if (savedGamma && count && display) {
        if (CGSetDisplayTransferByTable(display, count, red, green, blue) != kCGErrorSuccess) CGDisplayRestoreColorSyncSettings();
    }
    savedGamma = NO;
    self.enabled = NO; self.hdr.paused = YES; [self.trigger close]; self.trigger = nil; self.hdr = nil;
    if (savedBrightness) { setBrightness(display, originalBrightness); savedBrightness = NO; }
    self.status = @"已关闭";
}
- (void)displayChanged:(NSNotification *)note {
    if ([note.name isEqualToString:NSWorkspaceSessionDidResignActiveNotification]) self.sessionInactive=YES;
    else if (![note.name isEqualToString:NSApplicationDidChangeScreenParametersNotification]) { self.sleeping=YES; self.sleepObservedAt=NSDate.date; }
    if (!self.enabled) return;
    if ([note.name isEqualToString:NSApplicationDidChangeScreenParametersNotification]) {
        NSScreen *s = builtIn();
        NSRect expected = NSMakeRect(NSMinX(s.frame), NSMaxY(s.frame)-1, 1, 1);
        if (s && [s.deviceDescription[@"NSScreenNumber"] unsignedIntValue] == display) {
            if (!NSEqualRects(expected, self.trigger.frame)) [self.trigger setFrame:expected display:YES];
            [self.trigger orderFrontRegardless]; [self.hdr draw]; return;
        }
    }
    [self disableBoost]; self.status = self.wantsBoost ? @"屏幕暂不可用，就绪后自动恢复" : @"屏幕状态变化，已恢复"; [self updateMenu];
}
- (void)toggleLogin:(id)sender {
    NSError *error=nil; SMAppService *service=SMAppService.mainAppService;
    if (service.status==SMAppServiceStatusRequiresApproval) { [SMAppService openSystemSettingsLoginItems]; return; }
    BOOL ok=service.status==SMAppServiceStatusEnabled ? [service unregisterAndReturnError:&error] : [service registerAndReturnError:&error];
    if (!ok) { NSAlert *a=[NSAlert new]; a.messageText=@"登录启动未能设置"; a.informativeText=error.localizedDescription ?: @"请先把 App 安装到应用程序文件夹。"; [a runModal]; }
    [self updateMenu];
}
- (void)checkUpdates:(id)sender { [self.onlineUpdater check:sender]; }
- (void)configureUpdates:(id)sender { [self.onlineUpdater configure:sender]; }
- (void)about:(id)sender {
    NSAlert *alert = [NSAlert new]; alert.messageText = [NSString stringWithFormat:@"XDRLight %@ · 免费本地工具", [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];
    alert.informativeText = @"适用于 14 / 16 英寸 MacBook Pro（M1 Pro / M1 Max 及更新机型）的内置 XDR 屏幕。开启后调到系统最高亮度，并利用 HDR 余量增强桌面。\n\n100% 是本工具的增强强度，不是实测尼特值。温度、供电和系统会限制亮度。会增加耗电，HDR 视频与色彩校准工作建议关闭增强。\n\n关闭或退出时恢复原来的状态。持续保持会记住你的选择，睡眠唤醒和温度恢复正常后自动尝试恢复增强。若系统亮度接口不可用，请使用系统亮度键。\n\n打开菜单后可按 ⌘B 开关增强，⌘1–⌘4 切换 25/50/75/100% 强度。\n\n“运行状态”子菜单每两秒更新电池温度、整机热状态和 HDR 余量；整机热状态达到较高或严重时自动关闭增强。\n\n技术参考 BrightIntosh，源码随附，GPL-3.0。";
    [NSApp activateIgnoringOtherApps:YES]; [alert runModal];
}
- (void)quit:(id)sender { [NSApp terminate:nil]; }
- (void)applicationWillTerminate:(NSNotification *)note { [self.monitorTimer invalidate]; [self disableBoost]; if (self.diagnostic && exitStatus) exit(exitStatus); }
@end
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        BOOL utility = argc > 1 && (strcmp(argv[1], "--probe") == 0 || strcmp(argv[1], "--restore") == 0);
        if (!utility) {
            NSURL *cache = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
            NSURL *folder = [cache URLByAppendingPathComponent:@"local.xdrlight" isDirectory:YES];
            NSError *error=nil;
            if (![NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:&error]) {
                fprintf(stderr,"Unable to create single-instance lock directory\n"); return 1;
            }
            static int lockFD=-1;
            lockFD=open([[folder URLByAppendingPathComponent:@"instance.lock"] path].fileSystemRepresentation, O_CREAT|O_RDWR, 0600);
            if (lockFD<0) { fprintf(stderr,"Unable to open instance lock\n"); return 1; }
            if (flock(lockFD,LOCK_EX|LOCK_NB)!=0) {
                [NSDistributedNotificationCenter.defaultCenter postNotificationName:@"local.xdrlight.ShowPanel" object:nil userInfo:nil deliverImmediately:YES];
                BOOL testRequested = NO;
                for (int i=1; i<argc; i++) {
                    if (strcmp(argv[i], "--self-test")==0 || strcmp(argv[i], "--soak-test")==0 || strcmp(argv[i], "--recovery-test")==0 || strcmp(argv[i], "--menu-health")==0 || strcmp(argv[i], "--render-stall-test")==0 || strcmp(argv[i], "--exit-code-test")==0 || strcmp(argv[i], "--conflict-test")==0) testRequested=YES;
                }
                fprintf(stderr,"XDRLight already running; %s\n", testRequested ? "test was NOT run; quit the existing app first" : "reused existing instance");
                close(lockFD); return testRequested ? 2 : 0;
            }
        }
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        Controller *controller = [Controller new]; NSApp.delegate = controller; [NSApp run];
    }
    return exitStatus;
}
