#import "SPKInstantsAutoSave.h"

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
#import "../Messages/SPKDirectUserResolver.h"
#import "../UI/SPKIGAlertPresenter.h"
#import "../UI/SPKNotificationCenter.h"
#import "../UI/SPKUserListViewController.h"

static NSString *const kSPKInstantsAutoSaveEnabledKey = @"instants_auto_save";

#pragma mark - Filter

SPKAutoSaveFilterConfig *SPKInstantsAutoSaveFilterConfig(void) {
    static SPKAutoSaveFilterConfig *config = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        config = [SPKAutoSaveFilterConfig new];
        config.enabledKey = kSPKInstantsAutoSaveEnabledKey;
        config.filterModeKey = @"instants_auto_save_filter_mode";
        config.excludedKey = @"instants_auto_save_excluded";
        config.includedKey = @"instants_auto_save_included";
        config.identityField = @"用户名";
        config.sortField = @"用户名";
        config.subjectPlural = @"Users";
        config.ruleNotificationIdentifier = kSPKNotificationInstantsAutoSaveUserRule;
    });
    return config;
}

BOOL SPKInstantsAutoSaveAllUsersMode(void) {
    return SPKAutoSaveFilterAllMode(SPKInstantsAutoSaveFilterConfig());
}

NSString *SPKInstantsAutoSaveListTitle(void) {
    return SPKAutoSaveFilterListTitle(SPKInstantsAutoSaveFilterConfig());
}

BOOL SPKInstantsAutoSaveAppliesToUsername(NSString *username) {
    return SPKAutoSaveFilterApplies(SPKInstantsAutoSaveFilterConfig(), username);
}

NSString *SPKInstantsAutoSaveSettingsSummary(void) {
    return SPKAutoSaveFilterSummary(SPKInstantsAutoSaveFilterConfig());
}

#pragma mark - Auto-saver

// Snap keys already handled this viewer session -- both saved snaps and snaps rejected
// by the filter, so a rejected snap costs one list lookup rather than one per pass.
static NSMutableSet<NSString *> *SPKInstantsAutoSaveSessionKeys(void) {
    static NSMutableSet<NSString *> *keys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = [NSMutableSet set];
    });
    return keys;
}

void SPKInstantsAutoSaveViewerSessionDidEnd(void) {
    [SPKInstantsAutoSaveSessionKeys() removeAllObjects];
}

// Keys are usually 700-character CDN URLs; logs get the tail, which is enough to tell
// two snaps apart.
static NSString *SPKInstantsAutoSaveLoggableKey(NSString *key) {
    if (key.length <= 24)
        return key ?: @"(none)";
    return [NSString stringWithFormat:@"…%@", [key substringFromIndex:key.length - 24]];
}

void SPKInstantsAutoSaveConsiderSnap(id snap, NSString *username, NSString *snapKey) {
    if (!snap)
        return;
    if (![SPKUtils getBoolPref:kSPKInstantsAutoSaveEnabledKey])
        return;

    NSString *normalized = SPKAutoSaveFilterNormalizedUsername(username);
    if (normalized.length == 0)
        return;

    if (snapKey.length == 0)
        return;

    NSMutableSet<NSString *> *sessionKeys = SPKInstantsAutoSaveSessionKeys();
    if ([sessionKeys containsObject:snapKey])
        return;

    if (!SPKInstantsAutoSaveAppliesToUsername(normalized)) {
        [sessionKeys addObject:snapKey];
        return;
    }

    // Claim the snap before any async work so a later pass over the same snap can't
    // queue a second download for it.
    [sessionKeys addObject:snapKey];

    NSURL *photoURL = nil;
    NSURL *videoURL = nil;
    SPKGallerySaveMetadata *metadata = nil;
    if (!SPKResolveGalleryDownloadForMedia(snap, SPKActionButtonSourceInstants, normalized,
                                           &photoURL, &videoURL, &metadata)) {
        SPKLog(@"Instants", @"[Sparkle AutoSave] No downloadable media for snap=%@ user=@%@", SPKInstantsAutoSaveLoggableKey(snapKey), normalized);
        return;
    }

    // Durable guard: the session set only covers this viewer session.
    SPKGalleryMediaType mediaType = videoURL ? SPKGalleryMediaTypeVideo : SPKGalleryMediaTypeImage;
    SPKDownloadDestination destination = SPKAutoSaveDestination();
    if ([SPKDownloadDuplicatePolicy destinationContainsMediaForMetadata:metadata
                                                              mediaType:mediaType
                                                            destination:destination]) {
        SPKLog(@"Instants", @"[Sparkle AutoSave] Already in %@, skipping snap=%@ user=@%@",
               SPKDownloadDestinationDisplayName(destination), SPKInstantsAutoSaveLoggableKey(snapKey), normalized);
        return;
    }

    SPKLog(@"Instants", @"[Sparkle AutoSave] Saving instant snap=%@ user=@%@ video=%d", SPKInstantsAutoSaveLoggableKey(snapKey), normalized, videoURL != nil);
    if (!SPKAutoSaveSubmitMedia(snap, SPKActionButtonSourceInstants, normalized, kSPKNotificationInstantsAutoSave)) {
        // Nothing was queued, so let the snap be retried while it's still displayed.
        [sessionKeys removeObject:snapKey];
        SPKLog(@"Instants", @"[Sparkle AutoSave] Failed to submit snap=%@ user=@%@", SPKInstantsAutoSaveLoggableKey(snapKey), normalized);
    }
}

#pragma mark - Auto-save users list

@interface SPKInstantsAutoSaveUsersViewController : SPKAutoSaveFilterListViewController
@end

@implementation SPKInstantsAutoSaveUsersViewController

- (instancetype)init {
    if ((self = [super initWithConfig:SPKInstantsAutoSaveFilterConfig()])) {
        BOOL allUsers = SPKInstantsAutoSaveAllUsersMode();
        self.showsAddButton = YES;
        self.infoText = allUsers
                            ? @"Filter Mode is All Users, so every instant you open is saved except from users in this "
                              @"list. Instants you already have are skipped."
                            : @"Filter Mode is Selected Users, so only instants from users in this list are saved. "
                              @"Instants you already have are skipped.";
        self.emptyTitle = @"No users yet";
        self.emptySubtitle = allUsers
                                 ? @"Add users whose instants should never be auto-saved."
                                 : @"Add users whose instants should be saved automatically as you open them.";
    }
    return self;
}

- (NSString *)removalDisplayNameForEntry:(NSDictionary *)entry {
    NSString *username = SPKStringFromValue(entry[@"用户名"]);
    return username.length > 0 ? [@"@" stringByAppendingString:username] : nil;
}

- (NSArray<SPKUserListItem *> *)buildItems {
    NSMutableArray<SPKUserListItem *> *items = [NSMutableArray array];
    for (NSDictionary *entry in SPKAutoSaveFilterList(self.config)) {
        NSString *username = SPKStringFromValue(entry[@"用户名"]);
        NSString *pk = SPKStringFromValue(entry[@"pk"]);
        NSString *fullName = SPKStringFromValue(entry[@"fullName"]);
        NSString *profilePicUrl = SPKStringFromValue(entry[@"profilePicUrl"]);
        if (profilePicUrl.length == 0 && pk.length > 0)
            profilePicUrl = spkDirectUserResolverProfilePicURLStringForPK(pk);

        SPKUserListItem *item = [SPKUserListItem new];
        item.pk = pk;
        item.title = username.length > 0 ? [@"@" stringByAppendingString:username] : @"Unknown user";
        item.subtitle = fullName.length > 0 ? fullName : nil;
        item.avatarURLString = profilePicUrl;
        item.representedObject = entry;
        [items addObject:item];
    }
    return items;
}

- (void)presentError:(NSString *)message {
    [SPKIGAlertPresenter presentAlertFromViewController:self
                                                  title:@"无法添加用户"
                                                message:message
                                                actions:@[ [SPKIGAlertAction actionWithTitle:@"OK" style:SPKIGAlertActionStyleCancel handler:nil] ]];
}

- (void)didTapAdd {
    __weak typeof(self) weakSelf = self;
    [SPKIGAlertPresenter presentTextInputAlertFromViewController:self
                                                           title:@"添加用户"
                                                         message:@"Enter the Instagram username whose instants should be auto-saved."
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

// The list keys on username, so the lookup is only for the avatar, full name, and to
// catch typos -- a failed lookup still leaves a usable entry.
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
                                          [strongSelf presentError:[NSString stringWithFormat:@"User '%@' was not found.", username]];
                                          return;
                                      }

                                      NSString *resolvedUsername = SPKStringFromValue(user[@"用户名"]) ?: username;
                                      NSString *fullName = SPKStringFromValue(user[@"full_name"] ?: user[@"fullName"]) ?: @"";
                                      NSString *message = fullName.length > 0
                                                              ? [NSString stringWithFormat:@"@%@ (%@)", resolvedUsername, fullName]
                                                              : [@"@" stringByAppendingString:resolvedUsername];
                                      NSMutableDictionary *entry = [@{@"用户名" : resolvedUsername, @"fullName" : fullName} mutableCopy];
                                      NSString *pk = SPKStringFromValue(user[@"pk"] ?: user[@"id"]);
                                      if (pk.length > 0)
                                          entry[@"pk"] = pk;
                                      NSString *profilePicUrl = SPKStringFromValue(user[@"profile_pic_url"] ?: user[@"profile_pic_url_hd"]);
                                      if (profilePicUrl.length > 0)
                                          entry[@"profilePicUrl"] = profilePicUrl;

                                      [SPKIGAlertPresenter presentAlertFromViewController:strongSelf
                                                                                    title:@"自动保存快拍？"
                                                                                  message:message
                                                                                  actions:@[
                                                                                      [SPKIGAlertAction actionWithTitle:@"取消"
                                                                                                                  style:SPKIGAlertActionStyleCancel
                                                                                                                handler:nil],
                                                                                      [SPKIGAlertAction actionWithTitle:@"Add"
                                                                                                                  style:SPKIGAlertActionStyleDefault
                                                                                                                handler:^{
                                                                                                                    [strongSelf addResolvedEntry:entry.copy username:resolvedUsername];
                                                                                                                }],
                                                                                  ]];
                                  }];
}

- (void)addResolvedEntry:(NSDictionary *)entry username:(NSString *)username {
    if (SPKAutoSaveFilterListContains(self.config, username))
        return;
    SPKAutoSaveFilterToggleEntry(self.config, entry);
    SPKNotify(kSPKNotificationInstantsAutoSaveUserRule,
              [NSString stringWithFormat:@"Added @%@", username],
              SPKInstantsAutoSaveListTitle(),
              @"circle_check_filled",
              SPKNotificationToneSuccess);
    [self reloadItems];
}

@end

UIViewController *SPKInstantsAutoSaveListViewController(void) {
    return [[SPKInstantsAutoSaveUsersViewController alloc] init];
}
