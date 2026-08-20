#import "SPKAboutSettingsProvider.h"

#import "../../AssetUtils.h"
#import "../../Tweak.h"
#import "../../Utils.h"
#import "../SPKTopicSettingsSupport.h"

@implementation SPKAboutSettingsProvider

+ (SPKSetting *)rootSetting {
    // 更大、更粗的标题，与 45pt Ko-fi 图标保持视觉平衡。
    SPKSetting *donate = [SPKSetting linkCellWithTitle:@"支持 waffle"
                                              subtitle:@""
                                              imageUrl:@"https://cdn.prod.website-files.com/5c14e387dab576fe667689cf/670f5a01229bf8a18f97a3c1_favion.png"
                                                   url:@"https://ko-fi.com/sparkle_ig"];
    donate.userInfo = @{
        @"titleFont" : [UIFont systemFontOfSize:20.0 weight:UIFontWeightSemibold],
        @"remoteImageCircular" : @NO
    };

    return SPKTopicNavigationSetting(@"关于", @"info", 24.0, @[
        SPKTopicSection(@"支持", @[
            donate
        ],
                        @"考虑捐赠以支持插件开发。"),

        SPKTopicSection(@"信息", @[
            [SPKSetting staticCellWithTitle:@"Sparkle"
                                   subtitle:SPKVersionString
                                       icon:SPKSettingsIcon(@"action")],
            [SPKSetting staticCellWithTitle:@"Instagram"
                                   subtitle:[SPKUtils IGVersionString]
                                       icon:SPKSettingsIcon(@"app")],
            [SPKSetting staticCellWithTitle:@"Bundle ID"
                                   subtitle:[[NSBundle mainBundle] bundleIdentifier]
                                       icon:SPKSettingsIcon(@"key")]
        ],
                        nil),

        SPKTopicSection(@"", @[
            [SPKSetting linkCellWithTitle:@"waffle"
                                 subtitle:@"Sparkle 开发者"
                                 imageUrl:@"https://avatars.githubusercontent.com/u/117626247?v=4"
                                      url:@"https://github.com/efibalogh"],

            [SPKSetting linkCellWithTitle:@"查看源代码"
                                 subtitle:@"点击打开 GitHub"
                                 imageUrl:@"https://i.imgur.com/BBUNzeP.png"
                                      url:@"https://github.com/efibalogh/sparkle-ig"]
        ],
                        nil),

        SPKTopicSection(@"社区", @[
            [SPKSetting linkCellWithTitle:@"Telegram 频道"
                                 subtitle:@"加入社区获取更新和支持"
                                 imageUrl:@"https://upload.wikimedia.org/wikipedia/commons/thumb/8/82/Telegram_logo.svg/960px-Telegram_logo.svg.png"
                                      url:@"https://t.me/sparkle_ig"]
        ],
                        nil),

        SPKTopicSection(@"致谢", @[
            [SPKSetting linkCellWithTitle:@"SoCuul • SCInsta"
                                 subtitle:@"Sparkle 所基于的基础项目"
                                 imageUrl:@"https://i.imgur.com/c9CbytZ.png"
                                      url:@"https://github.com/SoCuul/SCInsta"],

            [SPKSetting linkCellWithTitle:@"Ryuk • RyukGram"
                                 subtitle:@"代码、灵感和帮助"
                                 imageUrl:@"https://avatars.githubusercontent.com/u/51106560?v=4"
                                      url:@"https://github.com/faroukbmiled/"],

            [SPKSetting linkCellWithTitle:@"@n3d1117 • InstaSane"
                                 subtitle:@"关注动态模式"
                                 imageUrl:@"https://avatars.githubusercontent.com/u/11541888?v=4"
                                      url:@"https://github.com/n3d1117/InstaSane"],

            [SPKSetting linkCellWithTitle:@"@asdfzxcvbn • zxPluginsInject"
                                 subtitle:@"修复侧载安装相关问题"
                                 imageUrl:@"https://avatars.githubusercontent.com/u/109937991?v=4"
                                      url:@"https://github.com/asdfzxcvbn/zxPluginsInject"]
        ],
                        nil),
    ]);
}

@end
