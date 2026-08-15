#import "SPKOnboardingViewController.h"

@implementation SPKOnboardingViewController

- (NSArray<SPKPagedSheetPage *> *)buildPages {
    return @[
        [SPKPagedSheetPage pageWithTitle:@"欢迎使用 Sparkle"
                                    body:@"你喜爱 Instagram 的一切，现在都拥有了它从未提供过的更多控制功能——全部集成其中，带来更流畅的使用体验。"
                                    rows:nil],

        [SPKPagedSheetPage pageWithTitle:@"你可以做什么"
                                    body:@""
                                    rows:@[
                                        @{ @"icon": @"download", @"text": @"以高画质下载任何内容" },
                                        @{ @"icon": @"sparkle_gallery", @"text": @"将媒体保存到私人图库" },
                                        @{ @"icon": @"profile_analyzer", @"text": @"追踪粉丝、取消关注和个人资料变化" },
                                        @{ @"icon": @"channels", @"text": @"即使消息被删除，也能保留消息内容" },
                                        @{ @"icon": @"eye", @"text": @"控制已读回执和正在输入状态" },
                                        @{ @"icon": @"ads", @"text": @"移除广告及其他干扰内容" },
                                        @{ @"icon": @"", @"text": @"……还有更多功能！" },
                                    ]],

        [SPKPagedSheetPage pageWithTitle:@"随时打开 Sparkle"
                                    body:@"你可以通过以下方式随时打开 Sparkle 设置："
                                    rows:@[
                                        @{ @"icon": @"settings_menu", @"text": @"长按个人主页上的菜单按钮" },
                                        @{ @"icon": @"home", @"text": @"长按主页标签" },
                                        @{ @"icon": @"action", @"text": @"启用信息流顶部的按钮" },
                                    ]],
    ];
}

@end
