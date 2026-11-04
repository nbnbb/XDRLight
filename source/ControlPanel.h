#import <Cocoa/Cocoa.h>
@interface ControlPanel : NSWindowController
@property NSSlider *backlightSlider;
@property NSSlider *boostSlider;
@property NSTextField *backlightValue;
@property NSTextField *boostValue;
@property NSTextField *stateLabel;
@property NSTextField *thermalLabel;
@property NSTextField *edrLabel;
@property NSTextField *temperatureLabel;
@property NSButton *keepButton;
@property NSButton *restoreButton;
@property NSButton *detailsButton;
@property NSTextField *backlightTitle;
@property NSTextField *boostTitle;
@property NSTextField *detailsTitle;
- (instancetype)initWithOwner:(id)owner;
@end
@implementation ControlPanel
- (NSTextField *)label:(NSString *)text size:(CGFloat)size {
    NSTextField *v = [NSTextField wrappingLabelWithString:text];
    v.font = [NSFont systemFontOfSize:size];
    [self.window.contentView addSubview:v]; return v;
}
- (void)layoutPanel {
    CGFloat h = self.window.contentView.bounds.size.height;
    self.backlightTitle.frame=NSMakeRect(24,h-44,220,20);
    self.backlightValue.frame=NSMakeRect(260,h-44,76,20);
    self.backlightSlider.frame=NSMakeRect(22,h-72,316,24);
    self.boostTitle.frame=NSMakeRect(24,h-110,220,20);
    self.boostValue.frame=NSMakeRect(260,h-110,76,20);
    self.boostSlider.frame=NSMakeRect(22,h-138,316,24);
    self.keepButton.frame=NSMakeRect(22,h-176,316,24);
    self.stateLabel.frame=NSMakeRect(24,h-222,312,38);
    self.detailsButton.frame=NSMakeRect(20,h-254,18,24);
    self.detailsTitle.frame=NSMakeRect(44,h-252,292,20);
    BOOL expanded=self.detailsButton.state==NSControlStateValueOn;
    NSArray *rows=@[self.thermalLabel,self.edrLabel,self.temperatureLabel];
    for (NSUInteger i=0;i<rows.count;i++) {
        NSTextField *row=rows[i]; row.hidden=!expanded;
        row.frame=NSMakeRect(24,h-282-i*24,312,22);
    }
    self.restoreButton.frame=NSMakeRect(22,18,138,28);
}
- (void)toggleDetails:(id)sender {
    (void)sender;
    NSRect old=self.window.frame;
    CGFloat height=self.detailsButton.state==NSControlStateValueOn?410:324;
    NSRect frame=[self.window frameRectForContentRect:NSMakeRect(0,0,360,height)];
    frame.origin=NSMakePoint(old.origin.x,NSMaxY(old)-frame.size.height);
    [self.window setFrame:frame display:YES];
    [self layoutPanel];
}
- (instancetype)initWithOwner:(id)owner {
    NSWindow *w=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,360,324) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
    self=[super initWithWindow:w];
    if (self) {
        w.title=@"XDRLight"; w.releasedWhenClosed=NO;
        self.backlightTitle=[self label:@"屏幕亮度" size:13];
        self.boostTitle=[self label:@"增强强度" size:13];
        self.backlightValue=[self label:@"100%" size:13];
        self.boostValue=[self label:@"100%" size:13];
        for (NSTextField *value in @[self.backlightValue,self.boostValue]) {
            value.alignment=NSTextAlignmentRight;
            value.font=[NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightRegular];
            value.textColor=NSColor.secondaryLabelColor;
        }
        self.backlightSlider=[NSSlider sliderWithValue:1 minValue:.05 maxValue:1 target:owner action:NSSelectorFromString(@"adjustBacklight:")];
        self.boostSlider=[NSSlider sliderWithValue:1 minValue:0 maxValue:1 target:owner action:NSSelectorFromString(@"adjustBoost:")];
        self.backlightSlider.accessibilityLabel=@"屏幕亮度";
        self.boostSlider.accessibilityLabel=@"增强强度";
        for (NSSlider *slider in @[self.backlightSlider,self.boostSlider]) {
            slider.continuous=YES; [w.contentView addSubview:slider];
        }
        self.keepButton=[NSButton checkboxWithTitle:@"持续保持高亮度" target:owner action:NSSelectorFromString(@"keepChanged:")];
        [w.contentView addSubview:self.keepButton];
        self.stateLabel=[self label:@"增强已关闭" size:12];
        self.stateLabel.textColor=NSColor.secondaryLabelColor;
        self.detailsButton=[[NSButton alloc] init];
        self.detailsButton.title=@"";
        self.detailsTitle=[self label:@"运行状态" size:12];
        self.detailsTitle.textColor=NSColor.secondaryLabelColor;
        self.detailsButton.target=self; self.detailsButton.action=@selector(toggleDetails:);
        self.detailsButton.bezelStyle=NSBezelStyleDisclosure;
        self.detailsButton.buttonType=NSButtonTypeOnOff;
        self.detailsButton.font=[NSFont systemFontOfSize:12];
        self.detailsButton.accessibilityLabel=@"展开或收起运行状态";
        [w.contentView addSubview:self.detailsButton];
        self.thermalLabel=[self label:@"整机热状态：读取中" size:12];
        self.edrLabel=[self label:@"HDR 余量：读取中" size:12];
        self.temperatureLabel=[self label:@"电池温度：读取中" size:12];
        for (NSTextField *row in @[self.thermalLabel,self.edrLabel,self.temperatureLabel]) row.textColor=NSColor.secondaryLabelColor;
        self.restoreButton=[NSButton buttonWithTitle:@"关闭并恢复" target:owner action:NSSelectorFromString(@"stopKeeping:")];
        self.restoreButton.bezelStyle=NSBezelStyleRounded;
        self.restoreButton.toolTip=@"关闭持续增强并恢复屏幕色彩";
        [w.contentView addSubview:self.restoreButton];
        [self layoutPanel]; [w center];
    }
    return self;
}
@end
