#import "SPKAutoSaveSettingsViewController.h"

#import "../../Settings/SPKSetting.h"
#import "../../Settings/SPKTopicSettingsSupport.h"
#import "../../Utils.h"
#import "../Instants/SPKInstantsAutoSave.h"
#import "../MediaDownload/SPKMediaFFmpeg.h"
#import "../Messages/SPKDirectAutoSave.h"
#import "../Stories/SPKStoryAutoSave.h"
#import "SPKAutoSave.h"
#import "SPKAutoSaveStoriesSettingsViewController.h"

@implementation SPKAutoSaveSettingsViewController

+ (NSDictionary *)destinationSection {
    BOOL toPhotos = SPKAutoSaveDestination() == SPKDownloadDestinationPhotos;
    SPKSetting *destination = [SPKSetting menuCellWithTitle:@"Save To"
                                                       icon:SPKSettingsIcon(toPhotos ? @"photo_gallery" : @"sparkle_gallery")
                                                       menu:SPKAutoSaveDestinationMenu()];

    return SPKTopicSection(@"Destination", @[ destination ],
                           @"Where auto-saved media lands, for every surface. Sparkle Gallery keeps it inside the tweak. "
                           @"Photos App saves it to your photo library, which iOS asks permission for the first time. "
                           @"Each destination is tracked separately, so switching saves items the other one already has.");
}

+ (NSDictionary *)qualitySection {
    BOOL ffmpegAvailable = [SPKMediaFFmpeg isAvailable];

    SPKSetting *videoQuality = [SPKSetting menuCellWithTitle:@"Video Quality"
                                                    subtitle:(ffmpegAvailable ? @"" : @"Requires FFmpegKit")
                                                        icon:SPKSettingsIcon(@"video")
                                                        menu:SPKAutoSaveVideoQualityMenu()];
    videoQuality.userInfo = @{@"enabled" : @(ffmpegAvailable)};

    return SPKTopicSection(@"Quality", @[
        [SPKSetting menuCellWithTitle:@"Photo Quality"
                                 icon:SPKSettingsIcon(@"photo")
                                 menu:SPKAutoSavePhotoQualityMenu()],
        videoQuality,
    ],
                           @"1. Preferred quality for auto-saved photos.\n"
                           @"2. \"Default\" takes Instagram's ready-to-play file, which is fastest and re-encodes nothing. "
                           @"\"High\" merges DASH video and audio for the best quality, at the cost of an FFmpeg pass for "
                           @"every item saved. Auto-save never prompts, so there is no \"Always Ask\".");
}

+ (NSDictionary *)feedbackSection {
    return SPKTopicSection(@"History", @[
        [SPKSetting switchCellWithTitle:@"Keep in Download History"
                                   icon:SPKSettingsIcon(@"history")
                            defaultsKey:kSPKAutoSaveKeepHistoryKey],
    ],
                           @"Auto-saves are removed from the download history once saved. Enable to keep them listed. "
                           @"Every auto-save toast is configured under Notifications, in its own Auto-Save section.");
}

+ (SPKSetting *)surfaceRowWithTitle:(NSString *)title
                               icon:(NSString *)icon
                            summary:(NSString *)summary
                     surfaceClass:(Class)surfaceClass {
    SPKSetting *row = [SPKSetting navigationCellWithTitle:title
                                                 subtitle:@""
                                                     icon:SPKSettingsIcon(icon)
                                           viewController:[[surfaceClass alloc] init]];
    row.userInfo = @{@"accessoryText" : summary};
    row.searchSectionsProvider = ^NSArray * {
        return [surfaceClass searchSections];
    };
    return row;
}

+ (NSDictionary *)surfacesSection {
    return SPKTopicSection(@"Surfaces", @[
        [self surfaceRowWithTitle:@"快拍"
                             icon:@"story"
                          summary:SPKStoryAutoSaveSettingsSummary()
                     surfaceClass:[SPKAutoSaveStoriesSettingsViewController class]],
        [self surfaceRowWithTitle:@"消息"
                             icon:@"messages"
                          summary:SPKDirectAutoSaveSettingsSummary()
                     surfaceClass:[SPKAutoSaveMessagesSettingsViewController class]],
        [self surfaceRowWithTitle:@"Instants"
                             icon:@"instants"
                          summary:SPKInstantsAutoSaveSettingsSummary()
                     surfaceClass:[SPKAutoSaveInstantsSettingsViewController class]],
    ],
                           nil);
}

+ (NSArray *)contentSections {
    return @[
        [self surfacesSection],
        [self destinationSection],
        [self qualitySection],
        [self feedbackSection],
    ];
}

+ (NSArray *)searchSections {
    return [self contentSections];
}

- (instancetype)init {
    return [super initWithTitle:@"Auto-Save" sections:[[self class] contentSections] reduceMargin:NO];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Refresh the per-surface summary accessory after editing a surface page.
    [self replaceSections:[[self class] contentSections]];
}

- (void)menuChanged:(UICommand *)command {
    [super menuChanged:command];
    // The Save To row's icon reflects the destination, so the row has to be rebuilt --
    // the built-in path only full-rebuilds pages that have hiddenProvider rows.
    if ([command.propertyList[@"defaultsKey"] isEqualToString:kSPKAutoSaveDestinationKey])
        [self replaceSections:[[self class] contentSections]];
}

@end
