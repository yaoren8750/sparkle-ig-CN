#import "SPKStorageUsageViewController.h"

#import "../Shared/Avatars/SPKAvatarCache.h"
#import "../Shared/SPKStoragePaths.h"
#import "../Shared/UI/SPKIGAlertPresenter.h"
#import "../Utils.h"
#import "SPKTopicSettingsSupport.h"

@interface SPKStorageUsageViewController ()
@property (nonatomic, strong) NSDictionary<NSString *, NSNumber *> *breakdown;
@end

@implementation SPKStorageUsageViewController

- (instancetype)init {
    return [super initWithTitle:@"Storage" sections:@[] reduceMargin:NO];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self reloadStatsAndRebuild];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadStatsAndRebuild];
}

- (void)reloadStatsAndRebuild {
    self.breakdown = [SPKStoragePaths storageBreakdown];
    [self rebuildSections];
}

- (NSString *)formattedKey:(NSString *)key {
    unsigned long long bytes = [self.breakdown[key] unsignedLongLongValue];
    return [NSByteCountFormatter stringFromByteCount:(long long)bytes countStyle:NSByteCountFormatterCountStyleFile];
}

- (void)rebuildSections {
    NSMutableArray *sections = [NSMutableArray array];

    [sections addObject:SPKTopicSection(@"概览", @[
        [SPKSetting valueCellWithTitle:@"总计"
                              subtitle:[self formattedKey:@"total"]
                                  icon:SPKSettingsIcon(@"info")],
    ],
                                      @"Sparkle 所有数据在设备上占用的存储空间。不包括 Instagram 自身的缓存。")];

    [sections addObject:SPKTopicSection(@"详细占用", @[
        [SPKSetting valueCellWithTitle:@"图库"
                              subtitle:[self formattedKey:@"gallery"]
                                  icon:SPKSettingsIcon(@"sparkle_gallery")],
        [SPKSetting valueCellWithTitle:@"下载"
                              subtitle:[self formattedKey:@"downloads"]
                                  icon:SPKSettingsIcon(@"download")],
        [SPKSetting valueCellWithTitle:@"已删除消息"
                              subtitle:[self formattedKey:@"deletedMessages"]
                                  icon:SPKSettingsIcon(@"channels")],
        [SPKSetting valueCellWithTitle:@"个人资料分析"
                              subtitle:[self formattedKey:@"profileAnalyzer"]
                                  icon:SPKSettingsIcon(@"profile_analyzer")],
        [SPKSetting valueCellWithTitle:@"头像"
                              subtitle:[self formattedKey:@"avatars"]
                                  icon:SPKSettingsIcon(@"user_circle")],
    ],
                                      nil)];

    SPKSetting *clearAvatars =
        [SPKSetting buttonCellWithTitle:@"清除缓存的头像"
                               subtitle:nil
                                   icon:SPKSettingsIcon(@"user_circle")
                                 action:^{
                                     [self confirmClearAvatars];
                                 }];

    clearAvatars.tintColor = [SPKUtils SPKColor_InstagramDestructive];
    clearAvatars.iconTintColor = [SPKUtils SPKColor_InstagramDestructive];

    [sections addObject:SPKTopicSection(
        @"头像",
        @[ clearAvatars ],
        @"头像是 Sparkle 共用的缓存。清除头像缓存可以释放存储空间，之后需要显示时会自动重新下载。"
    )];

    [self replaceSections:sections];
}

- (void)confirmClearAvatars {
    [SPKIGAlertPresenter presentAlertFromViewController:self
                                                  title:@"清除缓存的头像？"
                                                message:@"这将删除设备上的所有头像缓存。下次显示时会重新下载。"
                                                actions:@[
        [SPKIGAlertAction actionWithTitle:@"取消"
                                    style:SPKIGAlertActionStyleCancel
                                  handler:nil],

        [SPKIGAlertAction actionWithTitle:@"清除"
                                    style:SPKIGAlertActionStyleDestructive
                                  handler:^{
                                      [[SPKAvatarCache shared] purge];
                                      [self reloadStatsAndRebuild];
                                  }],
    ]];
}

@end
