#import "SPKGallerySettingsViewController.h"
#import "../../AssetUtils.h"
#import "../../Settings/SPKTopicSettingsSupport.h"
#import "../../Utils.h"
#import "../Account/SPKAccountManager.h"
#import "../UI/SPKIGAlertPresenter.h"
#import "SPKGalleryCoreDataStack.h"
#import "SPKGalleryDeleteViewController.h"
#import "SPKGalleryFile.h"
#import "SPKGalleryGridDensity.h"
#import "SPKGalleryHiddenSources.h"
#import "SPKGalleryImportViewController.h"
#import "SPKGalleryLockViewController.h"
#import "SPKGalleryManager.h"

@interface SPKGalleryHiddenSourcesViewController : SPKSettingsViewController
@end

@implementation SPKGalleryHiddenSourcesViewController

- (instancetype)init {
    return [super initWithTitle:@"隐藏来源" sections:@[] reduceMargin:NO];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuildSections];
}

- (void)rebuildSections {
    NSMutableArray<SPKSetting *> *rows = [NSMutableArray array];
    NSArray<NSNumber *> *sources = @[
        @(SPKGallerySourceFeed),
        @(SPKGallerySourceStories),
        @(SPKGallerySourceReels),
        @(SPKGallerySourceProfile),
        @(SPKGallerySourceDMs),
        @(SPKGallerySourceThumbnail),
        @(SPKGallerySourceInstants),
        @(SPKGallerySourceAudioPage),
        @(SPKGallerySourceComments),
        @(SPKGallerySourceOther),
    ];
    for (NSNumber *sourceValue in sources) {
        SPKGallerySource source = (SPKGallerySource)sourceValue.integerValue;
        SPKSetting *row = [SPKSetting switchCellWithTitle:[SPKGalleryFile labelForSource:source]
                                                     icon:SPKSettingsIcon([SPKGalleryFile symbolNameForSource:source])
                                              defaultsKey:@""];
        row.switchValueProvider = ^BOOL {
            return SPKGallerySourceIsHidden(source);
        };
        row.switchChangeHandler = ^(BOOL hidden) {
            SPKGallerySetSourceHidden(source, hidden);
        };
        [rows addObject:row];
    }
    [self replaceSections:@[ SPKTopicSection(@"来源", rows, @"隐藏的来源仍会保存在图库中，并继续用于维护、导出和重复内容检测。") ]];
}

@end

static NSString *const kFavoritesAtTopKey = @"gallery_show_favorites_top";
static NSString *const kGalleryLongPressTabKey = @"gallery_quick_access_tab";
static NSString *const kGalleryQuickAccessDisabledValue = @"none";

@interface SPKGalleryStorageStats : NSObject
@property (nonatomic, assign) NSInteger totalFiles;
@property (nonatomic, assign) NSInteger imageCount;
@property (nonatomic, assign) NSInteger videoCount;
@property (nonatomic, assign) NSInteger audioCount;
@property (nonatomic, assign) long long totalSize;
@end

@implementation SPKGalleryStorageStats
@end

@interface SPKGallerySettingsViewController ()
@property (nonatomic, strong) SPKGalleryStorageStats *stats;
@end

@implementation SPKGallerySettingsViewController

+ (NSArray *)searchSections {
    return @[
        SPKTopicSection(@"存储", @[
            [SPKSetting valueCellWithTitle:@"总计"
                                  subtitle:@"图库存储空间和文件数量"
                                      icon:SPKSettingsIcon(@"info")],
            [SPKSetting valueCellWithTitle:@"图片"
                                  subtitle:@"已保存的图片数量"
                                      icon:SPKSettingsIcon(@"photo")],
            [SPKSetting valueCellWithTitle:@"视频"
                                  subtitle:@"已保存的视频数量"
                                      icon:SPKSettingsIcon(@"video")],
            [SPKSetting valueCellWithTitle:@"音频"
                                  subtitle:@"已保存的音频数量"
                                      icon:SPKSettingsIcon(@"audio")]
        ],
                        nil),

        SPKTopicSection(@"浏览", @[
            [SPKSetting switchCellWithTitle:@"置顶收藏"
                                       icon:SPKSettingsIcon(@"heart")
                                defaultsKey:kFavoritesAtTopKey],
            [SPKSetting switchCellWithTitle:@"显示子文件夹中的文件"
                                       icon:SPKSettingsIcon(@"folder")
                                defaultsKey:kSPKGalleryFlatBrowsingKey],
            [SPKSetting navigationCellWithTitle:@"隐藏来源"
                                       subtitle:@""
                                           icon:SPKSettingsIcon(@"eye_off")
                                 viewController:[SPKGalleryHiddenSourcesViewController new]]
        ],
                        @"在当前排序和文件夹范围内，将收藏内容置于其他文件之上。"),

        SPKTopicSection(@"编辑", @[
            [SPKSetting switchCellWithTitle:@"询问是否替换原文件"
                                       icon:SPKSettingsIcon(@"left_right")
                                defaultsKey:@"trim_gallery_prompt_replace"]
        ],
                        @"裁剪或编辑图库项目时，询问是替换原文件还是保存副本。关闭后始终保存副本并保留原文件。"),

        SPKTopicSection(@"预览", @[
            [SPKSetting switchCellWithTitle:@"显示媒体信息"
                                       icon:SPKSettingsIcon(@"info")
                                defaultsKey:@"gallery_preview_show_metadata"]
        ],
                        @"在展开的照片预览中显示用户名、来源以及保存/发布日期。"),

        SPKTopicSection(@"锁定", @[
            [SPKSetting switchCellWithTitle:@"图库密码锁"
                                       icon:SPKSettingsIcon(@"lock")
                                defaultsKey:@""],
            [SPKSetting buttonCellWithTitle:@"更改密码"
                                   subtitle:nil
                                       icon:SPKSettingsIcon(@"key")
                                     action:^{
                                     }]
        ],
                        @"使用密码或生物识别锁定图库。"),

        SPKTopicSection(@"导入", @[
            [SPKSetting navigationCellWithTitle:@"导入媒体"
                                       subtitle:nil
                                           icon:SPKSettingsIcon(@"media")
                                 viewController:[[SPKGalleryImportViewController alloc]
                                                    initWithDestinationFolderPath:nil]]
        ],
                        @"从“文件”App 导入媒体，并保留完整的可编辑元数据。\n"
                        @"从 Regram 导入？在这里选择你导出的文件夹或 MediaVault.zip，即可将整个 Media Vault 导入。"),

        SPKTopicSection(@"删除", @[
            [SPKSetting buttonCellWithTitle:@"删除文件"
                                   subtitle:nil
                                       icon:SPKSettingsIcon(@"trash")
                                     action:^{
                                     }]
        ],
                        nil)
    ];
}

- (instancetype)init {
    return [super initWithTitle:@"图库设置" sections:@[] reduceMargin:NO];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    [self reloadStats];
    [self rebuildSections];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadStats];
    [self rebuildSections];
}

- (void)reloadStats {
    NSManagedObjectContext *ctx = [SPKGalleryCoreDataStack shared].viewContext;
    NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"SPKGalleryFile"];
    NSArray<SPKGalleryFile *> *files = [ctx executeFetchRequest:req error:nil] ?: @[];

    SPKGalleryStorageStats *stats = [SPKGalleryStorageStats new];
    for (SPKGalleryFile *file in files) {
        stats.totalFiles += 1;
        stats.totalSize += file.fileSize;
        if (file.mediaType == SPKGalleryMediaTypeAudio) {
            stats.audioCount += 1;
        } else if (file.mediaType == SPKGalleryMediaTypeVideo) {
            stats.videoCount += 1;
        } else {
            stats.imageCount += 1;
        }
    }
    self.stats = stats;
}

- (NSString *)formattedSize:(long long)bytes {
    return [NSByteCountFormatter stringFromByteCount:bytes countStyle:NSByteCountFormatterCountStyleFile];
}

- (void)rebuildSections {
    NSMutableArray *sections = [NSMutableArray array];

    [sections addObject:SPKTopicSection(@"存储", @[
                  [SPKSetting valueCellWithTitle:@"总计"
                                        subtitle:[NSString stringWithFormat:@"%ld 个文件 • %@", (long)self.stats.totalFiles, [self formattedSize:self.stats.totalSize]]
                                            icon:SPKSettingsIcon(@"info")],
                  [SPKSetting valueCellWithTitle:@"图片"
                                        subtitle:[NSString stringWithFormat:@"%ld", (long)self.stats.imageCount]
                                            icon:SPKSettingsIcon(@"photo")],
                  [SPKSetting valueCellWithTitle:@"视频"
                                        subtitle:[NSString stringWithFormat:@"%ld", (long)self.stats.videoCount]
                                            icon:SPKSettingsIcon(@"video")],
                  [SPKSetting valueCellWithTitle:@"音频"
                                        subtitle:[NSString stringWithFormat:@"%ld", (long)self.stats.audioCount]
                                            icon:SPKSettingsIcon(@"audio")]
              ],
                                        nil)];

    SPKSetting *favoritesRow = [SPKSetting switchCellWithTitle:@"置顶收藏" icon:SPKSettingsIcon(@"heart") defaultsKey:kFavoritesAtTopKey];
    favoritesRow.action = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SPKGalleryFavoritesSortPreferenceChanged" object:nil];
    };

    // Defaults ON; the backing pref stores the *disabled* state, so the switch inverts.
    SPKSetting *pinFolderRow = [SPKSetting switchCellWithTitle:@"固定文件夹栏" icon:SPKSettingsIcon(@"pin") defaultsKey:@""];
    pinFolderRow.switchValueProvider = ^BOOL {
        return ![[NSUserDefaults standardUserDefaults] boolForKey:kSPKGalleryFolderBarPinDisabledKey];
    };
    pinFolderRow.switchChangeHandler = ^(BOOL isOn) {
        [[NSUserDefaults standardUserDefaults] setBool:!isOn forKey:kSPKGalleryFolderBarPinDisabledKey];
        [[NSNotificationCenter defaultCenter] postNotificationName:kSPKGalleryGridControlsChangedNotification object:nil];
    };

    SPKSetting *flatBrowsingRow = [SPKSetting switchCellWithTitle:@"显示子文件夹中的文件" icon:SPKSettingsIcon(@"folder") defaultsKey:kSPKGalleryFlatBrowsingKey];
    flatBrowsingRow.action = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kSPKGalleryBrowsingScopeChangedNotification object:nil];
    };

    [sections addObject:SPKTopicSection(@"浏览",
                                        @[favoritesRow, pinFolderRow, flatBrowsingRow],
                                        @"1. 在当前排序和文件夹范围内，将收藏内容置于其他文件之上。\n"
                                        @"2. 滚动时将子文件夹栏固定在顶部。\n"
                                        @"3. 显示所有文件夹中的文件，而不仅是当前文件夹中的文件。文件夹仍会显示在上方的栏中，并可继续用于筛选列表。")];

    [sections addObject:SPKTopicSection(@"编辑", @[
                  [SPKSetting switchCellWithTitle:@"询问是否替换原文件"
                                             icon:SPKSettingsIcon(@"left_right")
                                      defaultsKey:@"trim_gallery_prompt_replace"]
              ],
                                        @"裁剪或编辑图库项目时，询问是替换原文件还是保存副本。关闭后始终保存副本并保留原文件。")];

    SPKSetting *accountFilterRow = [SPKSetting switchCellWithTitle:@"仅显示此账户" icon:SPKSettingsIcon(@"user_circle") defaultsKey:@"gallery_filter_current_account"];
    __weak typeof(self) weakAccountSelf = self;
    accountFilterRow.action = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SPKGalleryHiddenSourcesDidChangeNotification object:nil];
        if ([SPKUtils getBoolPref:@"gallery_filter_current_account"]) {
            [weakAccountSelf promptClaimUnassignedFiles];
        }
    };

    [sections addObject:SPKTopicSection(@"可见性", @[
                  accountFilterRow,
                  [SPKSetting navigationCellWithTitle:@"隐藏来源"
                                             subtitle:@""
                                                 icon:SPKSettingsIcon(@"eye_off")
                                       viewController:[SPKGalleryHiddenSourcesViewController new]]
              ],
                                        @"1. 仅显示当前账户登录期间保存的媒体，以及较早保存的未分配文件；可以从文件详情页面重新分配文件所属账户。\n"
                                        @"2. 在图库浏览和上传选择器中隐藏指定来源，但不会删除这些文件。")];

    // Grid section: pinch-to-zoom toggle. Defaults ON; the backing pref stores
    // the *disabled* state, so the switch inverts.
    SPKSetting *pinchRow = [SPKSetting switchCellWithTitle:@"双指缩放" icon:SPKSettingsIcon(@"pinch") defaultsKey:@""];
    pinchRow.switchValueProvider = ^BOOL {
        return ![[NSUserDefaults standardUserDefaults] boolForKey:kSPKGalleryGridPinchDisabledKey];
    };
    pinchRow.switchChangeHandler = ^(BOOL isOn) {
        [[NSUserDefaults standardUserDefaults] setBool:!isOn forKey:kSPKGalleryGridPinchDisabledKey];
        [[NSNotificationCenter defaultCenter] postNotificationName:kSPKGalleryGridControlsChangedNotification object:nil];
    };

    SPKSetting *sourceUsernameRow = [SPKSetting switchCellWithTitle:@"显示来源和用户名" icon:SPKSettingsIcon(@"user_circle") defaultsKey:@""];
    sourceUsernameRow.switchValueProvider = ^BOOL {
        return ![[NSUserDefaults standardUserDefaults] boolForKey:kSPKGalleryGridShowSourceUsernameDisabledKey];
    };
    sourceUsernameRow.switchChangeHandler = ^(BOOL isOn) {
        [[NSUserDefaults standardUserDefaults] setBool:!isOn forKey:kSPKGalleryGridShowSourceUsernameDisabledKey];
        [[NSNotificationCenter defaultCenter] postNotificationName:kSPKGalleryGridControlsChangedNotification object:nil];
    };

    [sections addObject:SPKTopicSection(@"网格",
                                        @[ pinchRow, sourceUsernameRow ],
                                        @"1. 双指缩放网格以调整密度（2、3 或 5 列）。\n"
                                        @"2. 在每个网格项目上显示来源图标和用户名；在较低密度下会显示用户名。")];

    [sections addObject:SPKTopicSection(@"预览", @[
                  [SPKSetting switchCellWithTitle:@"显示媒体信息"
                                             icon:SPKSettingsIcon(@"info")
                                      defaultsKey:@"gallery_preview_show_metadata"]
              ],
                                        @"在展开的照片预览中显示用户名、来源以及保存/发布日期。点击媒体可隐藏这些信息和控件。")];

    NSMutableArray *lockRows = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    SPKSetting *lockSwitch =
        [SPKSetting switchCellWithTitle:@"图库密码锁"
                                   icon:SPKSettingsIcon(@"lock")
                            defaultsKey:@""];

    lockSwitch.switchValueProvider = ^BOOL {
        return [SPKGalleryManager sharedManager].isLockEnabled;
    };

    lockSwitch.switchChangeHandler = ^(BOOL isOn) {
        [weakSelf handleLockToggleEnabled:isOn];
    };

    [lockRows addObject:lockSwitch];

    SPKSetting *changePasscode =
        [SPKSetting buttonCellWithTitle:@"更改密码"
                               subtitle:nil
                                   icon:SPKSettingsIcon(@"key")
                                 action:^{
                                     [SPKGalleryLockViewController
                                         presentMode:SPKGalleryLockModeChangePasscode
                                         fromViewController:self
                                         completion:^(BOOL success) {
                                         }];
                                 }];

    changePasscode.enabledProvider = ^BOOL {
        return [SPKGalleryManager sharedManager].isLockEnabled;
    };

    [lockRows addObject:changePasscode];

    [sections addObject:
        SPKTopicSection(@"锁定",
                        lockRows,
                        @"使用密码或生物识别锁定图库。")];

    SPKSetting *importRow =
        [SPKSetting buttonCellWithTitle:@"导入媒体"
                               subtitle:nil
                                   icon:SPKSettingsIcon(@"media")
                                 action:^{
                                     SPKGalleryImportViewController *vc =
                                         [[SPKGalleryImportViewController alloc]
                                             initWithDestinationFolderPath:
                                                 self.importDestinationFolderPath];

                                     [self.navigationController
                                         pushViewController:vc
                                         animated:YES];
                                 }];

    [sections addObject:
        SPKTopicSection(@"导入",
                        @[ importRow ],
                        @"从“文件”App 导入媒体，并完整编辑媒体信息。\n"
                         @"如果来自 Regram，可在这里选择导出的文件夹或 MediaVault.zip，以导入整个 Media Vault。")];

    SPKSetting *deleteRow =
        [SPKSetting buttonCellWithTitle:@"删除文件"
                               subtitle:nil
                                   icon:SPKSettingsIcon(@"trash")
                                 action:^{
                                     SPKGalleryDeleteViewController *vc =
                                         [[SPKGalleryDeleteViewController alloc]
                                             initWithMode:
                                                 SPKGalleryDeletePageModeRoot];

                                     __weak typeof(self) weakSelf = self;

                                     vc.onDidDelete = ^{
                                         [weakSelf reloadStats];
                                         [weakSelf rebuildSections];

                                         [[NSNotificationCenter defaultCenter]
                                             postNotificationName:
                                                 @"SPKGalleryFavoritesSortPreferenceChanged"
                                             object:nil];
                                     };

                                     [self.navigationController
                                         pushViewController:vc
                                         animated:YES];
                                 }];

    deleteRow.tintColor =
        [SPKUtils SPKColor_InstagramDestructive];

    deleteRow.iconTintColor =
        [SPKUtils SPKColor_InstagramDestructive];

    [sections addObject:
        SPKTopicSection(@"删除",
                        @[ deleteRow ],
                        nil)];

    [self replaceSections:sections];
    }

    - (void)promptClaimUnassignedFiles {
        NSString *pk = [SPKAccountManager currentAccountPK];
        if (pk.length == 0)
            return;

        NSUInteger count = [SPKGalleryFile unassignedFileCount];
        if (count == 0)
            return;

        NSString *username =
            [SPKAccountManager currentAccountUsername];

        NSString *who =
            username.length > 0
                ? [@"@" stringByAppendingString:username]
                : @"此账号";

        NSString *message =
            [NSString stringWithFormat:
                @"%lu 个现有文件没有分配账号，因此不会显示在“仅此账号”中。要将 %@ 分配给 %@？",
                (unsigned long)count,
                count == 1 ? @"该文件" : @"这些文件",
                who];

        [SPKIGAlertPresenter
            presentAlertFromViewController:self
            title:@"认领现有文件？"
            message:message
            actions:@[
                [SPKIGAlertAction
                    actionWithTitle:@"暂不"
                    style:SPKIGAlertActionStyleCancel
                    handler:nil],

                [SPKIGAlertAction
                    actionWithTitle:@"分配"
                    style:SPKIGAlertActionStyleDefault
                    handler:^{
                        [SPKGalleryFile
                            claimUnassignedFilesForAccountPK:pk
                            username:username];

                        [[NSNotificationCenter defaultCenter]
                            postNotificationName:
                                SPKGalleryHiddenSourcesDidChangeNotification
                            object:nil];
                    }]
            ]];
    }

    - (void)handleLockToggleEnabled:(BOOL)enabled {
        SPKGalleryManager *mgr =
            [SPKGalleryManager sharedManager];

        if (enabled && !mgr.isLockEnabled) {
            __weak typeof(self) weakSelf = self;

            [SPKGalleryLockViewController
                presentMode:SPKGalleryLockModeSetPasscode
                fromViewController:self
                completion:^(BOOL success) {
                    [weakSelf rebuildSections];
                }];

            return;
        }

        if (enabled && mgr.isLockEnabled) {
            [self rebuildSections];
            return;
        }

        if (!enabled && !mgr.isLockEnabled) {
            [self rebuildSections];
            return;
        }

        [SPKIGAlertPresenter
            presentAlertFromViewController:self
            title:@"禁用密码"
            message:
                @"图库将不再要求身份验证即可打开。"
            actions:@[
                [SPKIGAlertAction
                    actionWithTitle:@"取消"
                    style:SPKIGAlertActionStyleCancel
                    handler:^{
                        [self rebuildSections];
                    }],

                [SPKIGAlertAction
                    actionWithTitle:@"禁用"
                    style:SPKIGAlertActionStyleDestructive
                    handler:^{
                        [mgr removePasscode];
                        [self rebuildSections];
                    }]
            ]];
    }

    @end
