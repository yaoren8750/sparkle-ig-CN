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
        @{@"title" : @"Open Menu", @"value" : @"none", @"icon" : @"action"}
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

    SPKSetting *videoQualitySetting = [SPKSetting menuCellWithTitle:@"Default Video Quality"
                                                           subtitle:(ffmpegAvailable ? @"" : @"Requires FFmpegKit")
                                                           icon:SPKSettingsIcon(@"video")
                                                               menu:SPKMediaVideoQualityMenu()];
    videoQualitySetting.userInfo = @{@"enabled" : @(ffmpegAvailable)};

    SPKSetting *encodingSettings = [SPKSetting navigationCellWithTitle:@"Encoding Settings"
                                                              subtitle:(ffmpegAvailable ? @"" : @"Requires FFmpegKit")
                                                              icon:SPKSettingsIcon(@"settings")
                                                        viewController:[SPKMediaQualityManager encodingSettingsViewController]];
    encodingSettings.userInfo = @{@"enabled" : @(ffmpegAvailable)};
    encodingSettings.searchSectionsProvider = ^NSArray * {
        return [SPKMediaQualityManager encodingSettingsSearchSections];
    };

    SPKSetting *encodingLogs = [SPKSetting navigationCellWithTitle:@"View Encoding Logs"
                                                          subtitle:@""
                                                              icon:SPKSettingsIcon(@"logs")
                                                    viewController:[SPKMediaFFmpeg logsViewController]];
    encodingLogs.userInfo = @{@"enabled" : @YES};

    NSString *qualityFooter = ffmpegAvailable
        ? @"1. Request 4K image candidates by mimicking a web browser (extra call to the web API).\n"
          @"2. Fetch the highest-resolution variant Instagram exposes for photos and videos.\n"
          @"3. Preferred quality for downloaded photos.\n"
          @"4. \"High\" merges DASH files for best quality, \"Default\" uses ready-to-play files, \"Always Ask\" prompts for selection each time.\n"
          @"5. Configure how merged videos are re-encoded (codec, container, bitrate).\n"
          @"6. Review the FFmpeg output from recent encoding jobs."
        : @"1. Request 4K image candidates by mimicking a web browser (extra call to the web API).\n"
          @"2. Fetch the highest-resolution variant Instagram exposes for photos and videos.\n"
          @"FFmpegKit is required for video quality options and encoding features.";

    SPKSetting *autoSave = [SPKSetting navigationCellWithTitle:@"Auto-Save"
                                                      subtitle:@""
                                                          icon:SPKSettingsIcon(@"download")
                                                viewController:[SPKAutoSaveSettingsViewController new]];
    autoSave.searchSectionsProvider = ^NSArray * {
        return [SPKAutoSaveSettingsViewController searchSections];
    };

    return @[
        SPKTopicSection(@"Auto-Save", @[ autoSave ],
                        @"Automatically download media as you view it."),
        SPKTopicSection(@"Behavior", @[
            [SPKSetting switchCellWithTitle:@"Detect Duplicate Downloads"
                                       icon:SPKSettingsIcon(@"duplicate")
                                defaultsKey:kSPKDownloadDetectDuplicatesKey],
            [SPKSetting stepperCellWithTitle:@"Parallel Downloads"
                                    subtitle:@"%@ concurrent %@"
                                        icon:SPKSettingsIcon(@"parallel")
                                 defaultsKey:kSPKDownloadMaxConcurrentKey
                                         min:1
                                         max:4
                                        step:1
                                       label:@"downloads"
                               singularLabel:@"download"],
            [SPKSetting stepperCellWithTitle:@"History Limit"
                                    subtitle:@"%@ saved %@"
                                        icon:SPKSettingsIcon(@"history")
                                 defaultsKey:kSPKDownloadHistoryLimitKey
                                         min:50
                                         max:1000
                                        step:50
                                       label:@"entries"
                               singularLabel:@"entry"],
            ({
                SPKSetting *toggle = [SPKSetting switchCellWithTitle:@"Save to Custom Album"
                                                                icon:SPKSettingsIcon(@"photo_gallery")
                                                         defaultsKey:@"downloads_photos_album_enabled"];
                toggle.reloadsTableOnSwitchChange = YES;
                toggle;
            }),
            ({
                SPKSetting *album = [SPKSetting textFieldCellWithTitle:@"Album Name"
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
                        @"1. Check before downloading and skip media already saved. Gallery checks are exact; Photos checks cover media Sparkle saved while tracking is enabled.\n"
                        @"2. How many downloads may run at the same time.\n"
                        @"3. How many finished entries the download history keeps before trimming the oldest.\n"
                        @"4. Group saved Photos media under a specific custom album."),
        SPKTopicSection(@"Quality", @[
            ({
                SPKSetting *toggle = [SPKSetting switchCellWithTitle:@"Fetch 4K Images"
                                                                icon:SPKSettingsIcon(@"web")
                                                         defaultsKey:@"downloads_fetch_4k_images"];
                toggle.switchChangeHandler = ^(BOOL isOn) {
                    [[NSUserDefaults standardUserDefaults] setBool:isOn forKey:SPKEffectivePreferenceKey(@"downloads_fetch_4k_images")];
                    if (!isOn) {
                        NSString *qualityKey = SPKEffectivePreferenceKey(@"downloads_photo_quality");
                        NSString *quality = [[NSUserDefaults standardUserDefaults] stringForKey:qualityKey];
                        if ([quality isEqualToString:@"max"]) {
                            [[NSUserDefaults standardUserDefaults] setObject:@"high" forKey:qualityKey];
                        }
                    }
                };
                toggle.reloadsTableOnSwitchChange = YES;
                toggle;
            }),
            [SPKSetting switchCellWithTitle:@"Enhanced Media Resolution"
                                       icon:SPKSettingsIcon(@"hd")
                                defaultsKey:@"downloads_enhanced_media_resolution"],
            [SPKSetting menuCellWithTitle:@"Default Photo Quality"
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

    SPKSetting *master = [SPKSetting switchCellWithTitle:@"Audio Downloads" icon:SPKSettingsIcon(@"audio_download") defaultsKey:@"downloads_audio_enabled"];
    master.switchChangeHandler = ^(BOOL isOn) {
        [[NSUserDefaults standardUserDefaults] setBool:isOn forKey:SPKEffectivePreferenceKey(@"downloads_audio_enabled")];
        if (isOn)
            SPKInstallEnabledFeatureHooks();
    };
    master.reloadsTableOnSwitchChange = YES; // grey out / re-enable the dependents live

    SPKSetting *pageButton = [SPKSetting switchCellWithTitle:@"Audio Page Button" icon:SPKSettingsIcon(@"audio_page") defaultsKey:@"downloads_audio_page_button"];
    pageButton.enabledProvider = audioEnabled;

    SPKSetting *pageDefault = SPKSettingApplySelectedMenuIcon([SPKSetting menuCellWithTitle:@"Audio Page Default Action" icon:SPKSettingsIcon(@"action") menu:[self audioPageDefaultActionMenu]], SPKSettingsIcon(@"action"));
    pageDefault.enabledProvider = audioEnabled;

    return SPKTopicSection(@"音频", @[ master, pageButton, pageDefault ],
                           @"Adds audio actions for audio pages and media action buttons.");
}

+ (NSArray *)searchSections {
    return [self contentSections];
}

- (instancetype)init {
    return [super initWithTitle:@"Downloads Settings" sections:[[self class] contentSections] reduceMargin:NO];
}

@end
