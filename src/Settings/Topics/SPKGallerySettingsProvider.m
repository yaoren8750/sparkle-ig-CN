#import "SPKGallerySettingsProvider.h"
#import "../SPKSetting.h"
#import "../SPKTopicSettingsSupport.h"

#import "../../Shared/Gallery/SPKGallerySettingsViewController.h"
#import "../../Shared/Gallery/SPKGalleryViewController.h"
#import "../../Utils.h"

@implementation SPKGallerySettingsProvider

+ (SPKSetting *)rootSetting {
    SPKSetting *gallerySettings = [SPKSetting navigationCellWithTitle:@"图库设置"
                                                             subtitle:nil
                                                                 icon:SPKSettingsIcon(@"settings")
                                                       viewController:[[SPKGallerySettingsViewController alloc] init]];
    gallerySettings.searchSectionsProvider = ^NSArray * {
        return [SPKGallerySettingsViewController searchSections];
    };

    return SPKTopicNavigationSetting(@"图库", @"sparkle_gallery", 24.0, @[
        SPKTopicSection(@"访问", @[
            [SPKSetting buttonCellWithTitle:@"打开图库"
                                   subtitle:@""
                                       icon:SPKSettingsIcon(@"sparkle_gallery")
                                     action:^(void) {
                                         [SPKGalleryViewController presentGallery];
                                     }],
            SPKSettingApplySelectedMenuIcon([SPKSetting menuCellWithTitle:@"快速访问图库" icon:SPKSettingsIcon(@"circle_off") menu:SPKGalleryShortcutTargetMenu()], SPKSettingsIcon(@"circle_off"))
        ],
                        @"选择长按时打开图库的标签页。选择“无”可禁用此操作。"),
        SPKTopicSection(@"设置", @[
            gallerySettings
        ],
                        @"与从图库内部进入的界面相同。")
    ]);
}

@end
