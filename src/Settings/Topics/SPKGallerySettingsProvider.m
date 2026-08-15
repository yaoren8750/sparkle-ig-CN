#import "SPKGallerySettingsProvider.h"
#import "../SPKSetting.h"
#import "../SPKTopicSettingsSupport.h"

#import "../../Shared/Gallery/SPKGallerySettingsViewController.h"
#import "../../Shared/Gallery/SPKGalleryViewController.h"
#import "../../Utils.h"

@implementation SPKGallerySettingsProvider

+ (SPKSetting *)rootSetting {
    SPKSetting *gallerySettings = [SPKSetting navigationCellWithTitle:@"Gallery Settings"
                                                             subtitle:nil
                                                                 icon:SPKSettingsIcon(@"settings")
                                                       viewController:[[SPKGallerySettingsViewController alloc] init]];
    gallerySettings.searchSectionsProvider = ^NSArray * {
        return [SPKGallerySettingsViewController searchSections];
    };

    return SPKTopicNavigationSetting(@"图库", @"sparkle_gallery", 24.0, @[
        SPKTopicSection(@"Access", @[
            [SPKSetting buttonCellWithTitle:@"Open Gallery"
                                   subtitle:@""
                                       icon:SPKSettingsIcon(@"sparkle_gallery")
                                     action:^(void) {
                                         [SPKGalleryViewController presentGallery];
                                     }],
            SPKSettingApplySelectedMenuIcon([SPKSetting menuCellWithTitle:@"Quick Gallery Access" icon:SPKSettingsIcon(@"circle_off") menu:SPKGalleryShortcutTargetMenu()], SPKSettingsIcon(@"circle_off"))
        ],
                        @"Choose the tab that opens Gallery on long press. None disables the action."),
        SPKTopicSection(@"设置", @[
            gallerySettings
        ],
                        @"The same screen you reach from inside Gallery.")
    ]);
}

@end
