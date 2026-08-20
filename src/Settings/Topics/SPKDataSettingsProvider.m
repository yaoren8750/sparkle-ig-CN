#import "SPKDataSettingsProvider.h"
#import <UIKit/UIKit.h>

#import "../../AssetUtils.h"
#import "../../Utils.h"
#import "../SPKSettingsTransferManager.h"
#import "../SPKStorageUsageViewController.h"
#import "../SPKTopicSettingsSupport.h"

#pragma mark - Export / Import selection

@interface SPKSettingsTransferSelectionViewController : SPKSettingsViewController
@property (nonatomic, assign) BOOL importMode;
@property (nonatomic, assign) BOOL includeSettings;
@property (nonatomic, assign) BOOL includeGallery;
@property (nonatomic, assign) BOOL includeDeletedMessages;
@property (nonatomic, assign) BOOL includeProfileAnalyzer;
- (instancetype)initWithImportMode:(BOOL)importMode;
@end

@implementation SPKSettingsTransferSelectionViewController

- (instancetype)initWithImportMode:(BOOL)importMode {
    if ((self = [super initWithTitle:(importMode ? @"Import" : @"Export") sections:@[] reduceMargin:NO])) {
        _importMode = importMode;
        _includeSettings = YES;
        _includeGallery = YES;
        _includeDeletedMessages = YES;
        _includeProfileAnalyzer = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupTransferActionItem];
    [self rebuildSections];
    [self updateActionEnabled];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self setupTransferActionItem];
    [self updateActionEnabled];
}

- (void)setupTransferActionItem {
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[SPKAssetUtils instagramIconNamed:(self.importMode ? @"arrow_down" : @"arrow_up")]
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(runTransfer)];
    self.navigationItem.rightBarButtonItem.tintColor = [SPKUtils SPKColor_InstagramPrimaryText];
}

- (void)rebuildSections {
    SPKSetting *settingsRow = [SPKSetting buttonCellWithTitle:@"设置"
                                                     subtitle:@""
                                                         icon:SPKSettingsIcon(@"settings")
                                                       action:^{
        self.includeSettings = !self.includeSettings;
        [self rebuildSections];
        [self updateActionEnabled];
    }];
    settingsRow.userInfo = @{@"checkmarked" : @(self.includeSettings)};
    
    SPKSetting *galleryRow = [SPKSetting buttonCellWithTitle:@"图库"
                                                    subtitle:@""
                                                        icon:SPKSettingsIcon(@"sparkle_gallery")
                                                      action:^{
        self.includeGallery = !self.includeGallery;
        [self rebuildSections];
        [self updateActionEnabled];
    }];
    galleryRow.userInfo = @{@"checkmarked" : @(self.includeGallery)};
    
    SPKSetting *deletedMessagesRow = [SPKSetting buttonCellWithTitle:@"已删除消息"
                                                            subtitle:@""
                                                                icon:SPKSettingsIcon(@"channels")
                                                              action:^{
        self.includeDeletedMessages = !self.includeDeletedMessages;
        [self rebuildSections];
        [self updateActionEnabled];
    }];
    deletedMessagesRow.userInfo = @{@"checkmarked" : @(self.includeDeletedMessages)};
    
    SPKSetting *profileAnalyzerRow = [SPKSetting buttonCellWithTitle:@"个人资料分析"
                                                            subtitle:@""
                                                                icon:SPKSettingsIcon(@"profile_analyzer")
                                                              action:^{
        self.includeProfileAnalyzer = !self.includeProfileAnalyzer;
        [self rebuildSections];
        [self updateActionEnabled];
    }];
    profileAnalyzerRow.userInfo = @{
        @"checkmarked" : @(self.includeProfileAnalyzer)
    };
    
    NSString *footer = self.importMode
    ? @"正在恢复偏好设置，将替换当前导入范围内的设置值。图库、已删除消息和个人资料分析数据将进行合并——现有项目不会被删除。仅当偏好设置发生变化时才会提示重启。"
    : nil;
    
    NSArray *sections = @[
        SPKTopicSection(
        @"",
        @[ settingsRow, galleryRow, deletedMessagesRow, profileAnalyzerRow ],
        footer
        )
    ];
    
    [self replaceSections:sections];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    SPKSetting *row = self.sections[indexPath.section][@"rows"][indexPath.row];
    if (row.userInfo[@"checkmarked"]) {
        BOOL checked = [row.userInfo[@"checkmarked"] boolValue];
        if (checked) {
            UIImageView *checkmarkView = [[UIImageView alloc] initWithImage:[SPKAssetUtils instagramIconNamed:@"circle_check_filled"]];
            checkmarkView.tintColor = [SPKUtils SPKColor_InstagramBlue];
            cell.accessoryView = checkmarkView;
        } else {
            cell.accessoryView = nil;
            cell.accessoryType = UITableViewCellAccessoryNone;
        }
    }
    return cell;
}

- (void)updateActionEnabled {
    self.navigationItem.rightBarButtonItem.enabled = self.includeSettings || self.includeGallery || self.includeDeletedMessages || self.includeProfileAnalyzer;
}

- (void)runTransfer {
    if (!(self.includeSettings || self.includeGallery || self.includeDeletedMessages || self.includeProfileAnalyzer))
        return;
    UIViewController *presenter = self.navigationController ?: self;
    if (self.importMode) {
        [[SPKSettingsTransferManager sharedManager] importFromController:presenter includeSettings:self.includeSettings includeGallery:self.includeGallery includeDeletedMessages:self.includeDeletedMessages includeProfileAnalyzer:self.includeProfileAnalyzer];
    } else {
        [[SPKSettingsTransferManager sharedManager] exportFromController:presenter includeSettings:self.includeSettings includeGallery:self.includeGallery includeDeletedMessages:self.includeDeletedMessages includeProfileAnalyzer:self.includeProfileAnalyzer];
    }
}

@end

#pragma mark - Provider

@implementation SPKDataSettingsProvider

+ (SPKSetting *)rootSetting {
    SPKSetting *resetAllSettings = [SPKSetting buttonCellWithTitle:@"重置所有设置"
                                                          subtitle:@""
                                                              icon:SPKSettingsIcon(@"arrow_ccw")
                                                            action:^(void) {
                                                                UIWindowScene *scene = (UIWindowScene *)UIApplication.sharedApplication.connectedScenes.anyObject;
                                                                UIViewController *presenter = scene.windows.firstObject.rootViewController;
                                                                while (presenter.presentedViewController)
                                                                    presenter = presenter.presentedViewController;
                                                                [[SPKSettingsTransferManager sharedManager] resetAllSettingsFromController:presenter];
                                                            }];
    resetAllSettings.tintColor = [SPKUtils SPKColor_InstagramDestructive];
    resetAllSettings.iconTintColor = [SPKUtils SPKColor_InstagramDestructive];

    NSArray *sections = @[
        SPKTopicSection(@"存储", @[
            [SPKSetting navigationCellWithTitle:@"存储使用情况"
                                       subtitle:@""
                                           icon:SPKSettingsIcon(@"info")
                                 viewController:[SPKStorageUsageViewController new]]
        ],
                        @"查看 Sparkle 各项功能占用的设备存储空间。"),

        SPKTopicSection(@"备份与传输", @[
            SPKSettingApplyIconTint(
                [SPKSetting navigationCellWithTitle:@"导出"
                                           subtitle:@""
                                               icon:SPKSettingsIcon(@"arrow_up")
                                     viewController:
                                         [[SPKSettingsTransferSelectionViewController alloc]
                                             initWithImportMode:NO]],
                [SPKUtils SPKColor_InstagramPrimaryText]
            ),

            SPKSettingApplyIconTint(
                [SPKSetting navigationCellWithTitle:@"导入"
                                           subtitle:@""
                                               icon:SPKSettingsIcon(@"arrow_down")
                                     viewController:
                                         [[SPKSettingsTransferSelectionViewController alloc]
                                             initWithImportMode:YES]],
                [SPKUtils SPKColor_InstagramPrimaryText]
            )
        ],
                        @"选择导出或导入设置、图库媒体、已删除消息和个人资料分析数据。"),

        SPKTopicSection(@"重置", @[
            resetAllSettings
        ],
                        @"将所有偏好设置恢复为默认值。")
    ];

    return SPKTopicNavigationSetting(@"数据与设置", @"cloud", 24.0, sections);
    }

    @end
