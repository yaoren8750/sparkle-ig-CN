#import "SPKDeletedMessagesStorageViewController.h"

#import "../../../Settings/SPKTopicSettingsSupport.h"
#import "../../../Shared/UI/SPKIGAlertPresenter.h"
#import "../../../Utils.h"
#import "SPKDeletedMessagesModels.h"
#import "SPKDeletedMessagesStorage.h"

@interface SPKDeletedMessagesStorageViewController ()
@property (nonatomic, copy) NSString *ownerPK;
@property (nonatomic, assign) NSUInteger messageCount;
@property (nonatomic, assign) NSUInteger senderCount;
@property (nonatomic, assign) NSUInteger textCount;
@property (nonatomic, assign) NSUInteger mediaCount;
@property (nonatomic, assign) NSUInteger voiceCount;
@property (nonatomic, assign) NSUInteger otherCount;
@property (nonatomic, assign) unsigned long long mediaBytes;
@property (nonatomic, assign) unsigned long long stagedMediaBytes;
@end

@implementation SPKDeletedMessagesStorageViewController

static NSString *SPKDMStorageOwnerPK(void) {
    @try {
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            id session = nil;
            @try {
                session = [window valueForKey:@"userSession"];
            } @catch (__unused id e) {
            }
            id user = nil;
            @try {
                user = [session valueForKey:@"user"];
            } @catch (__unused id e) {
            }
            for (NSString *key in @[ @"pk", @"instagramUserID", @"instagramUserId", @"userID", @"userId" ]) {
                id value = nil;
                @try {
                    value = [user valueForKey:key];
                } @catch (__unused id e) {
                }
                if ([value isKindOfClass:NSString.class] && [value length])
                    return value;
                if ([value isKindOfClass:NSNumber.class])
                    return [value stringValue];
            }
        }
    } @catch (__unused id e) {
    }
    NSArray<NSString *> *owners = [SPKDeletedMessagesStorage allOwnerPKs];
    return owners.firstObject ?: @"anon";
}

- (instancetype)init {
    return [super initWithTitle:@"Storage" sections:@[] reduceMargin:NO];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadStatsAndRebuild) name:SPKDeletedMessagesDidChangeNotification object:nil];
    [self reloadStatsAndRebuild];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadStatsAndRebuild];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reloadStatsAndRebuild {
    [self reloadStats];
    [self rebuildSections];
}

- (void)reloadStats {
    self.ownerPK = SPKDMStorageOwnerPK();
    NSArray<SPKDeletedMessage *> *messages = [SPKDeletedMessagesStorage allMessagesForOwnerPK:self.ownerPK];
    self.messageCount = messages.count;

    NSMutableSet<NSString *> *senders = [NSMutableSet set];
    NSUInteger text = 0, media = 0, voice = 0, other = 0;
    for (SPKDeletedMessage *message in messages) {
        if (message.senderPk.length)
            [senders addObject:message.senderPk];
        switch (message.kind) {
        case SPKDeletedMessageKindText:
            text++;
            break;
        case SPKDeletedMessageKindPhoto:
        case SPKDeletedMessageKindVideo:
        case SPKDeletedMessageKindGif:
        case SPKDeletedMessageKindSticker:
            media++;
            break;
        case SPKDeletedMessageKindVoice:
        case SPKDeletedMessageKindAudioShare:
            voice++;
            break;
        default:
            other++;
            break;
        }
    }
    self.senderCount = senders.count;
    self.textCount = text;
    self.mediaCount = media;
    self.voiceCount = voice;
    self.otherCount = other;
    self.mediaBytes = [SPKDeletedMessagesStorage mediaSizeBytesForOwnerPK:self.ownerPK];
    self.stagedMediaBytes = [SPKDeletedMessagesStorage stagedMediaSizeBytesForOwnerPK:self.ownerPK];
}

- (NSString *)formattedSize:(unsigned long long)bytes {
    return [NSByteCountFormatter stringFromByteCount:(long long)bytes countStyle:NSByteCountFormatterCountStyleFile];
}

- (void)rebuildSections {
    NSMutableArray *sections = [NSMutableArray array];

    unsigned long long totalDisk = self.mediaBytes + self.stagedMediaBytes;
    NSString *overviewSubtitle = [NSString stringWithFormat:@"%lu message%@ • %lu sender%@ • %@",
                                                            (unsigned long)self.messageCount, self.messageCount == 1 ? @"" : @"s",
                                                            (unsigned long)self.senderCount, self.senderCount == 1 ? @"" : @"s",
                                                            [self formattedSize:totalDisk]];

    [sections addObject:SPKTopicSection(@"Overview", @[
                  [SPKSetting valueCellWithTitle:@"Logged"
                                        subtitle:overviewSubtitle
                                            icon:SPKSettingsIcon(@"history")],
              ],
                                        nil)];

    NSMutableArray *breakdown = [NSMutableArray array];
    [breakdown addObject:[SPKSetting valueCellWithTitle:@"Text" subtitle:[NSString stringWithFormat:@"%lu", (unsigned long)self.textCount] icon:SPKSettingsIcon(@"message")]];
    [breakdown addObject:[SPKSetting valueCellWithTitle:@"Photos & Videos" subtitle:[NSString stringWithFormat:@"%lu", (unsigned long)self.mediaCount] icon:SPKSettingsIcon(@"photo")]];
    [breakdown addObject:[SPKSetting valueCellWithTitle:@"Voice & Audio" subtitle:[NSString stringWithFormat:@"%lu", (unsigned long)self.voiceCount] icon:SPKSettingsIcon(@"microphone")]];
    if (self.otherCount > 0) {
        [breakdown addObject:[SPKSetting valueCellWithTitle:@"Other" subtitle:[NSString stringWithFormat:@"%lu", (unsigned long)self.otherCount] icon:SPKSettingsIcon(@"messages")]];
    }
    [sections addObject:SPKTopicSection(@"消息", breakdown, nil)];

    [sections addObject:SPKTopicSection(@"Disk Usage", @[
                  [SPKSetting valueCellWithTitle:@"Captured Media"
                                        subtitle:[self formattedSize:self.mediaBytes]
                                            icon:SPKSettingsIcon(@"media")],
                  [SPKSetting valueCellWithTitle:@"Media Recovery Cache"
                                        subtitle:[self formattedSize:self.stagedMediaBytes]
                                            icon:SPKSettingsIcon(@"clock")],
              ],
                                        @"View-once, view-twice, GIF, and sticker media is cached on-device before an unsend so it remains recoverable. It is excluded from deleted-message exports until the message is unsent. Cached profile pictures are shared across Sparkle — manage them in Data & Settings › Storage.")];

    __weak typeof(self) weakSelf = self;

    SPKSetting *clearMedia = [SPKSetting buttonCellWithTitle:@"Clear Captured Media"
                                                    subtitle:nil
                                                        icon:SPKSettingsIcon(@"media")
                                                      action:^{
                                                          [weakSelf confirmClearMedia];
                                                      }];
    clearMedia.tintColor = [SPKUtils SPKColor_InstagramDestructive];
    clearMedia.iconTintColor = [SPKUtils SPKColor_InstagramDestructive];

    SPKSetting *clearStaged = [SPKSetting buttonCellWithTitle:@"Clear Media Recovery Cache"
                                                     subtitle:nil
                                                         icon:SPKSettingsIcon(@"clock")
                                                       action:^{
                                                           [weakSelf confirmClearStagedMedia];
                                                       }];
    clearStaged.tintColor = [SPKUtils SPKColor_InstagramDestructive];
    clearStaged.iconTintColor = [SPKUtils SPKColor_InstagramDestructive];

    SPKSetting *clearLog = [SPKSetting buttonCellWithTitle:@"Clear Entire Log"
                                                  subtitle:nil
                                                      icon:SPKSettingsIcon(@"trash")
                                                    action:^{
                                                        [weakSelf confirmClearLog];
                                                    }];
    clearLog.tintColor = [SPKUtils SPKColor_InstagramDestructive];
    clearLog.iconTintColor = [SPKUtils SPKColor_InstagramDestructive];

    [sections addObject:SPKTopicSection(@"Maintenance", @[ clearMedia, clearStaged, clearLog ],
                                        @"Clearing the media recovery cache keeps lightweight message metadata for best-effort fallback after a future unsend. Clearing the log does not clear the recovery cache.")];

    [self replaceSections:sections];
}

#pragma mark - Actions

- (void)confirmClearMedia {
    [SPKIGAlertPresenter presentAlertFromViewController:self
                                                  title:@"清除已捕获媒体？"
                                                message:@"这将删除所有已捕获的媒体（照片、视频、语音消息），但会保留消息记录。"
                                                actions:@[
                                                    [SPKIGAlertAction actionWithTitle:@"取消"
                                                                                style:SPKIGAlertActionStyleCancel
                                                                              handler:nil],
                                                    [SPKIGAlertAction actionWithTitle:@"Clear Media"
                                                                                style:SPKIGAlertActionStyleDestructive
                                                                              handler:^{
                                                                                  for (SPKDeletedMessage *message in [SPKDeletedMessagesStorage allMessagesForOwnerPK:self.ownerPK]) {
                                                                                      NSString *media = [SPKDeletedMessagesStorage absolutePathForRelativePath:message.mediaPath ownerPK:self.ownerPK];
                                                                                      NSString *thumb = [SPKDeletedMessagesStorage absolutePathForRelativePath:message.thumbnailPath ownerPK:self.ownerPK];
                                                                                      if (media.length)
                                                                                          [NSFileManager.defaultManager removeItemAtPath:media error:nil];
                                                                                      if (thumb.length)
                                                                                          [NSFileManager.defaultManager removeItemAtPath:thumb error:nil];
                                                                                      message.mediaPath = nil;
                                                                                      message.thumbnailPath = nil;
                                                                                      [SPKDeletedMessagesStorage saveMessage:message forOwnerPK:self.ownerPK];
                                                                                  }
                                                                                  [self reloadStatsAndRebuild];
                                                                              }],
                                                ]];
}

- (void)confirmClearLog {
    [SPKIGAlertPresenter presentAlertFromViewController:self
                                                  title:@"清除全部记录？"
                                                message:@"这将删除当前账户的所有已删除消息记录和已捕获媒体。"
                                                actions:@[
                                                    [SPKIGAlertAction actionWithTitle:@"取消"
                                                                                style:SPKIGAlertActionStyleCancel
                                                                              handler:nil],
                                                    [SPKIGAlertAction actionWithTitle:@"清除"
                                                                                style:SPKIGAlertActionStyleDestructive
                                                                              handler:^{
                                                                                  [SPKDeletedMessagesStorage resetForOwnerPK:self.ownerPK];
                                                                                  [self reloadStatsAndRebuild];
                                                                              }],
                                                ]];
}

- (void)confirmClearStagedMedia {
    [SPKIGAlertPresenter presentAlertFromViewController:self
                                                  title:@"清除媒体恢复缓存？"
                                                message:@"This removes pre-cached view-once, view-twice, GIF, and sticker media. Lightweight metadata remains so Sparkle can still attempt a best-effort download after a future unsend."
                                                actions:@[
                                                    [SPKIGAlertAction actionWithTitle:@"取消"
                                                                                style:SPKIGAlertActionStyleCancel
                                                                              handler:nil],
                                                    [SPKIGAlertAction actionWithTitle:@"Clear Media"
                                                                                style:SPKIGAlertActionStyleDestructive
                                                                              handler:^{
                                                                                  [SPKDeletedMessagesStorage clearStagedMediaForOwnerPK:self.ownerPK];
                                                                                  [self reloadStatsAndRebuild];
                                                                              }],
                                                ]];
}

@end
