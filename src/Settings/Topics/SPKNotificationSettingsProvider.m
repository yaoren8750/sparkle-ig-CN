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
            NSString *title = item[@"title"] ?: @"Feature";
            NSString *iconName = item[@"iconName"] ?: @"info";
            SPKSetting *setting = [SPKSetting switchCellWithTitle:title
                                                         subtitle:@""
                                                             icon:SPKSettingsIcon(iconName)
                                                      defaultsKey:haptics ? SPKNotificationHapticDefaultsKey(identifier) : SPKNotificationDefaultsKey(identifier)];
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
            @"subtitle" : @"Notification preview: success tone.",
            @"iconResource" : @"circle_check_filled",
            @"tone" : @(SPKNotificationToneSuccess)
        },
        @{
            @"title" : @"Something Went Wrong",
            @"subtitle" : @"Notification preview: error tone.",
            @"iconResource" : @"error_filled",
            @"tone" : @(SPKNotificationToneError)
        },
        @{
            @"title" : @"Heads Up",
            @"subtitle" : @"Notification preview: info tone.",
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
        SPKTopicSection(@"Appearance", @[
            [SPKSetting switchCellWithTitle:@"Glow"
                                   subtitle:@"Show glow effect around notifications"
                                defaultsKey:kSPKNotificationPillGlowEnabledKey],
            [SPKSetting switchCellWithTitle:@"Liquid Glass"
                                   subtitle:(SPKPrefIsAvailable(kSPKNotificationPillLiquidGlassEnabledKey)
                                                 ? @"Render notifications with iOS 26 Liquid Glass"
                                                 : @"Requires iOS 26 or later")
                                   defaultsKey:kSPKNotificationPillLiquidGlassEnabledKey],
            [SPKSetting menuCellWithTitle:@"Download Progress"
                                 subtitle:@""
                                     menu:SPKNotificationProgressSubtitleStyleMenu()],
            [SPKSetting menuCellWithTitle:@"Position"
                                 subtitle:@""
                                     menu:SPKNotificationPillPositionMenu()],
            [SPKSetting stepperCellWithTitle:@"Duration"
                                    subtitle:@"Dismiss after %@%@"
                                 defaultsKey:kSPKNotificationPillDurationKey
                                         min:0.5
                                         max:5.0
                                        step:0.25
                                       label:@" seconds"
                               singularLabel:@" second"]
        ],
                        nil),
        SPKTopicSection(@"Preview", @[
            [SPKSetting buttonCellWithTitle:@"Test Notification"
                                   subtitle:@""
                                       icon:nil
                                     action:^{
                                         [self spk_showNextNotificationPreview];
                                     }]
        ],
                        nil),
        SPKTopicSection(@"", @[
            [SPKSetting navigationCellWithTitle:@"Haptics"
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
