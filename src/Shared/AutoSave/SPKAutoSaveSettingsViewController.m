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
  SPKSetting *destination = [SPKSetting menuCellWithTitle:@"保存到"
  icon:SPKSettingsIcon(toPhotos ? @"photo_gallery" : @"sparkle_gallery")
  menu:SPKAutoSaveDestinationMenu()];

  return SPKTopicSection(@"保存位置", @[ destination ],
  @"自动保存的媒体将保存到这里，适用于所有来源。Sparkle Gallery 会将内容保存在插件内。"
  @"照片 App 会将内容保存到你的照片图库，首次使用时 iOS 会请求权限。"
  @"每个保存位置都会单独记录，因此切换保存位置后，不会重复保存之前已经保存过的内容。");
  }

+ (NSDictionary *)qualitySection {
  BOOL ffmpegAvailable = [SPKMediaFFmpeg isAvailable];

  SPKSetting *videoQuality = [SPKSetting menuCellWithTitle:@"视频质量"
  subtitle:(ffmpegAvailable ? @"" : @"需要 FFmpegKit")
  icon:SPKSettingsIcon(@"video")
  menu:SPKAutoSaveVideoQualityMenu()];
  videoQuality.userInfo = @{@"enabled" : @(ffmpegAvailable)};

  return SPKTopicSection(@"质量", @[
  [SPKSetting menuCellWithTitle:@"照片质量"
  icon:SPKSettingsIcon(@"photo")
  menu:SPKAutoSavePhotoQualityMenu()],
  videoQuality,
  ],
  @"1. 设置自动保存照片时使用的质量。\n"
  @"2. “默认”使用 Instagram 已准备好的可播放文件，速度最快且不会重新编码。"
  @"“高”会合并 DASH 视频和音频，以获得最佳质量，但每次保存都需要经过 FFmpeg 处理。"
  @"自动保存不会询问，因此没有“始终询问”选项。");
  }

+ (NSDictionary *)feedbackSection {
  return SPKTopicSection(@"历史记录", @[
  [SPKSetting switchCellWithTitle:@"保留在下载历史记录中"
  icon:SPKSettingsIcon(@"history")
  defaultsKey:kSPKAutoSaveKeepHistoryKey],
  ],
  @"自动保存的内容保存完成后会从下载历史记录中移除。开启后会继续保留在历史记录中。"
  @"每次自动保存的提示都可以在“通知”中的“自动保存”部分单独设置。");
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
  return SPKTopicSection(@"内容来源", @[
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
  return [super initWithTitle:@"自动保存" sections:[[self class] contentSections] reduceMargin:NO];
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
