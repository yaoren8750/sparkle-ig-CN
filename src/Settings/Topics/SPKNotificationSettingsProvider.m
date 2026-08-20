#import "SPKNotificationSettingsProvider.h"
#import "../../Shared/UI/SPKNotificationCenter.h"
#import "../../Utils.h"
#import "../SPKPreferenceAvailability.h"
#import "../SPKTopicSettingsSupport.h"

@implementation SPKNotificationSettingsProvider

+ (NSArray<NSDictionary *> *)spk_featureSectionsForHaptics:(BOOL)haptics {
    NSMutableArray<NSDictionary *> *sections = [NSMutableArray array];

    for (NSDictionary *sectionInfo in SPKNotificationPreferenceSections()) {
        NSMutableArray<SPKSetting *> *rows = [NSMutableArray array];

        for (NSDictionary *item in sectionInfo[@"items"] ?: @[]) {
            NSString *identifier = item[@"identifier"];
            NSString *title = item[@"title"] ?: @"功能";
            NSString *iconName = item[@"iconName"] ?: @"info";

            SPKSetting *setting =
                [SPKSetting switchCellWithTitle:title
                                        subtitle:@""
                                            icon:SPKSettingsIcon(iconName)
                                     defaultsKey:haptics
                                         ? SPKNotificationHapticDefaultsKey(identifier)
                                         : SPKNotificationDefaultsKey(identifier)];

            setting.userInfo = @{@"defaultValue" : @YES};
            [rows addObject:setting];
        }

        NSString *sectionTitle = sectionInfo[@"title"] ?: @"";
        [sections addObject:SPKTopicSection(sectionTitle, [rows copy], nil)];
    }

    return [sections copy];
}

+ (void)spk_showNextNotificationPreview {
    static NSUInteger toneIndex = 0;

    NSArray<NSDictionary *> *configs = @[
        @{
            @"title" : @"已保存到图库",
            @"subtitle" : @"通知预览：成功提示音。",
            @"iconResource" : @"circle_check_filled",
            @"tone" : @(SPKNotificationToneSuccess)
        },
        @{
            @"title" : @"出现问题",
            @"subtitle" : @"通知预览：错误提示音。",
            @"iconResource" : @"error_filled",
            @"tone" : @(SPKNotificationToneError)
        },
        @{
            @"title" : @"提示",
            @"subtitle" : @"通知预览：信息提示音。",
            @"iconResource" : @"info_filled",
            @"tone" : @(SPKNotificationToneInfo)
        }
    ];

    NSDictionary *config = configs[toneIndex % configs.count];
    toneIndex++;

    SPKNotify(kSPKNotificationSettingsClearCache,
              config[@"title"],
              config[@"subtitle"],
              config[@"iconResource"],
              [config[@"tone"] unsignedIntegerValue]);
}

+ (NSArray *)sections {
    NSMutableArray *sections = [NSMutableArray arrayWithArray:@[
        SPKTopicSection(@"外观", @[
            [SPKSetting switchCellWithTitle:@"发光效果"
                                   subtitle:@"在通知周围显示发光效果"
                                defaultsKey:kSPKNotificationPillGlowEnabledKey],

            [SPKSetting switchCellWithTitle:@"液态玻璃"
                                   subtitle:(SPKPrefIsAvailable(kSPKNotificationPillLiquidGlassEnabledKey)
                                                 ? @"使用 iOS 26 液态玻璃显示通知"
                                                 : @"需要 iOS 26 或更高版本")
                                defaultsKey:kSPKNotificationPillLiquidGlassEnabledKey],

            [SPKSetting menuCellWithTitle:@"下载进度"
                                 subtitle:@""
                                     menu:SPKNotificationProgressSubtitleStyleMenu()],

            [SPKSetting menuCellWithTitle:@"位置"
                                 subtitle:@""
                                     menu:SPKNotificationPillPositionMenu()],

            [SPKSetting stepperCellWithTitle:@"持续时间"
                                    subtitle:@"在 %@%@ 后关闭"
                                 defaultsKey:kSPKNotificationPillDurationKey
                                         min:0.5
                                         max:5.0
                                        step:0.25
                                       label:@" 秒"
                               singularLabel:@" 秒"]
        ],
        nil),

        SPKTopicSection(@"预览", @[
            [SPKSetting buttonCellWithTitle:@"测试通知"
                                   subtitle:@""
                                       icon:nil
                                     action:^{
                                         [self spk_showNextNotificationPreview];
                                     }]
        ],
        nil),

        SPKTopicSection(@"", @[
            [SPKSetting navigationCellWithTitle:@"触感反馈"
                                       subtitle:@""
                                           icon:SPKSettingsIcon(@"haptics")
                                    navSections:[self spk_featureSectionsForHaptics:YES]]
        ],
        nil)
    ]];

    [sections addObjectsFromArray:[self spk_featureSectionsForHaptics:NO]];

    return [sections copy];
}

@end
