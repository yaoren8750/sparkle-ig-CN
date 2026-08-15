#import "SPKDownloadsSettingsProvider.h"
#import <UIKit/UIKit.h>

#import "../../Shared/Downloads/SPKDownloadsHistoryViewController.h"
#import "../../Shared/Downloads/SPKDownloadsSettingsViewController.h"
#import "../../Utils.h"
#import "../SPKSetting.h"
#import "../SPKTopicSettingsSupport.h"

@implementation SPKDownloadsSettingsProvider

+ (SPKSetting *)rootSetting {
    // Opens straight into the download history — the in-screen gear button leads
    // to the download settings. The settings sections are still surfaced to
    // settings search via the provider below.
    SPKSetting *setting = [SPKSetting navigationCellWithTitle:@"下载"
                                                     subtitle:@""
                                                         icon:SPKSettingsIcon(@"download")
                                               viewController:[SPKDownloadsHistoryViewController new]];
    setting.searchKeywords = @"downloads history queue retry cancel duplicate parallel concurrent quality encoding ffmpeg audio resolution";
    setting.searchSectionsProvider = ^NSArray * {
        return [SPKDownloadsSettingsViewController searchSections];
    };
    return SPKSettingApplyIconTint(setting, [SPKUtils SPKColor_InstagramPrimaryText]);
}

@end
