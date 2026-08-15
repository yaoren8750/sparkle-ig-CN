#import "SPKDeletedMessagesStorage.h"
#import "../../../Shared/Avatars/SPKAvatarCache.h"
#import "../../../Shared/SPKStoragePaths.h"

NSNotificationName const SPKDeletedMessagesDidChangeNotification = @"SPKDeletedMessagesDidChangeNotification";

static NSString *const kSPKDMMediaDir = @"media";
static NSString *const kSPKDMSenderFlagsFile = @"sender_flags.json";
static NSString *const kSPKDMPendingCandidatesDir = @"candidates";
static NSString *const kSPKDMPendingRemovalsDir = @"removals";

@implementation SPKDeletedMessagesStorage

#pragma mark - Plumbing

static dispatch_queue_t spkDMQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("com.sparkle.deletedmessages.io", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

static NSString *spkSafePK(NSString *pk) {
    return pk.length ? pk : @"anon";
}

static NSString *spkStorageDir(void) {
    NSString *dir = [SPKStoragePaths deletedMessagesDirectory];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static NSString *spkMediaDirForOwner(NSString *pk) {
    NSString *dir = [[spkStorageDir() stringByAppendingPathComponent:kSPKDMMediaDir]
        stringByAppendingPathComponent:spkSafePK(pk)];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static NSString *spkPendingStorageDir(void) {
    NSString *dir = [SPKStoragePaths deletedMessagesPendingDirectory];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static NSString *spkPendingSubdirectory(NSString *name) {
    NSString *dir = [spkPendingStorageDir() stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static NSString *spkPendingJSONPath(NSString *directory, NSString *pk) {
    return [[spkPendingSubdirectory(directory) stringByAppendingPathComponent:spkSafePK(pk)]
        stringByAppendingPathExtension:@"json"];
}

static NSString *spkStagedMediaDirForOwner(NSString *pk) {
    NSString *dir = [[spkPendingStorageDir() stringByAppendingPathComponent:kSPKDMMediaDir]
        stringByAppendingPathComponent:spkSafePK(pk)];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static NSString *spkJSONPathForOwner(NSString *pk) {
    return [spkStorageDir() stringByAppendingPathComponent:
                                [NSString stringWithFormat:@"%@.json", spkSafePK(pk)]];
}

static NSString *spkFlagsPath(void) {
    return [spkStorageDir() stringByAppendingPathComponent:kSPKDMSenderFlagsFile];
}

static NSArray *spkReadArray(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length)
        return @[];
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [obj isKindOfClass:[NSArray class]] ? obj : @[];
}

static BOOL spkWriteArray(NSString *path, NSArray *arr) {
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:(arr ?: @[]) options:0 error:&err];
    if (!data)
        return NO;
    return [data writeToFile:path atomically:YES];
}

static NSMutableDictionary *spkReadDictionary(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length)
        return [NSMutableDictionary dictionary];
    id obj = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    return [obj isKindOfClass:[NSMutableDictionary class]] ? obj : [NSMutableDictionary dictionary];
}

static BOOL spkWriteDictionary(NSString *path, NSDictionary *dict) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:(dict ?: @{}) options:0 error:nil];
    return data ? [data writeToFile:path atomically:YES] : NO;
}

static unsigned long long spkDirectorySize(NSString *dir) {
    NSDirectoryEnumerator *en = [[NSFileManager defaultManager] enumeratorAtPath:dir];
    unsigned long long total = 0;
    for (NSString *rel in en) {
        NSDictionary *attrs = [en fileAttributes];
        if ([attrs[NSFileType] isEqualToString:NSFileTypeRegular]) {
            total += [attrs[NSFileSize] unsignedLongLongValue];
        }
        (void)rel;
    }
    return total;
}

static NSMutableDictionary *spkReadFlags(void) {
    NSData *data = [NSData dataWithContentsOfFile:spkFlagsPath()];
    if (!data.length)
        return [NSMutableDictionary dictionary];
    id obj = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    return [obj isKindOfClass:[NSMutableDictionary class]] ? obj : [NSMutableDictionary dictionary];
}

static BOOL spkWriteFlags(NSDictionary *flags) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:(flags ?: @{}) options:0 error:nil];
    return data ? [data writeToFile:spkFlagsPath() atomically:YES] : NO;
}

static NSMutableDictionary *spkFlagsForOwner(NSMutableDictionary *flags, NSString *ownerPK, BOOL create) {
    NSString *owner = spkSafePK(ownerPK);
    id existing = flags[owner];
    if ([existing isKindOfClass:[NSMutableDictionary class]])
        return existing;
    if ([existing isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *copy = [existing mutableCopy];
        flags[owner] = copy;
        return copy;
    }
    if (!create)
        return nil;
    NSMutableDictionary *ownerFlags = [NSMutableDictionary dictionary];
    flags[owner] = ownerFlags;
    return ownerFlags;
}

static NSDictionary *spkSenderFlags(NSString *senderPK, NSString *ownerPK) {
    if (!senderPK.length)
        return @{};
    __block NSDictionary *result = nil;
    dispatch_sync(spkDMQueue(), ^{
        NSMutableDictionary *flags = spkReadFlags();
        NSDictionary *ownerFlags = spkFlagsForOwner(flags, ownerPK, NO);
        id senderFlags = ownerFlags[senderPK];
        result = [senderFlags isKindOfClass:[NSDictionary class]] ? senderFlags : @{};
    });
    return result ?: @{};
}

static void spkPostChanged(NSString *ownerPK) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SPKDeletedMessagesDidChangeNotification
                                                            object:nil
                                                          userInfo:ownerPK.length ? @{@"owner_pk" : ownerPK} : @{}];
    });
}

// Newest-first order. capturedAt is required; deletedAt is the truer key when present.
static NSDate *spkSortKey(SPKDeletedMessage *m) {
    return m.deletedAt ?: (m.capturedAt ?: m.sentAt);
}

static NSArray<SPKDeletedMessage *> *spkDecode(NSArray *raw) {
    NSMutableArray<SPKDeletedMessage *> *out = [NSMutableArray arrayWithCapacity:raw.count];
    for (id d in raw) {
        SPKDeletedMessage *m = [SPKDeletedMessage messageFromJSONDict:d];
        if (m)
            [out addObject:m];
    }
    return out;
}

static NSArray<NSDictionary *> *spkEncode(NSArray<SPKDeletedMessage *> *msgs) {
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:msgs.count];
    for (SPKDeletedMessage *m in msgs)
        [out addObject:[m toJSONDict]];
    return out;
}

#pragma mark - Read

+ (NSArray<SPKDeletedMessage *> *)allMessagesForOwnerPK:(NSString *)ownerPK {
    __block NSArray<SPKDeletedMessage *> *result = nil;
    dispatch_sync(spkDMQueue(), ^{
        result = spkDecode(spkReadArray(spkJSONPathForOwner(ownerPK)));
    });
    return result ?: @[];
}

+ (NSArray<NSString *> *)allOwnerPKs {
    __block NSArray<NSString *> *owners = @[];
    dispatch_sync(spkDMQueue(), ^{
        NSArray<NSString *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:spkStorageDir() error:nil] ?: @[];
        NSMutableArray<NSString *> *result = [NSMutableArray array];
        for (NSString *file in files) {
            if (![file.pathExtension isEqualToString:@"json"])
                continue;
            if ([file isEqualToString:kSPKDMSenderFlagsFile])
                continue;
            NSString *owner = file.stringByDeletingPathExtension;
            if (owner.length)
                [result addObject:owner];
        }
        owners = [result copy];
    });
    return owners;
}

+ (NSArray<SPKDeletedMessage *> *)messagesForSenderPK:(NSString *)senderPK ownerPK:(NSString *)ownerPK {
    if (!senderPK.length)
        return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (SPKDeletedMessage *m in [self allMessagesForOwnerPK:ownerPK]) {
        if ([m.senderPk isEqualToString:senderPK])
            [out addObject:m];
    }
    return out;
}

+ (NSArray<SPKDeletedMessage *> *)messagesForThreadId:(NSString *)threadId ownerPK:(NSString *)ownerPK {
    if (!threadId.length)
        return @[];
    NSMutableArray<SPKDeletedMessage *> *out = [NSMutableArray array];
    for (SPKDeletedMessage *m in [self allMessagesForOwnerPK:ownerPK]) {
        if ([m.threadId isEqualToString:threadId])
            [out addObject:m];
    }
    // Chronological by original send time (fall back to deletion time) so the
    // conversation reads top-to-bottom like a real chat.
    [out sortUsingComparator:^NSComparisonResult(SPKDeletedMessage *a, SPKDeletedMessage *b) {
        NSDate *da = a.sentAt ?: a.deletedAt ?
                             : a.capturedAt  ?
                                             : [NSDate distantPast];
        NSDate *db = b.sentAt ?: b.deletedAt ?
                             : b.capturedAt  ?
                                             : [NSDate distantPast];
        return [da compare:db];
    }];
    return out;
}

// Best display label for a sender, from any captured message by them. Prefer
// the full name (IG titles untitled groups with participant names, not handles).
static NSString *spkSenderLabel(SPKDeletedMessage *m) {
    if (m.senderFullName.length)
        return m.senderFullName;
    if (m.senderUsername.length)
        return [@"@" stringByAppendingString:m.senderUsername];
    return nil;
}

// Generated group title from the distinct non-owner sender labels — used when
// the real thread name wasn't captured (e.g. messages logged before the chat
// was opened with the tweak active).
static NSString *spkGeneratedGroupTitle(NSArray<SPKDeletedMessage *> *msgs, NSString *ownerPK) {
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (SPKDeletedMessage *m in msgs) {
        if (!m.senderPk.length || [m.senderPk isEqualToString:ownerPK])
            continue;
        if ([seen containsObject:m.senderPk])
            continue;
        [seen addObject:m.senderPk];
        NSString *label = spkSenderLabel(m);
        if (label.length)
            [labels addObject:label];
    }
    if (!labels.count)
        return @"Group chat";
    if (labels.count <= 3)
        return [labels componentsJoinedByString:@", "];
    NSArray *head = [labels subarrayWithRange:NSMakeRange(0, 3)];
    return [NSString stringWithFormat:@"%@ +%lu", [head componentsJoinedByString:@", "], (unsigned long)(labels.count - 3)];
}

+ (NSArray<SPKDeletedMessageGroup *> *)groupedForOwnerPK:(NSString *)ownerPK {
    NSArray<SPKDeletedMessage *> *all = [self allMessagesForOwnerPK:ownerPK]; // newest-first

    // First pass: per-thread aggregates that decide group-ness and title.
    NSMutableDictionary<NSString *, NSMutableArray<SPKDeletedMessage *> *> *byThread = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *nonOwnerSenders = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *flaggedGroupThreads = [NSMutableSet set];
    NSMutableDictionary<NSString *, NSString *> *titleByThread = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *photoByThread = [NSMutableDictionary dictionary];
    for (SPKDeletedMessage *m in all) {
        NSString *tid = m.threadId;
        if (!tid.length)
            continue;
        NSMutableArray *list = byThread[tid];
        if (!list) {
            list = [NSMutableArray array];
            byThread[tid] = list;
        }
        [list addObject:m];
        if (m.senderPk.length && ![m.senderPk isEqualToString:ownerPK]) {
            NSMutableSet *s = nonOwnerSenders[tid];
            if (!s) {
                s = [NSMutableSet set];
                nonOwnerSenders[tid] = s;
            }
            [s addObject:m.senderPk];
        }
        if (m.isGroup)
            [flaggedGroupThreads addObject:tid];
        if (m.threadTitle.length && !titleByThread[tid])
            titleByThread[tid] = m.threadTitle;
        if (m.threadPhotoURL.length && !photoByThread[tid])
            photoByThread[tid] = m.threadPhotoURL;
    }

    NSMutableSet<NSString *> *groupThreads = [NSMutableSet set];
    for (NSString *tid in byThread) {
        if ([flaggedGroupThreads containsObject:tid] || nonOwnerSenders[tid].count >= 2) {
            [groupThreads addObject:tid];
        }
    }

    NSMutableArray<SPKDeletedMessageGroup *> *groups = [NSMutableArray array];

    // Group-thread entries — one per thread.
    for (NSString *tid in groupThreads) {
        NSArray<SPKDeletedMessage *> *msgs = byThread[tid];
        if (!msgs.count)
            continue;
        SPKDeletedMessageGroup *g = [SPKDeletedMessageGroup new];
        g.isGroup = YES;
        g.threadId = tid;
        g.threadTitle = titleByThread[tid].length ? titleByThread[tid] : spkGeneratedGroupTitle(msgs, ownerPK);
        g.threadPhotoURL = photoByThread[tid];
        g.messages = msgs;
        NSDictionary *flags = spkSenderFlags(g.flagKey, ownerPK);
        g.isPinned = [flags[@"pinned"] boolValue];
        g.isBlocked = [flags[@"blocked"] boolValue];
        [groups addObject:g];
    }

    // 1:1 entries — bucket the rest by sender (legacy behaviour).
    NSMutableDictionary<NSString *, NSMutableArray<SPKDeletedMessage *> *> *byPk = [NSMutableDictionary dictionary];
    for (SPKDeletedMessage *m in all) {
        if (m.threadId.length && [groupThreads containsObject:m.threadId])
            continue;
        if (!m.senderPk.length)
            continue;
        NSMutableArray *list = byPk[m.senderPk];
        if (!list) {
            list = [NSMutableArray array];
            byPk[m.senderPk] = list;
        }
        [list addObject:m];
    }
    for (NSString *pk in byPk) {
        NSArray<SPKDeletedMessage *> *msgs = byPk[pk];
        SPKDeletedMessage *latest = msgs.firstObject;
        SPKDeletedMessageGroup *g = [SPKDeletedMessageGroup new];
        g.senderPk = pk;
        g.senderUsername = latest.senderUsername;
        g.senderFullName = latest.senderFullName;
        g.senderProfilePicURL = latest.senderProfilePicURL;
        NSDictionary *flags = spkSenderFlags(pk, ownerPK);
        g.isPinned = [flags[@"pinned"] boolValue];
        g.isBlocked = [flags[@"blocked"] boolValue];
        g.messages = msgs;
        [groups addObject:g];
    }

    [groups sortUsingComparator:^NSComparisonResult(SPKDeletedMessageGroup *a, SPKDeletedMessageGroup *b) {
        if (a.isPinned != b.isPinned)
            return a.isPinned ? NSOrderedAscending : NSOrderedDescending;
        NSDate *da = a.lastDeletedAt ?: [NSDate distantPast];
        NSDate *db = b.lastDeletedAt ?: [NSDate distantPast];
        return [db compare:da];
    }];
    return groups;
}

+ (SPKDeletedMessageGroup *)groupForSenderPK:(NSString *)senderPK ownerPK:(NSString *)ownerPK {
    if (!senderPK.length)
        return nil;
    NSArray<SPKDeletedMessage *> *msgs = [self messagesForSenderPK:senderPK ownerPK:ownerPK];
    if (!msgs.count)
        return nil;
    SPKDeletedMessage *latest = msgs.firstObject; // already newest-first
    SPKDeletedMessageGroup *g = [SPKDeletedMessageGroup new];
    g.senderPk = senderPK;
    g.senderUsername = latest.senderUsername;
    g.senderFullName = latest.senderFullName;
    g.senderProfilePicURL = latest.senderProfilePicURL;
    NSDictionary *flags = spkSenderFlags(senderPK, ownerPK);
    g.isPinned = [flags[@"pinned"] boolValue];
    g.isBlocked = [flags[@"blocked"] boolValue];
    g.messages = msgs;
    return g;
}

+ (SPKDeletedMessageGroup *)groupForThreadId:(NSString *)threadId ownerPK:(NSString *)ownerPK {
    if (!threadId.length)
        return nil;
    NSArray<SPKDeletedMessage *> *all = [self allMessagesForOwnerPK:ownerPK]; // newest-first
    NSMutableArray<SPKDeletedMessage *> *msgs = [NSMutableArray array];
    NSMutableSet<NSString *> *nonOwner = [NSMutableSet set];
    BOOL flagged = NO;
    NSString *title = nil;
    NSString *photo = nil;
    NSString *fallbackSender = nil;
    for (SPKDeletedMessage *m in all) {
        if (![m.threadId isEqualToString:threadId])
            continue;
        [msgs addObject:m];
        if (m.senderPk.length && ![m.senderPk isEqualToString:ownerPK])
            [nonOwner addObject:m.senderPk];
        if (m.senderPk.length && !fallbackSender)
            fallbackSender = m.senderPk;
        if (m.isGroup)
            flagged = YES;
        if (m.threadTitle.length && !title)
            title = m.threadTitle;
        if (m.threadPhotoURL.length && !photo)
            photo = m.threadPhotoURL;
    }
    if (!msgs.count)
        return nil;

    if (flagged || nonOwner.count >= 2) {
        SPKDeletedMessageGroup *g = [SPKDeletedMessageGroup new];
        g.isGroup = YES;
        g.threadId = threadId;
        g.threadTitle = title.length ? title : spkGeneratedGroupTitle(msgs, ownerPK);
        g.threadPhotoURL = photo;
        g.messages = msgs;
        NSDictionary *flags = spkSenderFlags(g.flagKey, ownerPK);
        g.isPinned = [flags[@"pinned"] boolValue];
        g.isBlocked = [flags[@"blocked"] boolValue];
        return g;
    }

    // 1:1 — prefer the non-owner sender, else whatever sender we have.
    NSString *senderPK = nonOwner.anyObject ?: fallbackSender;
    return senderPK.length ? [self groupForSenderPK:senderPK ownerPK:ownerPK] : nil;
}

#pragma mark - Write

+ (BOOL)saveMessage:(SPKDeletedMessage *)message forOwnerPK:(NSString *)ownerPK {
    if (!message.messageId.length)
        return NO;
    return [self saveMessages:@[ message ] forOwnerPK:ownerPK];
}

+ (BOOL)saveMessages:(NSArray<SPKDeletedMessage *> *)messages forOwnerPK:(NSString *)ownerPK {
    if (!messages.count)
        return NO;
    __block BOOL ok = NO;
    dispatch_sync(spkDMQueue(), ^{
        NSString *path = spkJSONPathForOwner(ownerPK);
        NSMutableArray<SPKDeletedMessage *> *cur = [spkDecode(spkReadArray(path)) mutableCopy];
        NSMutableSet<NSString *> *incomingIds = [NSMutableSet setWithCapacity:messages.count];
        NSMutableDictionary<NSString *, SPKDeletedMessage *> *existingById = [NSMutableDictionary dictionary];
        for (SPKDeletedMessage *m in cur) {
            if (m.messageId.length)
                existingById[m.messageId] = m;
        }
        for (SPKDeletedMessage *m in messages) {
            if (!m.messageId.length)
                continue;
            SPKDeletedMessage *existing = existingById[m.messageId];
            if (!m.mediaPath.length)
                m.mediaPath = existing.mediaPath;
            if (!m.thumbnailPath.length)
                m.thumbnailPath = existing.thumbnailPath;
            if (!m.mediaMimeType.length)
                m.mediaMimeType = existing.mediaMimeType;
            if (!m.stagedMediaPath.length)
                m.stagedMediaPath = existing.stagedMediaPath;
            if (!m.stagedThumbnailPath.length)
                m.stagedThumbnailPath = existing.stagedThumbnailPath;
            [incomingIds addObject:m.messageId];
        }
        // Drop any existing record for the incoming ids (replace semantics).
        NSMutableArray<SPKDeletedMessage *> *kept = [NSMutableArray arrayWithCapacity:cur.count];
        for (SPKDeletedMessage *m in cur) {
            if (![incomingIds containsObject:m.messageId])
                [kept addObject:m];
        }
        [kept addObjectsFromArray:messages];
        [kept sortUsingComparator:^NSComparisonResult(SPKDeletedMessage *a, SPKDeletedMessage *b) {
            NSDate *da = spkSortKey(a) ?: [NSDate distantPast];
            NSDate *db = spkSortKey(b) ?: [NSDate distantPast];
            return [db compare:da];
        }];
        NSUInteger maxCount = 10000;
        if (kept.count > maxCount) {
            [kept removeObjectsInRange:NSMakeRange(maxCount, kept.count - maxCount)];
        }
        ok = spkWriteArray(path, spkEncode(kept));
    });
    if (ok)
        spkPostChanged(ownerPK);
    return ok;
}

+ (BOOL)applySenderInfo:(NSDictionary *)info
            forSenderPK:(NSString *)senderPK
                ownerPK:(NSString *)ownerPK {
    if (!senderPK.length || ![info isKindOfClass:[NSDictionary class]])
        return NO;
    NSString *u = [info[@"用户名"] isKindOfClass:[NSString class]] ? info[@"用户名"] : nil;
    NSString *fn = [info[@"full_name"] isKindOfClass:[NSString class]] ? info[@"full_name"] : nil;
    NSString *p = [info[@"profile_pic_url"] isKindOfClass:[NSString class]] ? info[@"profile_pic_url"] : nil;
    if (!u.length && !fn.length && !p.length)
        return NO;

    __block BOOL touched = NO;
    dispatch_sync(spkDMQueue(), ^{
        NSString *path = spkJSONPathForOwner(ownerPK);
        NSMutableArray<SPKDeletedMessage *> *cur = [spkDecode(spkReadArray(path)) mutableCopy];
        for (SPKDeletedMessage *m in cur) {
            if (![m.senderPk isEqualToString:senderPK])
                continue;
            if (u.length && !m.senderUsername.length) {
                m.senderUsername = u;
                touched = YES;
            }
            if (fn.length && !m.senderFullName.length) {
                m.senderFullName = fn;
                touched = YES;
            }
            if (p.length && !m.senderProfilePicURL.length) {
                m.senderProfilePicURL = p;
                touched = YES;
            }
        }
        if (touched)
            spkWriteArray(path, spkEncode(cur));
    });
    if (touched)
        spkPostChanged(ownerPK);
    return touched;
}

+ (BOOL)backfillThreadTitle:(NSString *)title
                    isGroup:(BOOL)isGroup
                   photoURL:(NSString *)photoURL
                forThreadId:(NSString *)threadId
                    ownerPK:(NSString *)ownerPK {
    if (!threadId.length)
        return NO;
    __block BOOL changed = NO;
    dispatch_sync(spkDMQueue(), ^{
        NSString *path = spkJSONPathForOwner(ownerPK);
        NSMutableArray<SPKDeletedMessage *> *cur = [spkDecode(spkReadArray(path)) mutableCopy];
        for (SPKDeletedMessage *m in cur) {
            if (![m.threadId isEqualToString:threadId])
                continue;
            if (isGroup && !m.isGroup) {
                m.isGroup = YES;
                changed = YES;
            }
            if (title.length && ![m.threadTitle isEqualToString:title]) {
                m.threadTitle = title;
                changed = YES;
            }
            if (photoURL.length && ![m.threadPhotoURL isEqualToString:photoURL]) {
                m.threadPhotoURL = photoURL;
                changed = YES;
            }
        }
        if (changed)
            spkWriteArray(path, spkEncode(cur));
    });
    if (changed)
        spkPostChanged(ownerPK);

    // This runs from the thread-metadata resolver with a *fresh* group-photo URL
    // (the live thread object). Group-photo CDN URLs can't be re-resolved by PK
    // like user avatars, so warm the shared cache now while the URL is valid —
    // the downloaded jpg then survives the URL's later expiry.
    if (isGroup && photoURL.length && threadId.length) {
        NSString *key = [@"grp_" stringByAppendingString:threadId];
        [[SPKAvatarCache shared] avatarForPK:key urlString:photoURL forceRefresh:YES completion:nil];
    }
    return changed;
}

+ (BOOL)isSenderPinned:(NSString *)senderPK ownerPK:(NSString *)ownerPK {
    return [spkSenderFlags(senderPK, ownerPK)[@"pinned"] boolValue];
}

+ (BOOL)isSenderBlocked:(NSString *)senderPK ownerPK:(NSString *)ownerPK {
    return [spkSenderFlags(senderPK, ownerPK)[@"blocked"] boolValue];
}

+ (void)setSenderPinned:(BOOL)pinned senderPK:(NSString *)senderPK ownerPK:(NSString *)ownerPK {
    if (!senderPK.length)
        return;
    dispatch_sync(spkDMQueue(), ^{
        NSMutableDictionary *flags = spkReadFlags();
        NSMutableDictionary *ownerFlags = spkFlagsForOwner(flags, ownerPK, YES);
        NSMutableDictionary *senderFlags = [ownerFlags[senderPK] isKindOfClass:[NSMutableDictionary class]]
                                               ? ownerFlags[senderPK]
                                               : ([ownerFlags[senderPK] isKindOfClass:[NSDictionary class]] ? [ownerFlags[senderPK] mutableCopy] : [NSMutableDictionary dictionary]);
        senderFlags[@"pinned"] = @(pinned);
        ownerFlags[senderPK] = senderFlags;
        spkWriteFlags(flags);
    });
    spkPostChanged(ownerPK);
}

+ (void)setSenderBlocked:(BOOL)blocked senderPK:(NSString *)senderPK ownerPK:(NSString *)ownerPK {
    if (!senderPK.length)
        return;
    dispatch_sync(spkDMQueue(), ^{
        NSMutableDictionary *flags = spkReadFlags();
        NSMutableDictionary *ownerFlags = spkFlagsForOwner(flags, ownerPK, YES);
        NSMutableDictionary *senderFlags = [ownerFlags[senderPK] isKindOfClass:[NSMutableDictionary class]]
                                               ? ownerFlags[senderPK]
                                               : ([ownerFlags[senderPK] isKindOfClass:[NSDictionary class]] ? [ownerFlags[senderPK] mutableCopy] : [NSMutableDictionary dictionary]);
        senderFlags[@"blocked"] = @(blocked);
        ownerFlags[senderPK] = senderFlags;
        spkWriteFlags(flags);
    });
    spkPostChanged(ownerPK);
}

+ (void)deleteMessageId:(NSString *)messageId forOwnerPK:(NSString *)ownerPK {
    if (!messageId.length)
        return;
    dispatch_sync(spkDMQueue(), ^{
        NSString *path = spkJSONPathForOwner(ownerPK);
        NSMutableArray<SPKDeletedMessage *> *cur = [spkDecode(spkReadArray(path)) mutableCopy];
        NSMutableArray<SPKDeletedMessage *> *kept = [NSMutableArray arrayWithCapacity:cur.count];
        for (SPKDeletedMessage *m in cur) {
            if ([m.messageId isEqualToString:messageId]) {
                if (m.mediaPath.length) {
                    [[NSFileManager defaultManager] removeItemAtPath:
                                                        [spkMediaDirForOwner(ownerPK) stringByAppendingPathComponent:m.mediaPath.lastPathComponent]
                                                               error:nil];
                }
                if (m.thumbnailPath.length) {
                    [[NSFileManager defaultManager] removeItemAtPath:
                                                        [spkMediaDirForOwner(ownerPK) stringByAppendingPathComponent:m.thumbnailPath.lastPathComponent]
                                                               error:nil];
                }
                continue;
            }
            [kept addObject:m];
        }
        spkWriteArray(path, spkEncode(kept));
    });
    spkPostChanged(ownerPK);
}

+ (void)deleteMessagesForSenderPK:(NSString *)senderPK ownerPK:(NSString *)ownerPK {
    if (!senderPK.length)
        return;
    NSArray *toDrop = [self messagesForSenderPK:senderPK ownerPK:ownerPK];
    for (SPKDeletedMessage *m in toDrop) {
        [self deleteMessageId:m.messageId forOwnerPK:ownerPK];
    }
}

+ (void)deleteMessagesForThreadId:(NSString *)threadId ownerPK:(NSString *)ownerPK {
    if (!threadId.length)
        return;
    NSArray *toDrop = [self messagesForThreadId:threadId ownerPK:ownerPK];
    for (SPKDeletedMessage *m in toDrop) {
        [self deleteMessageId:m.messageId forOwnerPK:ownerPK];
    }
}

+ (void)resetForOwnerPK:(NSString *)ownerPK {
    dispatch_sync(spkDMQueue(), ^{
        [[NSFileManager defaultManager] removeItemAtPath:spkJSONPathForOwner(ownerPK) error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:spkMediaDirForOwner(ownerPK) error:nil];
        NSMutableDictionary *flags = spkReadFlags();
        [flags removeObjectForKey:spkSafePK(ownerPK)];
        spkWriteFlags(flags);
    });
    spkPostChanged(ownerPK);
}

+ (void)resetAll {
    dispatch_sync(spkDMQueue(), ^{
        [[NSFileManager defaultManager] removeItemAtPath:spkStorageDir() error:nil];
    });
    spkPostChanged(nil);
}

#pragma mark - Media

+ (NSString *)absolutePathForRelativePath:(NSString *)relativePath ownerPK:(NSString *)ownerPK {
    if (!relativePath.length)
        return nil;
    return [spkMediaDirForOwner(ownerPK) stringByAppendingPathComponent:relativePath.lastPathComponent];
}

+ (NSString *)reserveRelativeMediaPathForMessageId:(NSString *)messageId
                                         extension:(NSString *)ext
                                           ownerPK:(NSString *)ownerPK {
    NSString *safeId = [messageId stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    NSString *cleanExt = ext.length ? ([ext hasPrefix:@"."] ? [ext substringFromIndex:1] : ext) : @"bin";
    NSString *fname = [NSString stringWithFormat:@"%@.%@", safeId, cleanExt];
    // Touch the dir so callers can write straight away.
    (void)spkMediaDirForOwner(ownerPK);
    return fname;
}

+ (unsigned long long)mediaSizeBytesForOwnerPK:(NSString *)ownerPK {
    return spkDirectorySize(spkMediaDirForOwner(ownerPK));
}

#pragma mark - Pending reconciliation and media recovery cache

+ (BOOL)savePendingCandidateSnapshot:(NSDictionary *)snapshot forOwnerPK:(NSString *)ownerPK {
    NSString *messageId = [snapshot[@"message_id"] isKindOfClass:[NSString class]] ? snapshot[@"message_id"] : nil;
    if (!messageId.length)
        return NO;
    __block BOOL ok = NO;
    dispatch_sync(spkDMQueue(), ^{
        NSString *path = spkPendingJSONPath(kSPKDMPendingCandidatesDir, ownerPK);
        NSMutableDictionary *all = spkReadDictionary(path);
        NSMutableDictionary *merged = [all[messageId] isKindOfClass:[NSDictionary class]]
                                          ? [all[messageId] mutableCopy]
                                          : [NSMutableDictionary dictionary];
        [merged addEntriesFromDictionary:snapshot];
        all[messageId] = merged;
        ok = spkWriteDictionary(path, all);
    });
    return ok;
}

+ (NSDictionary *)pendingCandidateSnapshotForMessageId:(NSString *)messageId ownerPK:(NSString *)ownerPK {
    if (!messageId.length)
        return nil;
    __block NSDictionary *result = nil;
    dispatch_sync(spkDMQueue(), ^{
        id candidate = spkReadDictionary(spkPendingJSONPath(kSPKDMPendingCandidatesDir, ownerPK))[messageId];
        if ([candidate isKindOfClass:[NSDictionary class]])
            result = [candidate copy];
    });
    return result;
}

+ (BOOL)patchPendingCandidateForMessageId:(NSString *)messageId values:(NSDictionary *)values ownerPK:(NSString *)ownerPK {
    if (!messageId.length || !values.count)
        return NO;
    __block BOOL ok = NO;
    dispatch_sync(spkDMQueue(), ^{
        NSString *path = spkPendingJSONPath(kSPKDMPendingCandidatesDir, ownerPK);
        NSMutableDictionary *all = spkReadDictionary(path);
        NSMutableDictionary *candidate = [all[messageId] isKindOfClass:[NSDictionary class]]
                                             ? [all[messageId] mutableCopy]
                                             : nil;
        if (!candidate)
            return;
        BOOL stagesMedia = values[@"staged_media_path"] != nil || values[@"staged_thumbnail_path"] != nil;
        if (stagesMedia && [candidate[@"staging_disabled"] boolValue])
            return;
        [candidate addEntriesFromDictionary:values];
        all[messageId] = candidate;
        ok = spkWriteDictionary(path, all);
    });
    return ok;
}

+ (void)removePendingCandidateForMessageId:(NSString *)messageId ownerPK:(NSString *)ownerPK {
    if (!messageId.length)
        return;
    dispatch_sync(spkDMQueue(), ^{
        NSString *path = spkPendingJSONPath(kSPKDMPendingCandidatesDir, ownerPK);
        NSMutableDictionary *all = spkReadDictionary(path);
        [all removeObjectForKey:messageId];
        spkWriteDictionary(path, all);
    });
}

+ (BOOL)savePendingRemovalForMessageId:(NSString *)messageId
                              threadId:(NSString *)threadId
                            mutationId:(NSString *)mutationId
                               ownerPK:(NSString *)ownerPK {
    if (!messageId.length)
        return NO;
    __block BOOL ok = NO;
    dispatch_sync(spkDMQueue(), ^{
        NSString *path = spkPendingJSONPath(kSPKDMPendingRemovalsDir, ownerPK);
        NSMutableDictionary *all = spkReadDictionary(path);
        NSMutableDictionary *entry = [all[messageId] isKindOfClass:[NSDictionary class]]
                                         ? [all[messageId] mutableCopy]
                                         : [NSMutableDictionary dictionary];
        entry[@"message_id"] = messageId;
        if (threadId.length)
            entry[@"thread_id"] = threadId;
        if (mutationId.length)
            entry[@"mutation_id"] = mutationId;
        if (!entry[@"created_at"])
            entry[@"created_at"] = @([NSDate date].timeIntervalSince1970);
        all[messageId] = entry;
        ok = spkWriteDictionary(path, all);
    });
    return ok;
}

+ (NSArray<NSDictionary *> *)pendingRemovalsForOwnerPK:(NSString *)ownerPK {
    __block NSArray *result = nil;
    dispatch_sync(spkDMQueue(), ^{
        result = [spkReadDictionary(spkPendingJSONPath(kSPKDMPendingRemovalsDir, ownerPK)).allValues copy];
    });
    return result ?: @[];
}

+ (void)removePendingRemovalForMessageId:(NSString *)messageId ownerPK:(NSString *)ownerPK {
    if (!messageId.length)
        return;
    dispatch_sync(spkDMQueue(), ^{
        NSString *path = spkPendingJSONPath(kSPKDMPendingRemovalsDir, ownerPK);
        NSMutableDictionary *all = spkReadDictionary(path);
        [all removeObjectForKey:messageId];
        spkWriteDictionary(path, all);
    });
}

+ (NSString *)reserveRelativeStagedMediaPathForMessageId:(NSString *)messageId
                                               extension:(NSString *)ext
                                                 ownerPK:(NSString *)ownerPK
                                               thumbnail:(BOOL)thumbnail {
    NSString *safeId = [messageId stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    NSString *cleanExt = ext.length ? ([ext hasPrefix:@"."] ? [ext substringFromIndex:1] : ext) : @"bin";
    (void)spkStagedMediaDirForOwner(ownerPK);
    return [NSString stringWithFormat:@"%@%@.%@", thumbnail ? @"thumb_" : @"", safeId, cleanExt];
}

+ (NSString *)absoluteStagedPathForRelativePath:(NSString *)relativePath ownerPK:(NSString *)ownerPK {
    if (!relativePath.length)
        return nil;
    return [spkStagedMediaDirForOwner(ownerPK) stringByAppendingPathComponent:relativePath.lastPathComponent];
}

+ (NSString *)promoteStagedRelativePath:(NSString *)relativePath
                              messageId:(NSString *)messageId
                                ownerPK:(NSString *)ownerPK
                              thumbnail:(BOOL)thumbnail {
    if (!relativePath.length || !messageId.length)
        return nil;
    NSString *source = [self absoluteStagedPathForRelativePath:relativePath ownerPK:ownerPK];
    if (![[NSFileManager defaultManager] fileExistsAtPath:source])
        return nil;
    NSString *baseId = thumbnail ? [@"thumb_" stringByAppendingString:messageId] : messageId;
    NSString *destinationRel = [self reserveRelativeMediaPathForMessageId:baseId extension:relativePath.pathExtension ownerPK:ownerPK];
    NSString *destination = [self absolutePathForRelativePath:destinationRel ownerPK:ownerPK];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:destination]) {
        if (![fm moveItemAtPath:source toPath:destination error:nil])
            return nil;
    } else {
        [fm removeItemAtPath:source error:nil];
    }
    return destinationRel;
}

+ (unsigned long long)stagedMediaSizeBytesForOwnerPK:(NSString *)ownerPK {
    return spkDirectorySize(spkStagedMediaDirForOwner(ownerPK));
}

+ (void)clearStagedMediaForOwnerPK:(NSString *)ownerPK {
    dispatch_sync(spkDMQueue(), ^{
        [[NSFileManager defaultManager] removeItemAtPath:spkStagedMediaDirForOwner(ownerPK) error:nil];
        NSString *path = spkPendingJSONPath(kSPKDMPendingCandidatesDir, ownerPK);
        NSMutableDictionary *all = spkReadDictionary(path);
        for (NSString *key in all.allKeys) {
            NSMutableDictionary *candidate = [all[key] mutableCopy];
            [candidate removeObjectForKey:@"staged_media_path"];
            [candidate removeObjectForKey:@"staged_thumbnail_path"];
            candidate[@"staging_disabled"] = @YES;
            all[key] = candidate;
        }
        spkWriteDictionary(path, all);
    });
    spkPostChanged(ownerPK);
}

+ (NSString *)storageRootPath {
    return spkStorageDir();
}

+ (BOOL)replaceStorageWithDirectoryAtPath:(NSString *)sourcePath error:(NSError **)error {
    if (sourcePath.length == 0)
        return NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *destination = spkStorageDir();
    if ([fm fileExistsAtPath:destination] && ![fm removeItemAtPath:destination error:error]) {
        return NO;
    }
    NSString *parent = [destination stringByDeletingLastPathComponent];
    [fm createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:nil];
    BOOL copied = [fm copyItemAtPath:sourcePath toPath:destination error:error];
    if (copied)
        spkPostChanged(nil);
    return copied;
}

+ (NSInteger)mergeFromStorageDirectory:(NSString *)sourcePath
                         ownerFilterPK:(NSString *)ownerFilterPK
                                 error:(NSError **)error {
    if (sourcePath.length == 0)
        return 0;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:sourcePath error:error];
    if (!entries)
        return -1;

    NSInteger added = 0;
    for (NSString *entry in entries) {
        if (![entry.pathExtension isEqualToString:@"json"])
            continue;
        if ([entry isEqualToString:kSPKDMSenderFlagsFile])
            continue;
        NSString *ownerPK = [entry stringByDeletingPathExtension]; // "<pk>.json"
        if (ownerFilterPK.length > 0 && ![ownerPK isEqualToString:spkSafePK(ownerFilterPK)])
            continue;

        NSArray<SPKDeletedMessage *> *incoming = spkDecode(spkReadArray([sourcePath stringByAppendingPathComponent:entry]));
        if (incoming.count == 0)
            continue;

        // Count genuinely-new messages (saveMessages: replaces by id, so existing ones don't grow the log).
        NSMutableSet<NSString *> *existingIds = [NSMutableSet set];
        for (SPKDeletedMessage *m in [self allMessagesForOwnerPK:ownerPK]) {
            if (m.messageId.length)
                [existingIds addObject:m.messageId];
        }
        for (SPKDeletedMessage *m in incoming) {
            if (m.messageId.length && ![existingIds containsObject:m.messageId])
                added++;
        }

        // Copy this owner's media before saving the records that reference it.
        NSString *srcMediaDir = [[sourcePath stringByAppendingPathComponent:kSPKDMMediaDir] stringByAppendingPathComponent:ownerPK];
        NSString *dstMediaDir = spkMediaDirForOwner(ownerPK);
        for (NSString *file in [fm contentsOfDirectoryAtPath:srcMediaDir error:nil]) {
            NSString *dst = [dstMediaDir stringByAppendingPathComponent:file];
            if (![fm fileExistsAtPath:dst]) {
                [fm copyItemAtPath:[srcMediaDir stringByAppendingPathComponent:file] toPath:dst error:nil];
            }
        }

        [self saveMessages:incoming forOwnerPK:ownerPK]; // merges by messageId
    }

    // Sender flags: fill in entries we don't already have (never overwrite local).
    NSString *srcFlags = [sourcePath stringByAppendingPathComponent:kSPKDMSenderFlagsFile];
    if ([fm fileExistsAtPath:srcFlags]) {
        dispatch_sync(spkDMQueue(), ^{
            NSMutableDictionary *live = spkReadDictionary(spkFlagsPath());
            NSDictionary *incoming = spkReadDictionary(srcFlags);
            BOOL changed = NO;
            for (NSString *key in incoming) {
                if (ownerFilterPK.length > 0 && ![key isEqualToString:spkSafePK(ownerFilterPK)])
                    continue;
                if (!live[key]) {
                    live[key] = incoming[key];
                    changed = YES;
                }
            }
            if (changed)
                spkWriteDictionary(spkFlagsPath(), live);
        });
    }

    spkPostChanged(nil);
    return added;
}

@end
