#import "SPKDownloadsSettingsViewController.h"

#import "../../App/SPKStartupHooks.h"
#import "../../AssetUtils.h"
#import "../../Settings/SPKSetting.h"
#import "../../Settings/SPKTopicSettingsSupport.h"
#import "../../Utils.h"
#import "../AutoSave/SPKAutoSaveSettingsViewController.h"
#import "../MediaDownload/SPKMediaFFmpeg.h"
#import "../MediaDownload/SPKMediaQualityManager.h"
#import "SPKDownloadTypes.h"

@implementation SPKDownloadsSettingsViewController

+ (UIMenu *)audioPageDefaultActionMenu {
    NSArray<NSDictionary *> *items = @[
        @{@"title" : @"将音频保存到文件", @"value" : @"files", @"icon" : @"audio_download"},
        @{@"title" : @"分享音频", @"value" : @"share", @"icon" : @"share"},
        @{@"title" : @"将音频保存到图库", @"value" : @"gallery", @"icon" : @"sparkle_gallery"},
        @{@"title" : @"播放音频", @"value" : @"play", @"icon" : @"play"},
        @{@"title" : @"复制音频下载链接", @"value" : @"copy_url", @"icon" : @"link"},
        @{@"title" : @"打开菜单", @"value" : @"none", @"icon" : @"action"}
    ];
    NSMutableArray<UICommand *> *commands = [NSMutableArray array];
    for (NSDictionary *item in items) {
        [commands addObject:[UICommand commandWithTitle:item[@"title"]
                                                  image:[SPKAssetUtils menuIconNamed:item[@"icon"]]
                                                 action:@selector(menuChanged:)
                                           propertyList:@{@"defaultsKey" : @"downloads_audio_page_default_action", @"value" : item[@"value"], @"iconName" : item[@"icon"]}]];
    }
    return [UIMenu menuWithChildren:commands];
}

+ (NSArray *)contentSections {
    BOOL ffmpegAvailable = [SPKMediaFFmpeg isAvailable];
    if (!ffmpegAvailable) {
        // No FFmpeg = no DASH merge for ANY account, so this is a hard global
        // constraint, not a per-account choice. Write it globally (direct).
        [[NSUserDefaults standardUserDefaults] setObject:@"high_ignore_dash" forKey:@"downloads_video_quality"];
    }

    SPKSetting *videoQualitySetting =
        [SPKSetting menuCellWithTitle:@"默认视频质量"
                             subtitle:(ffmpegAvailable ? @"" : @"需要 FFmpegKit")
                                 icon:SPKSettingsIcon(@"video")
                                  menu:SPKMediaVideoQualityMenu()];
    videoQualitySetting.userInfo = @{@"enabled" : @(ffmpegAvailable)};

    SPKSetting *encodingSettings =
        [SPKSetting navigationCellWithTitle:@"编码设置"
                                   subtitle:(ffmpegAvailable ? @"" : @"需要 FFmpegKit")
                                       icon:SPKSettingsIcon(@"settings")
                                 viewController:[SPKMediaQualityManager encodingSettingsViewController]];
    encodingSettings.userInfo = @{@"enabled" : @(ffmpegAvailable)};
    encodingSettings.searchSectionsProvider = ^NSArray * {
        return [SPKMediaQualityManager encodingSettingsSearchSections];
    };

    SPKSetting *encodingLogs =
        [SPKSetting navigationCellWithTitle:@"查看编码日志"
                                   subtitle:@""
                                       icon:SPKSettingsIcon(@"logs")
                                 viewController:[SPKMediaFFmpeg logsViewController]];
    encodingLogs.userInfo = @{@"enabled" : @YES};

    NSString *qualityFooter = ffmpegAvailable
        ? @"1. 模拟网页浏览器请求 4K 图片版本（会额外调用一次 Web API）。\n"
          @"2. 获取 Instagram 为照片和视频提供的最高分辨率版本。\n"
          @"3. 设置下载照片的默认画质。\n"
          @"4. “高”会合并 DASH 文件以获得最佳画质；“默认”使用可直接播放的文件；“每次询问”会在每次下载时让你选择。\n"
          @"5. 设置合并后视频的重新编码方式（编码格式、容器和比特率）。\n"
          @"6. 查看最近编码任务的 FFmpeg 输出日志。"
        : @"1. 模拟网页浏览器请求 4K 图片版本（会额外调用一次 Web API）。\n"
          @"2. 获取 Instagram 为照片和视频提供的最高分辨率版本。\n"
          @"视频画质选项和编码功能需要 FFmpegKit。";

    SPKSetting *autoSave =
        [SPKSetting navigationCellWithTitle:@"自动保存"
                                   subtitle:@""
                                       icon:SPKSettingsIcon(@"download")
                                 viewController:[SPKAutoSaveSettingsViewController new]];
    autoSave.searchSectionsProvider = ^NSArray * {
        return [SPKAutoSaveSettingsViewController searchSections];
    };

    return @[
        SPKTopicSection(@"自动保存", @[ autoSave ],
                        @"浏览内容时自动下载媒体。"),

        SPKTopicSection(@"下载设置", @[
            [SPKSetting switchCellWithTitle:@"检测重复下载"
                                       icon:SPKSettingsIcon(@"duplicate")
                                defaultsKey:kSPKDownloadDetectDuplicatesKey],

            [SPKSetting stepperCellWithTitle:@"同时下载数"
                                    subtitle:@"%@ 个%@"
                                        icon:SPKSettingsIcon(@"parallel")
                                 defaultsKey:kSPKDownloadMaxConcurrentKey
                                         min:1
                                         max:4
                                        step:1
                                       label:@"下载任务"
                               singularLabel:@"下载任务"],

            [SPKSetting stepperCellWithTitle:@"历史记录上限"
                                    subtitle:@"保存 %@ 条%@"
                                        icon:SPKSettingsIcon(@"history")
                                 defaultsKey:kSPKDownloadHistoryLimitKey
                                         min:50
                                         max:1000
                                        step:50
                                       label:@"记录"
                               singularLabel:@"记录"],

            ({
                SPKSetting *toggle =
                    [SPKSetting switchCellWithTitle:@"保存到自定义相册"
                                                icon:SPKSettingsIcon(@"photo_gallery")
                                         defaultsKey:@"downloads_photos_album_enabled"];
                toggle.reloadsTableOnSwitchChange = YES;
                toggle;
            }),

            ({
                SPKSetting *album =
                    [SPKSetting textFieldCellWithTitle:@"相册名称"
                                           placeholder:@"Sparkle"
                                          keyboardType:UIKeyboardTypeDefault
                                           defaultsKey:@"downloads_photos_album"];
                album.icon = SPKSettingsIcon(@"folder");
                album.enabledProvider = ^BOOL {
                    return [SPKUtils getBoolPref:@"downloads_photos_album_enabled"];
                };
                album;
            }),
            
        ],
@"1. 下载前检查媒体是否已保存，已保存的媒体将跳过。图库会进行精确匹配；照片仅检查 Sparkle 在开启追踪时保存的媒体。\n"
@"2. 设置同时进行的下载数量。\n"
@"3. 设置下载历史记录保留的已完成项目数量，超出后将从最早的记录开始清理。\n"
@"4. 将保存到照片的媒体归类到指定的自定义相册。"),

SPKTopicSection(@"画质", @[
    ({
        SPKSetting *toggle =
            [SPKSetting switchCellWithTitle:@"获取 4K 图片"
                                        icon:SPKSettingsIcon(@"web")
                                 defaultsKey:@"downloads_fetch_4k_images"];

        toggle.switchChangeHandler = ^(BOOL isOn) {
            [[NSUserDefaults standardUserDefaults]
                setBool:isOn
                forKey:SPKEffectivePreferenceKey(@"downloads_fetch_4k_images")];

            if (!isOn) {
                NSString *qualityKey =
                    SPKEffectivePreferenceKey(@"downloads_photo_quality");
                NSString *quality =
                    [[NSUserDefaults standardUserDefaults] stringForKey:qualityKey];

                if ([quality isEqualToString:@"max"]) {
                    [[NSUserDefaults standardUserDefaults]
                        setObject:@"high"
                        forKey:qualityKey];
                }
            }
        };

        toggle.reloadsTableOnSwitchChange = YES;
        toggle;
    }),

    [SPKSetting switchCellWithTitle:@"增强媒体画质"
                               icon:SPKSettingsIcon(@"hd")
                        defaultsKey:@"downloads_enhanced_media_resolution"],

    [SPKSetting menuCellWithTitle:@"默认照片画质"
                             icon:SPKSettingsIcon(@"photo")
                             menu:SPKMediaPhotoQualityMenu()],

    videoQualitySetting,
    encodingSettings,
    encodingLogs
],
qualityFooter),

[self audioSection]
    ];
}

// The "Audio Downloads" master toggle gates every other audio action tweak-wide.
// The dependent cells stay visible (and keep their stored value) but are disabled
// while the master is off.
+ (NSDictionary *)audioSection {
    BOOL (^audioEnabled)(void) = ^BOOL {
        return [SPKUtils getBoolPref:@"downloads_audio_enabled"];
    };

    SPKSetting *master =
        [SPKSetting switchCellWithTitle:@"下载音频"
                                   icon:SPKSettingsIcon(@"audio_download")
                            defaultsKey:@"downloads_audio_enabled"];

    master.switchChangeHandler = ^(BOOL isOn) {
        [[NSUserDefaults standardUserDefaults]
            setBool:isOn
            forKey:SPKEffectivePreferenceKey(@"downloads_audio_enabled")];

        if (isOn)
            SPKInstallEnabledFeatureHooks();
    };

    master.reloadsTableOnSwitchChange = YES; // grey out / re-enable the dependents live

    SPKSetting *pageButton =
        [SPKSetting switchCellWithTitle:@"音频页面按钮"
                                   icon:SPKSettingsIcon(@"audio_page")
                            defaultsKey:@"downloads_audio_page_button"];

    pageButton.enabledProvider = audioEnabled;

    SPKSetting *pageDefault =
        SPKSettingApplySelectedMenuIcon(
            [SPKSetting menuCellWithTitle:@"音频页面默认操作"
                                     icon:SPKSettingsIcon(@"action")
                                     menu:[self audioPageDefaultActionMenu]],
            SPKSettingsIcon(@"action"));

    pageDefault.enabledProvider = audioEnabled;

    return SPKTopicSection(@"音频", @[ master, pageButton, pageDefault ],
                           @"为音频页面和媒体操作按钮添加音频相关功能。");
}

+ (NSArray *)searchSections {
    return [self contentSections];
}

- (instancetype)init {
    return [super initWithTitle:@"下载设置"
                        sections:[[self class] contentSections]
                    reduceMargin:NO];
}

@end
