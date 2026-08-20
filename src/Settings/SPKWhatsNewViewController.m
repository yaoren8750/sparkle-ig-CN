#import "SPKWhatsNewViewController.h"
#import "../Tweak.h"

@implementation SPKWhatsNewViewController

// Release notes are curated from the conventional-commit log for the release range
// (see whats-new.sh). Feature rows carry a per-surface IG catalog glyph; fix rows
// share the `subtract` bullet so they read as one clean list. Icon names are
// SPKAssetUtils override keys — never SF Symbols. Keep in sync with README/FEATURES.
- (NSArray<SPKPagedSheetPage *> *)buildPages {
    return @[
        [SPKPagedSheetPage pageWithTitle:@"新功能"
                                  body:[NSString stringWithFormat:@"探索 %@ 的新功能", SPKVersionString]
                                  rows:@[
                                      @{ @"icon": @"sparkle_gallery", @"text": @"从「文件」或 Regram 私密库将媒体导入图库" },
                                      @{ @"icon": @"folder", @"text": @"一次查看图库中的所有文件，无需逐个打开文件夹" },
                                      @{ @"icon": @"crop", @"text": @"视频支持裁剪、旋转和翻转，剪辑更精细" },
                                      @{ @"icon": @"instants", @"text": @"将任意媒体上传为即时内容" },
                                      @{ @"icon": @"instants_burst", @"text": @"按用户查看你保存的所有即时内容" },
                                      @{ @"icon": @"download", @"text": @"查看限时动态、阅后即焚消息和即时内容时自动保存" },
                                      @{ @"icon": @"external_link", @"text": @"个人主页、帖子和 Reels 可直接打开为真实 Instagram 页面" },
                                  ]],
        [SPKPagedSheetPage pageWithTitle:@"更多功能"
                                  body:@""
                                  rows:@[
                                      @{ @"icon": @"hd_check_filled", @"text": @"优化照片画质选项，支持获取 4K 原图" },
                                      @{ @"icon": @"folder", @"text": @"将下载内容保存到自定义照片相册" },
                                      @{ @"icon": @"pinch", @"text": @"全屏预览视频时双指捏合即可缩放" },
                                      @{ @"icon": @"messages", @"text": @"优化「仅消息」模式" },
                                      @{ @"icon": @"story_preview", @"text": @"长按聊天即可预览消息内容" },
                                      @{ @"icon": @"sticker", @"text": @"从照片或 Sparkle 图库将视频上传为限时动态贴图" },
                                      @{ @"icon": @"calendar", @"text": @"在操作按钮菜单中查看帖子的发布日期" },
                                      @{ @"icon": @"profile_analyzer", @"text": @"在个人主页分析器中滑动即可删除单项变化记录" },
                                      @{ @"icon": @"filter", @"text": @"图库选择器支持跨文件夹排序、筛选和搜索" },
                                      @{ @"text": @"还有更多功能等你发现！" },
                                  ]],
        [SPKPagedSheetPage pageWithTitle:@"修复与优化"
                                  body:@""
                                  rows:@[
                                      @{ @"icon": @"subtract", @"text": @"修复使用几屏后应用卡顿、运行缓慢的问题" },
                                      @{ @"icon": @"subtract", @"text": @"通知现在即时送达，不再重复显示" },
                                      @{ @"icon": @"subtract", @"text": @"图库速度大幅提升：打开更快、选择更流畅、占用内存更少" },
                                      @{ @"icon": @"subtract", @"text": @"修复最新 Instagram 上限时动态预览和收件箱刷新问题" },
                                      @{ @"icon": @"subtract", @"text": @"即时内容现已支持完整分辨率下载和自动保存" },
                                      @{ @"icon": @"subtract", @"text": @"投票结果现在会遵循截图时的「隐藏界面」设置" },
                                      @{ @"icon": @"subtract", @"text": @"安全模式现在会说明原因，并提供关闭选项" },
                                      @{ @"icon": @"subtract", @"text": @"修复其他问题并优化界面体验" },
                                  
                                    ]],
    ];
}

- (NSString *)finishButtonTitle {
    return @"完成";
}

- (BOOL)allowsInteractiveDismiss {
    return YES;
}

@end
