#import "SPKDirectAutoSave.h"

#import "../../Networking/SPKInstagramAPI.h"
#import "../../Utils.h"
#import "../ActionButton/ActionButtonCore.h"
#import "../ActionButton/ActionButtonLookupUtils.h"
#import "../AutoSave/SPKAutoSave.h"
#import "../AutoSave/SPKAutoSaveFilter.h"
#import "../Downloads/SPKDownloadDuplicatePolicy.h"
#import "../Downloads/SPKDownloadTypes.h"
#import "../Gallery/SPKGalleryFile.h"
#import "../Gallery/SPKGallerySaveMetadata.h"
#import "../UI/SPKIGAlertPresenter.h"
#import "../UI/SPKNotificationCenter.h"
#import "../UI/SPKUserListViewController.h"
#import "SPKDirectSeenContext.h"
#import "SPKDirectUserResolver.h"

static NSString *const kSPKDirectAutoSaveEnabledKey = @"msgs_auto_save";

#pragma mark - Filter

SPKAutoSaveFilterConfig *SPKDirectAutoSaveFilterConfig(void) {
    static SPKAutoSaveFilterConfig *config = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        config = [SPKAutoSaveFilterConfig new];
        config.enabledKey = kSPKDirectAutoSaveEnabledKey;
        config.filterModeKey = @"msgs_auto_save_filter_mode";
        config.excludedKey = @"msgs_auto_save_excluded";
        config.includedKey = @"msgs_auto_save_included";
        config.identityField = @"threadId";
        config.sortField = @"threadName";
        config.subjectPlural = @"聊天";
        config.ruleNotificationIdentifier = kSPKNotificationDirectAutoSaveThreadRule;
    });
    return config;
}

BOOL SPKDirectAutoSaveAllChatsMode(void) {
    return SPKAutoSaveFilterAllMode(SPKDirectAutoSaveFilterConfig());
}

NSString *SPKDirectAutoSaveListTitle(void) {
    return SPKAutoSaveFilterListTitle(SPKDirectAutoSaveFilterConfig());
}

BOOL SPKDirectAutoSaveAppliesToThread(NSString *threadId) {
    return SPKAutoSaveFilterApplies(SPKDirectAutoSaveFilterConfig(), threadId);
}

NSString *SPKDirectAutoSaveSettingsSummary(void) {
    return SPKAutoSaveFilterSummary(SPKDirectAutoSaveFilterConfig());
}

#pragma mark - Auto-saver

// Item keys already handled this viewer session -- both saved items and items rejected
// by the filter, so a rejected item costs one list lookup rather than one per callback.
static NSMutableSet<NSString *> *SPKDirectAutoSaveSessionKeys(void) {
    static NSMutableSet<NSString *> *keys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = [NSMutableSet set];
    });
    return keys;
}

void SPKDirectAutoSaveViewerSessionDidEnd(void) {
    [SPKDirectAutoSaveSessionKeys() removeAllObjects];
}

void SPKDirectAutoSaveConsiderController(UIViewController *controller) {
    if (!controller)
        return;
    if (![SPKUtils getBoolPref:kSPKDirectAutoSaveEnabledKey])
        return;

    SPKDirectThreadContext *thread = SPKDirectThreadContextFromSource(controller);
    NSString *threadId = SPKStringFromValue(thread.threadId);
    if (threadId.length == 0)
        return;
    if (!SPKDirectAutoSaveAppliesToThread(threadId))
        return;

    id media = SPKDirectResolvedMediaFromController(controller);
    if (!media)
        return;

    NSString *username = SPKDirectUsernameFromController(controller);
    NSURL *photoURL = nil;
    NSURL *videoURL = nil;
    SPKGallerySaveMetadata *metadata = nil;
    if (!SPKResolveGalleryDownloadForMedia(media, SPKActionButtonSourceDirect, username,
                                           &photoURL, &videoURL, &metadata)) {
        SPKLog(@"消息", @"[Sparkle AutoSave] No downloadable media for DM thread=%@ user=@%@", threadId, username);
        return;
    }
    BOOL isVideo = (videoURL != nil);

    // View-once media has no stable server id in every payload, so fall back to the
    // resolved URL: it's per-item and stable for the life of the viewer session.
    NSString *itemKey = SPKStringFromValue(metadata.sourceMediaPK);
    if (itemKey.length == 0)
        itemKey = (videoURL ?: photoURL).absoluteString;
    if (itemKey.length == 0)
        return;

    NSMutableSet<NSString *> *sessionKeys = SPKDirectAutoSaveSessionKeys();
    if ([sessionKeys containsObject:itemKey])
        return;
    // Claim the item before any async work so a later callback for the same item
    // can't queue a second download for it.
    [sessionKeys addObject:itemKey];

    // Durable guard: the session set only covers this viewer session.
    SPKGalleryMediaType mediaType = isVideo ? SPKGalleryMediaTypeVideo : SPKGalleryMediaTypeImage;
    SPKDownloadDestination destination = SPKAutoSaveDestination();
    if ([SPKDownloadDuplicatePolicy destinationContainsMediaForMetadata:metadata
                                                              mediaType:mediaType
                                                            destination:destination]) {
        SPKLog(@"消息", @"[Sparkle AutoSave] Already in %@, skipping DM item thread=%@ user=@%@",
               SPKDownloadDestinationDisplayName(destination), threadId, username);
        return;
    }

    SPKLog(@"消息", @"[Sparkle AutoSave] Saving DM media thread=%@ user=@%@ video=%d", threadId, username, isVideo);
    if (!SPKAutoSaveSubmitMedia(media, SPKActionButtonSourceDirect, username, kSPKNotificationDirectAutoSave)) {
        // Nothing was queued, so let the item be retried next time it's displayed.
        [sessionKeys removeObject:itemKey];
        SPKLog(@"消息", @"[Sparkle AutoSave] Failed to submit DM item thread=%@ user=@%@", threadId, username);
    }
}

#pragma mark - Current-thread rule (DM viewer action menu)

// Never prefixes "@": the resolved name is a group title, a full name, or an already
// "@"-prefixed username, and only the last of those is a handle.
static NSString *SPKDirectAutoSaveThreadDisplayName(SPKDirectThreadContext *context) {
    NSString *name = SPKDirectDisplayNameForThreadContext(context);
    if (name.length > 0)
        return name;
    return context.isGroup ? @"此群组" : @"此聊天";
}

BOOL SPKDirectAutoSaveAppliesToCurrentThread(SPKDirectThreadContext *context) {
    NSString *threadId = SPKStringFromValue(context.threadId);
    if (threadId.length == 0)
        return NO;
    return SPKDirectAutoSaveAppliesToThread(threadId);
}

// The menu action reads as "does auto-save currently apply to this chat?", which in All
// Chats mode means removing it from the exclusion list and in Selected Chats mode means
// adding it to the inclusion list. Both are the same toggle underneath.
NSString *SPKDirectAutoSaveCurrentThreadActionTitle(SPKDirectThreadContext *context) {
    NSString *threadId = SPKStringFromValue(context.threadId);
    if (threadId.length == 0)
        return nil;
    return SPKDirectAutoSaveAppliesToCurrentThread(context) ? @"停止自动保存此聊天" : @"自动保存此聊天";
}

NSString *SPKDirectAutoSaveCurrentThreadConfirmationTitle(SPKDirectThreadContext *context) {
    return SPKDirectAutoSaveCurrentThreadActionTitle(context);
}

NSString *SPKDirectAutoSaveCurrentThreadConfirmationMessage(SPKDirectThreadContext *context) {
    NSString *threadId = SPKStringFromValue(context.threadId);
    if (threadId.length == 0)
        return nil;
    NSString *name = SPKDirectAutoSaveThreadDisplayName(context);
    return SPKDirectAutoSaveAppliesToThread(threadId)
               ? [NSString stringWithFormat:@"确定要停止自动保存 %@ 的阅后即焚媒体吗？", name]
               : [NSString stringWithFormat:@"确定要自动保存 %@ 的所有阅后即焚照片和视频吗？", name];
}

BOOL SPKDirectToggleAutoSaveCurrentThread(SPKDirectThreadContext *context,
                                          NSString **notificationTitle,
                                          NSString **notificationSubtitle) {
    NSDictionary *entry = SPKDirectThreadEntryFromContext(context);
    if (!entry)
        return NO;

    NSString *threadId = SPKStringFromValue(context.threadId);
    BOOL appliedBefore = SPKDirectAutoSaveAppliesToThread(threadId);
    SPKAutoSaveFilterToggleEntry(SPKDirectAutoSaveFilterConfig(), entry);

    NSString *name = SPKDirectAutoSaveThreadDisplayName(context);
    if (notificationTitle) {
        *notificationTitle = appliedBefore ? [NSString stringWithFormat:@"已关闭 %@ 的自动保存", name]
                                           : [NSString stringWithFormat:@"已开启 %@ 的自动保存", name];
    }
    if (notificationSubtitle)
        *notificationSubtitle = SPKDirectAutoSaveListTitle();
    return YES;
}

void SPKDirectPresentAutoSaveThreadRuleToggle(SPKDirectThreadContext *context) {
    NSString *title = SPKDirectAutoSaveCurrentThreadConfirmationTitle(context);
    NSString *message = SPKDirectAutoSaveCurrentThreadConfirmationMessage(context);
    if (title.length == 0 || message.length == 0) {
        SPKNotify(kSPKNotificationDirectAutoSaveThreadRule, @"找不到聊天", nil, @"error_filled", SPKNotificationToneError);
        return;
    }

    [SPKUtils
        showConfirmation:^{
            NSString *notificationTitle = nil;
            NSString *notificationSubtitle = nil;
            if (!SPKDirectToggleAutoSaveCurrentThread(context, &notificationTitle, &notificationSubtitle)) {
                SPKNotify(kSPKNotificationDirectAutoSaveThreadRule, @"找不到聊天", nil, @"error_filled", SPKNotificationToneError);
                return;
            }
            SPKNotify(kSPKNotificationDirectAutoSaveThreadRule, notificationTitle, notificationSubtitle, @"circle_check_filled",
                      SPKNotificationToneSuccess);
            // The item on screen was already skipped this session, so turning the rule
            // on only takes effect from the next one.
        }
                   title:title
                 message:message];
}

#pragma mark - Auto-save chats list

@interface SPKDirectAutoSaveChatsViewController : SPKAutoSaveFilterListViewController
@end

@implementation SPKDirectAutoSaveChatsViewController

- (instancetype)init {
    if ((self = [super initWithConfig:SPKDirectAutoSaveFilterConfig()])) {
        BOOL allChats = SPKDirectAutoSaveAllChatsMode();
        self.showsAddButton = YES;
        self.infoText = allChats
                            ? @"当前筛选模式为“所有聊天”，因此你打开的所有阅后即焚照片和视频都会被保存，但此列表中的聊天除外。已有的媒体将跳过保存。"
        : @"当前筛选模式为“指定聊天”，因此只有此列表中的聊天里的阅后即焚媒体会被保存。已有的媒体将跳过保存。";
                            
        self.emptyTitle = @"暂无聊天";
        self.emptySubtitle = allChats
                                         ? @"添加不应自动保存阅后即焚媒体的聊天。"
                                         : @"添加需要在打开阅后即焚媒体时自动保存的聊天。";
    }
    return self;
}

- (NSString *)displayNameForEntry:(NSDictionary *)entry {
    return SPKDirectDisplayNameForThreadEntry(entry) ?: @"未知聊天";
}

- (NSString *)removalDisplayNameForEntry:(NSDictionary *)entry {
    return [self displayNameForEntry:entry];
}

// Without this the base class would treat a group's *name* as a handle and try to open
// a profile for it.
- (void)didSelectItem:(SPKUserListItem *)item {
    SPKDirectOpenProfileForThreadEntry(item.representedObject);
}

- (NSArray<SPKUserListItem *> *)buildItems {
    NSMutableArray<SPKUserListItem *> *items = [NSMutableArray array];
    for (NSDictionary *entry in SPKAutoSaveFilterList(self.config)) {
        SPKUserListItem *item = [SPKUserListItem new];
        item.representedObject = entry;

        if ([entry[@"isGroup"] boolValue]) {
            item.isGroup = YES;
            item.title = [self displayNameForEntry:entry];
            item.subtitle = SPKDirectParticipantSubtitleForThreadEntry(entry);
            NSString *threadId = SPKStringFromValue(entry[@"threadId"]);
            // Shared cache key matches the manual-seen thread list; a synthetic "grp_"
            // PK can't self-heal, but SPKAvatarView draws the group glyph.
            if (threadId.length > 0)
                item.pk = [@"grp_" stringByAppendingString:threadId];
            item.avatarURLString = SPKStringFromValue(entry[@"groupPhotoUrl"]);
            [items addObject:item];
            continue;
        }

        NSArray *users = [entry[@"users"] isKindOfClass:[NSArray class]] ? entry[@"users"] : @[];
        NSDictionary *user = users.firstObject;
        NSString *pk = SPKStringFromValue(user[@"pk"]);
        NSString *username = SPKStringFromValue(user[@"用户名"]);
        NSString *fullName = SPKStringFromValue(user[@"fullName"]);
        NSString *profilePicUrl = SPKStringFromValue(user[@"profilePicUrl"]);
        if (profilePicUrl.length == 0 && pk.length > 0)
            profilePicUrl = spkDirectUserResolverProfilePicURLStringForPK(pk);

        item.pk = pk;
        item.title = username.length > 0 ? [@"@" stringByAppendingString:username] : [self displayNameForEntry:entry];
        item.subtitle = fullName.length > 0 ? fullName : nil;
        item.avatarURLString = profilePicUrl;
        [items addObject:item];
    }
    return items;
}

- (void)presentError:(NSString *)message {
    [SPKIGAlertPresenter presentAlertFromViewController:self
                                                  title:@"无法添加聊天"
                                                message:message
                                                actions:@[ [SPKIGAlertAction actionWithTitle:@"OK" style:SPKIGAlertActionStyleCancel handler:nil] ]];
}

- (void)didTapAdd {
    __weak typeof(self) weakSelf = self;
    [SPKIGAlertPresenter presentTextInputAlertFromViewController:self
                                                           title:@"添加聊天"
                                                         message:@"请输入一对一私信聊天的 Instagram 用户名。群聊可以从查看器的操作菜单中添加。"
                                                     placeholder:@"用户名"
                                                     initialText:nil
                                                 autocapitalized:NO
                                                    confirmTitle:@"搜索"
                                                     cancelTitle:@"取消"
                                                    confirmStyle:SPKIGAlertActionStyleDefault
                                                    confirmBlock:^(NSString *text) {
                                                        [weakSelf lookupUsername:text];
                                                    }
                                                     cancelBlock:nil];
}

- (void)lookupUsername:(NSString *)rawUsername {
    NSString *username = [SPKUtils sanitizedInstagramUsername:rawUsername];
    if (username.length == 0)
        return;

    __weak typeof(self) weakSelf = self;
    [SPKInstagramAPI resolveUserForUsername:username
                                  completion:^(NSDictionary *user, NSError *error) {
                                      __strong typeof(weakSelf) strongSelf = weakSelf;
                                      if (!strongSelf)
                                          return;
                                      if (![user isKindOfClass:[NSDictionary class]] || error) {
                                          [strongSelf presentError:[NSString stringWithFormat:@"未找到用户“%@。", username]];
                                          return;
                                      }
                                      NSString *pk = SPKStringFromValue(user[@"pk"] ?: user[@"id"]);
                                      if (pk.length == 0) {
                                          [strongSelf presentError:@"无法获取此用户的 Instagram ID。"];
                                          return;
                                      }
                                      [strongSelf resolveThreadForPK:pk
                                                            username:SPKStringFromValue(user[@"用户名"]) ?: username
                                                            fullName:SPKStringFromValue(user[@"full_name"] ?: user[@"fullName"]) ?: @""
                                                       profilePicUrl:SPKStringFromValue(user[@"profile_pic_url"] ?: user[@"profile_pic_url_hd"])];
                                  }];
}

// The list is keyed by thread, so a username has to be turned into the 1:1 thread it
// maps to. A user you've never DM'd has no thread to key on.
- (void)resolveThreadForPK:(NSString *)pk username:(NSString *)username fullName:(NSString *)fullName profilePicUrl:(NSString *)profilePicUrl {
    NSString *encodedRecipients = [[NSString stringWithFormat:@"[%@]", pk] stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    __weak typeof(self) weakSelf = self;
    [SPKInstagramAPI sendRequestWithMethod:@"GET"
                                      path:[NSString stringWithFormat:@"direct_v2/threads/get_by_participants/?recipient_users=%@", encodedRecipients]
                                      body:nil
                                completion:^(NSDictionary *threadResponse, NSError *threadError) {
                                    __strong typeof(weakSelf) strongSelf = weakSelf;
                                    if (!strongSelf)
                                        return;
                                    NSDictionary *thread = threadResponse[@"thread"];
                                    NSString *threadId = [thread isKindOfClass:[NSDictionary class]]
                                                             ? SPKStringFromValue(thread[@"thread_id"] ?: thread[@"threadId"])
                                                             : nil;
                                    if (threadId.length == 0 || threadError) {
                                        [strongSelf presentError:[NSString stringWithFormat:@"未找到与 @%@ 的一对一私信聊天。", username]];
                                        return;
                                    }

                                    NSMutableDictionary *userEntry = [@{@"pk" : pk, @"用户名" : username, @"fullName" : fullName} mutableCopy];
                                    if (profilePicUrl.length > 0)
                                        userEntry[@"profilePicUrl"] = profilePicUrl;
                                    NSDictionary *entry = @{
                                        @"threadId" : threadId,
                                        @"threadName" : SPKStringFromValue(thread[@"thread_title"]) ?: username,
                                        @"isGroup" : @(NO),
                                        @"users" : @[ userEntry.copy ],
                                    };

                                    NSString *message = fullName.length > 0 ? [NSString stringWithFormat:@"@%@ (%@)", username, fullName]
                                                                            : [@"@" stringByAppendingString:username];
                                    [SPKIGAlertPresenter presentAlertFromViewController:strongSelf
                                                                                  title:@"自动保存此聊天？"
                                                                                message:message
                                                                                actions:@[
                                                                                    [SPKIGAlertAction actionWithTitle:@"取消"
                                                                                                                style:SPKIGAlertActionStyleCancel
                                                                                                              handler:nil],
                                                                                    [SPKIGAlertAction actionWithTitle:@"添加"
                                                                                                                style:SPKIGAlertActionStyleDefault
                                                                                                              handler:^{
                                                                                                                  [strongSelf addResolvedEntry:entry username:username];
                                                                                                              }],
                                                                                ]];
                                }];
}

- (void)addResolvedEntry:(NSDictionary *)entry username:(NSString *)username {
    if (SPKAutoSaveFilterListContains(self.config, entry[@"threadId"]))
        return;
    SPKAutoSaveFilterToggleEntry(self.config, entry);
    SPKNotify(kSPKNotificationDirectAutoSaveThreadRule,
              [NSString stringWithFormat:@"已添加 @%@", username],
              SPKDirectAutoSaveListTitle(),
              @"circle_check_filled",
              SPKNotificationToneSuccess);
    [self reloadItems];
}

@end

UIViewController *SPKDirectAutoSaveListViewController(void) {
    return [[SPKDirectAutoSaveChatsViewController alloc] init];
}
