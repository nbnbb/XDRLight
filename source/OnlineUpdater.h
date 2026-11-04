#import <Sparkle/Sparkle.h>

@interface OnlineUpdater : NSObject <SPUUpdaterDelegate>
@property SPUStandardUpdaterController *controller;
@property BOOL started;
- (void)check:(id)sender;
- (void)configure:(id)sender;
@end
@implementation OnlineUpdater
- (NSString *)serviceURL {
    NSString *custom = [NSUserDefaults.standardUserDefaults stringForKey:@"XDRUpdateServiceURL"];
    return custom.length ? custom : [NSBundle.mainBundle objectForInfoDictionaryKey:@"SUFeedURL"];
}
- (instancetype)init {
    self = [super init];
    if (self) {
        _controller = [[SPUStandardUpdaterController alloc] initWithStartingUpdater:NO updaterDelegate:self userDriverDelegate:nil];
        if ([self serviceURL].length) [self start];
    }
    return self;
}
- (void)message:(NSString *)title detail:(NSString *)detail {
    NSAlert *alert = [NSAlert new]; alert.messageText = title; alert.informativeText = detail;
    [NSApp activateIgnoringOtherApps:YES]; [alert runModal];
}
- (BOOL)start {
    if (self.started) return YES;
    NSError *error = nil;
    self.started = [self.controller.updater startUpdater:&error];
    if (!self.started) [self message:@"更新服务暂不可用" detail:error.localizedDescription ?: @"请检查更新地址。"];
    return self.started;
}
- (NSString *)feedURLStringForUpdater:(SPUUpdater *)updater { (void)updater; return [self serviceURL]; }
- (NSArray<NSString *> *)allowedSystemProfileKeysForUpdater:(SPUUpdater *)updater { (void)updater; return @[]; }
- (void)check:(id)sender {
    if (![self serviceURL].length) { [self configure:sender]; return; }
    if ([self start]) [self.controller checkForUpdates:sender];
}
- (void)configure:(id)sender {
    (void)sender;
    if (self.controller.updater.sessionInProgress) { [self message:@"正在检查或下载更新" detail:@"请等待当前更新完成后再更改地址。"]; return; }
    NSAlert *alert = [NSAlert new]; alert.messageText = @"设置更新服务地址";
    alert.informativeText = @"填写你的网站提供的完整 HTTPS 更新地址。软件只接受本应用发布密钥签名的更新包。";
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 440, 26)];
    field.placeholderString = @"https://你的域名/xdrlight/appcast.xml";
    field.stringValue = [self serviceURL] ?: @""; alert.accessoryView = field;
    [alert addButtonWithTitle:@"保存并检查"]; [alert addButtonWithTitle:@"取消"];
    [NSApp activateIgnoringOtherApps:YES];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSString *value = [field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSURL *url = [NSURL URLWithString:value];
    if (![url.scheme.lowercaseString isEqualToString:@"https"] || !url.host.length || url.user.length || url.password.length || url.fragment.length) {
        [self message:@"更新地址无效" detail:@"请输入完整 HTTPS 地址，不要包含账号、密码或片段标记。"]; return;
    }
    [NSUserDefaults.standardUserDefaults setObject:url.absoluteString forKey:@"XDRUpdateServiceURL"];
    if ([self start]) {
        [self.controller.updater resetUpdateCycle];
        [self.controller checkForUpdates:nil];
    }
}
@end
