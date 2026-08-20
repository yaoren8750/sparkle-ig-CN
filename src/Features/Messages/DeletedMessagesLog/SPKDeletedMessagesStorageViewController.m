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
    return [super initWithTitle:@"存储" sections:@[] reduceMargin:NO];
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
    NSString *overviewSubtitle = [NSString stringWithFormat:@"%lu 条消息 • %lu 位用户 • %@",
                                  (unsigned long)self.messageCount,
                                  (unsigned long)self.senderCount,
                                  [self formattedSize:totalDisk]];

    [sections addObject:SPKTopicSection(@"概览", @[
                  [SPKSetting valueCellWithTitle:@"已记录"
                                        subtitle:overviewSubtitle
                                            icon:SPKSettingsIcon(@"history")],
              ],
                                        nil)];

    NSMutableArray *breakdown = [NSMutableArray array];
    [breakdown addObject:[SPKSetting valueCellWithTitle:@"文字" subtitle:[NSString stringWithFormat:@"%lu", (unsigned long)self.textCount] icon:SPKSettingsIcon(@"message")]];
    [breakdown addObject:[SPKSetting valueCellWithTitle:@"照片和视频" subtitle:[NSString stringWithFormat:@"%lu", (unsigned long)self.mediaCount] icon:SPKSettingsIcon(@"photo")]];
    [breakdown addObject:[SPKSetting valueCellWithTitle:@"语音和音频" subtitle:[NSString stringWithFormat:@"%lu", (unsigned long)self.voiceCount] icon:SPKSettingsIcon(@"microphone")]];
    if (self.otherCount > 0) {
        [breakdown addObject:[SPKSetting valueCellWithTitle:@"其他" subtitle:[NSString stringWithFormat:@"%lu", (unsigned long)self.otherCount] icon:SPKSettingsIcon(@"messages")]];
    }
    [sections addObject:SPKTopicSection(@"消息", breakdown, nil)];

    [sections addObject:SPKTopicSection(@"磁盘占用", @[
                  [SPKSetting valueCellWithTitle:@"已捕获媒体"
                                        subtitle:[self formattedSize:self.mediaBytes]
                                            icon:SPKSettingsIcon(@"media")],
                  [SPKSetting valueCellWithTitle:@"媒体恢复缓存"
                                        subtitle:[self formattedSize:self.stagedMediaBytes]
                                            icon:SPKSettingsIcon(@"clock")],
              ],
                                        @"阅后即焚、查看两次、GIF 和贴纸媒体会在撤回前缓存到设备上，以便之后恢复。这些媒体在消息撤回前不会包含在已删除消息导出中。缓存的头像由 Sparkle 共享管理，请前往“数据与设置 › 存储”进行管理。")];

    __weak typeof(self) weakSelf = self;

    SPKSetting *clearMedia = [SPKSetting buttonCellWithTitle:@"清除已捕获媒体"
                                                    subtitle:nil
                                                        icon:SPKSettingsIcon(@"media")
                                                      action:^{
                                                          [weakSelf confirmClearMedia];
                                                      }];
    clearMedia.tintColor = [SPKUtils SPKColor_InstagramDestructive];
    clearMedia.iconTintColor = [SPKUtils SPKColor_InstagramDestructive];

    SPKSetting *clearStaged = [SPKSetting buttonCellWithTitle:@"清除媒体恢复缓存"
                                                     subtitle:nil
                                                         icon:SPKSettingsIcon(@"clock")
                                                       action:^{
                                                           [weakSelf confirmClearStagedMedia];
                                                       }];
    clearStaged.tintColor = [SPKUtils SPKColor_InstagramDestructive];
    clearStaged.iconTintColor = [SPKUtils SPKColor_InstagramDestructive];

    SPKSetting *clearLog = [SPKSetting buttonCellWithTitle:@"清除全部记录"
                                                  subtitle:nil
                                                      icon:SPKSettingsIcon(@"trash")
                                                    action:^{
                                                        [weakSelf confirmClearLog];
                                                    }];
    clearLog.tintColor = [SPKUtils SPKColor_InstagramDestructive];
    clearLog.iconTintColor = [SPKUtils SPKColor_InstagramDestructive];

    [sections addObject:SPKTopicSection(@"维护", @[ clearMedia, clearStaged, clearLog ],
                                        @"清除媒体恢复缓存后，会保留轻量级消息元数据，以便未来撤回消息时尝试恢复媒体。清除全部记录不会清除恢复缓存。")];

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
                                                    [SPKIGAlertAction actionWithTitle:@"清除媒体"
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
                                                message:@"这将删除预缓存的阅后即焚、查看两次、GIF 和贴纸媒体。轻量级元数据会保留，以便未来消息撤回后 Sparkle 仍可尝试恢复媒体。"
                                                actions:@[
                                                    [SPKIGAlertAction actionWithTitle:@"取消"
                                                                                style:SPKIGAlertActionStyleCancel
                                                                              handler:nil],
                                                    [SPKIGAlertAction actionWithTitle:@"清除媒体"
                                                                                style:SPKIGAlertActionStyleDestructive
                                                                              handler:^{
                                                                                  [SPKDeletedMessagesStorage clearStagedMediaForOwnerPK:self.ownerPK];
                                                                                  [self reloadStatsAndRebuild];
                                                                              }],
                                                ]];
}

@end
