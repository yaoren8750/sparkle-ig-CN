#import "SPKDirectSeenContext.h"

#import <objc/message.h>

#import "../../AssetUtils.h"
#import "../../Networking/SPKInstagramAPI.h"
#import "../../Shared/UI/SPKIGAlertPresenter.h"
#import "../../Shared/UI/SPKMediaChrome.h"
#import "../../Shared/UI/SPKUserListViewController.h"
#import "../../Shared/UI/SPKNotificationCenter.h"
#import "../../Utils.h"
#import "SPKDirectUserResolver.h"

@implementation SPKDirectThreadContext
- (instancetype)init {
    if ((self = [super init])) {
        _users = @[];
    }
    return self;
}
@end

static SPKDirectThreadContext *SPKDirectActiveContext;
static NSArray<NSDictionary *> *SPKDirectManualSeenThreadsCache;
static NSSet<NSString *> *SPKDirectManualSeenThreadIdsCache;
// Effective defaults key the caches were built from; when the current mode or
// account produces a different key, the caches are rebuilt.
static NSString *SPKDirectManualSeenCachedKey;
BOOL SPKDirectSeenDebugPrintEnabled = NO;

static id SPKDirectKVCObject(id target, NSString *key) {
    if (!target || key.length == 0)
        return nil;
    @try {
        return [target valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id SPKDirectObjectForSelector(id target, NSString *selectorName) {
    if (!target || selectorName.length == 0)
        return nil;
    SEL selector = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:selector])
        return nil;

    NSMethodSignature *sig = [target methodSignatureForSelector:selector];
    if (!sig)
        return nil;

    const char *returnType = [sig methodReturnType];
    if (returnType == NULL)
        return nil;

    if (strcmp(returnType, "@") == 0) {
        return ((id (*)(id, SEL))objc_msgSend)(target, selector);
    }

    if (strcmp(returnType, "c") == 0 || strcmp(returnType, "B") == 0) {
        BOOL val = ((BOOL (*)(id, SEL))objc_msgSend)(target, selector);
        return @(val);
    }
    if (strcmp(returnType, "i") == 0 || strcmp(returnType, "I") == 0 ||
        strcmp(returnType, "s") == 0 || strcmp(returnType, "S") == 0) {
        int val = ((int (*)(id, SEL))objc_msgSend)(target, selector);
        return @(val);
    }
    if (strcmp(returnType, "l") == 0 || strcmp(returnType, "L") == 0 ||
        strcmp(returnType, "q") == 0 || strcmp(returnType, "Q") == 0) {
        long long val = ((long long (*)(id, SEL))objc_msgSend)(target, selector);
        return @(val);
    }
    if (strcmp(returnType, "f") == 0) {
        float val = ((float (*)(id, SEL))objc_msgSend)(target, selector);
        return @(val);
    }
    if (strcmp(returnType, "d") == 0) {
        double val = ((double (*)(id, SEL))objc_msgSend)(target, selector);
        return @(val);
    }

    return nil;
}

static NSString *SPKDirectStringFromValue(id value) {
    if (!value || value == (id)kCFNull)
        return nil;
    if ([value isKindOfClass:[NSString class]]) {
        NSString *string = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        return string.length > 0 ? string : nil;
    }
    if ([value respondsToSelector:@selector(stringValue)]) {
        NSString *string = [[value stringValue] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        return string.length > 0 ? string : nil;
    }
    NSString *description = [[value description] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return description.length > 0 ? description : nil;
}

static NSString *SPKDirectFirstStringForSelectors(id target, NSArray<NSString *> *selectors) {
    for (NSString *selectorName in selectors) {
        NSString *value = SPKDirectStringFromValue(SPKDirectObjectForSelector(target, selectorName));
        if (value.length == 0)
            value = SPKDirectStringFromValue(SPKDirectKVCObject(target, selectorName));
        if (value.length > 0)
            return value;
    }
    return nil;
}

static NSString *SPKDirectThreadIdDirectlyFromObject(id object) {
    if (!object)
        return nil;
    NSString *threadId = SPKDirectFirstStringForSelectors(object, @[ @"threadId", @"threadID", @"thread_id" ]);
    if (threadId.length == 0 && [object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)object;
        threadId = SPKDirectStringFromValue(dict[@"threadId"] ?: dict[@"thread_id"]);
    }
    return threadId;
}

static NSNumber *SPKDirectFirstNumberForSelectors(id target, NSArray<NSString *> *selectors) {
    for (NSString *selectorName in selectors) {
        id value = SPKDirectObjectForSelector(target, selectorName);
        if (!value)
            value = SPKDirectKVCObject(target, selectorName);
        if ([value respondsToSelector:@selector(boolValue)])
            return @([value boolValue]);
    }
    return nil;
}

static NSArray *SPKDirectArrayFromCollection(id collection) {
    if (!collection ||
        [collection isKindOfClass:[NSString class]] ||
        [collection isKindOfClass:[NSDictionary class]] ||
        [collection isKindOfClass:[NSURL class]]) {
        return nil;
    }
    if ([collection isKindOfClass:[NSArray class]])
        return collection;
    if ([collection isKindOfClass:[NSOrderedSet class]])
        return [(NSOrderedSet *)collection array];
    if ([collection isKindOfClass:[NSSet class]])
        return [(NSSet *)collection allObjects];
    if ([collection conformsToProtocol:@protocol(NSFastEnumeration)]) {
        NSMutableArray *array = [NSMutableArray array];
        for (id item in collection)
            [array addObject:item];
        return array;
    }
    return nil;
}

static NSArray<NSDictionary *> *SPKDirectUsersFromObject(id object) {
    NSMutableArray<NSDictionary *> *users = [NSMutableArray array];
    NSArray<NSString *> *selectors = @[
        @"users",
        @"threadUsers",
        @"recentlyActiveUsers",
        @"participants",
        @"recipientUsers"
    ];

    for (NSString *selectorName in selectors) {
        id collection = SPKDirectObjectForSelector(object, selectorName);
        if (!collection)
            collection = SPKDirectKVCObject(object, selectorName);
        NSArray *rawUsers = SPKDirectArrayFromCollection(collection);
        if (rawUsers.count == 0)
            continue;

        for (id user in rawUsers) {
            NSString *pk = SPKDirectFirstStringForSelectors(user, @[ @"pk", @"userId", @"userID", @"id" ]);
            NSString *username = SPKDirectFirstStringForSelectors(user, @[ @"用户名", @"userName" ]);
            NSString *fullName = SPKDirectFirstStringForSelectors(user, @[ @"fullName", @"full_name", @"name" ]);
            NSMutableDictionary *entry = [NSMutableDictionary dictionary];
            if (pk.length > 0)
                entry[@"pk"] = pk;
            if (username.length > 0)
                entry[@"用户名"] = username;
            if (fullName.length > 0)
                entry[@"fullName"] = fullName;
            NSString *profilePicUrl = spkDirectUserResolverProfilePicURLStringFromUser(user);
            if (profilePicUrl.length > 0)
                entry[@"profilePicUrl"] = profilePicUrl;
            if (entry.count > 0)
                [users addObject:entry];
        }

        if (users.count > 0)
            break;
    }

    return users.copy;
}

// Pulls the group's custom photo URL from a thread / metadata object via
// groupMetadata → groupPhotoIdentifier → groupImageSpecifier → remoteImageURL.
// `target` may be the thread, its provider, or the thread metadata itself.
static NSString *SPKDirectGroupPhotoURLFromTarget(id target) {
    if (!target)
        return nil;
    @try {
        id groupMeta = SPKDirectObjectForSelector(target, @"groupMetadata") ?: target;
        id photoId = SPKDirectObjectForSelector(groupMeta, @"groupPhotoIdentifier");
        if (!photoId)
            return nil;
        id specifier = SPKDirectObjectForSelector(photoId, @"groupImageSpecifier");
        id remoteUrl = specifier ? SPKDirectObjectForSelector(specifier, @"remoteImageURL") : nil;
        id url = remoteUrl ? SPKDirectObjectForSelector(remoteUrl, @"url") : nil;
        if ([url isKindOfClass:[NSURL class]])
            return ((NSURL *)url).absoluteString;
        if ([url isKindOfClass:[NSString class]] && [(NSString *)url length])
            return url;
    } @catch (__unused id e) {
    }
    return nil;
}

static NSString *SPKDirectNameFromUsers(NSArray<NSDictionary *> *users) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSDictionary *user in users) {
        NSString *username = [user[@"用户名"] isKindOfClass:[NSString class]] ? user[@"用户名"] : nil;
        NSString *fullName = [user[@"fullName"] isKindOfClass:[NSString class]] ? user[@"fullName"] : nil;
        NSString *name = fullName.length > 0 ? fullName : (username.length > 0 ? [@"@" stringByAppendingString:username] : nil);
        if (name.length > 0)
            [names addObject:name];
    }
    return names.count > 0 ? [names componentsJoinedByString:@", "] : nil;
}

static NSString *SPKDirectNormalizeUsername(NSString *username) {
    NSString *trimmed = [[username ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    if ([trimmed hasPrefix:@"@"])
        trimmed = [trimmed substringFromIndex:1];
    return trimmed;
}

static NSString *SPKDirectCleanFullName(NSString *fullName, NSString *username) {
    NSString *cleanName = [SPKDirectStringFromValue(fullName) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *normalizedUsername = SPKDirectNormalizeUsername(username);
    if (cleanName.length == 0)
        return nil;
    if ([SPKDirectNormalizeUsername(cleanName) isEqualToString:normalizedUsername])
        return nil;
    return cleanName;
}

static SPKDirectThreadContext *SPKDirectThreadContextFromSourceInternal(id source, NSMutableSet<NSValue *> *visited, BOOL allowActiveFallback);

static SPKDirectThreadContext *SPKDirectContextDirectlyFromObject(id object) {
    if (!object)
        return nil;

    id target = object;

    // Resolve threadInfoProvider (e.g. from IGDirectThreadViewController, or via _threadSession)
    id provider = [SPKUtils getIvarForObj:object name:"_threadInfoProvider"];
    if (!provider) {
        provider = SPKDirectObjectForSelector(object, @"threadInfoProvider");
    }
    if (!provider) {
        id threadSession = [SPKUtils getIvarForObj:object name:"_threadSession"];
        if (threadSession) {
            provider = [SPKUtils getIvarForObj:threadSession name:"_threadInfoProvider"];
            if (!provider)
                provider = SPKDirectObjectForSelector(threadSession, @"threadInfoProvider");
        }
    }
    if (!provider) {
        id vcCtx = [SPKUtils getIvarForObj:object name:"_threadViewControllerContext"];
        if (!vcCtx)
            vcCtx = SPKDirectObjectForSelector(object, @"threadViewControllerContext");
        if (vcCtx) {
            provider = SPKDirectObjectForSelector(vcCtx, @"threadInfoProvider");
        }
    }
    if (provider) {
        target = provider;
    }

    id metadata = nil;
    if ([target respondsToSelector:NSSelectorFromString(@"threadMetadata")]) {
        id meta = SPKDirectObjectForSelector(target, @"threadMetadata");
        if (meta) {
            metadata = meta;
            target = meta;
        }
    }

    NSString *threadId = SPKDirectThreadIdDirectlyFromObject(target);
    if (threadId.length == 0 && target != object) {
        threadId = SPKDirectThreadIdDirectlyFromObject(object);
    }
    if (threadId.length == 0 && [object respondsToSelector:NSSelectorFromString(@"threadKey")]) {
        id key = SPKDirectObjectForSelector(object, @"threadKey");
        threadId = SPKDirectThreadIdDirectlyFromObject(key);
    }
    if (threadId.length == 0)
        return nil;

    NSArray<NSDictionary *> *users = SPKDirectUsersFromObject(target);
    if (users.count == 0 && target != object) {
        users = SPKDirectUsersFromObject(object);
    }

    NSString *threadName = SPKDirectFirstStringForSelectors(target, @[ @"threadName", @"threadTitle", @"title", @"name" ]);
    if (threadName.length == 0 && [object isKindOfClass:[UIViewController class]]) {
        threadName = ((UIViewController *)object).navigationItem.title;
    }
    if (threadName.length == 0 && [object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)object;
        threadName = SPKDirectStringFromValue(dict[@"threadName"] ?: dict[@"thread_title"] ?
                                                                                           : dict[@"title"]);
    }
    if (threadName.length == 0 && target != object) {
        threadName = SPKDirectFirstStringForSelectors(object, @[ @"threadName", @"threadTitle", @"title", @"name" ]);
    }
    if (threadName.length == 0)
        threadName = SPKDirectNameFromUsers(users);

    NSNumber *isGroupValue = SPKDirectFirstNumberForSelectors(target, @[ @"isGroup", @"isGroupThread", @"groupThread" ]);
    if (!isGroupValue && [object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)object;
        id raw = dict[@"isGroup"] ?: dict[@"is_group"] ?
                                                       : dict[@"is_group_thread"];
        if ([raw respondsToSelector:@selector(boolValue)])
            isGroupValue = @([raw boolValue]);
    }
    if (!isGroupValue && target != object) {
        isGroupValue = SPKDirectFirstNumberForSelectors(object, @[ @"isGroup", @"isGroupThread", @"groupThread" ]);
    }

    if (SPKDirectSeenDebugPrintEnabled) {
        SPKLog(@"消息", @"SPKDirectContextDirectlyFromObject: object=%@ provider=%@ metadata=%@ target=%@ threadId=%@ name=%@ usersCount=%lu users=%@",
               NSStringFromClass([object class]),
               provider ? NSStringFromClass([provider class]) : @"nil",
               metadata ? NSStringFromClass([metadata class]) : @"nil",
               NSStringFromClass([target class]),
               threadId,
               threadName,
               (unsigned long)users.count,
               users);
    }

    SPKDirectThreadContext *context = [SPKDirectThreadContext new];
    context.threadId = threadId;
    context.threadName = threadName ?: @"";
    context.isGroup = [isGroupValue boolValue];
    context.users = users ?: @[];

    if (context.isGroup) {
        context.groupPhotoUrl = SPKDirectGroupPhotoURLFromTarget(target)
                                    ?: SPKDirectGroupPhotoURLFromTarget(object);
    }

    return context;
}

static SPKDirectThreadContext *SPKDirectThreadContextFromSourceInternal(id source, NSMutableSet<NSValue *> *visited, BOOL allowActiveFallback) {
    if (!source)
        return allowActiveFallback ? SPKDirectActiveContext : nil;

    NSValue *pointerValue = [NSValue valueWithNonretainedObject:source];
    if ([visited containsObject:pointerValue])
        return nil;
    [visited addObject:pointerValue];

    SPKDirectThreadContext *context = SPKDirectContextDirectlyFromObject(source);
    if (context.threadId.length > 0)
        return context;

    if ([source isKindOfClass:[UIView class]]) {
        context = SPKDirectThreadContextFromSourceInternal([SPKUtils nearestViewControllerForView:(UIView *)source], visited, NO);
        if (context.threadId.length > 0)
            return context;
    }

    if ([source isKindOfClass:[UIViewController class]]) {
        UIViewController *viewController = (UIViewController *)source;
        context = SPKDirectThreadContextFromSourceInternal(viewController.parentViewController, visited, NO);
        if (context.threadId.length > 0)
            return context;
        context = SPKDirectThreadContextFromSourceInternal(viewController.navigationController, visited, NO);
        if (context.threadId.length > 0)
            return context;
        for (UIViewController *child in viewController.childViewControllers) {
            context = SPKDirectThreadContextFromSourceInternal(child, visited, NO);
            if (context.threadId.length > 0)
                return context;
        }
    }

    for (NSString *key in @[
             @"_thread",
             @"thread",
             @"_directThread",
             @"directThread",
             @"_threadInfoProvider",
             @"threadInfoProvider",
             @"_threadViewController",
             @"threadViewController",
             @"_messageListViewController",
             @"messageListViewController",
             @"_directMessageListViewController",
             @"directMessageListViewController",
             @"_messageListDataSource",
             @"messageListDataSource",
             @"_dataSource",
             @"dataSource",
             @"_stateProvider",
             @"stateProvider",
             @"_delegate",
             @"delegate",
             @"_viewModel",
             @"viewModel",
             @"_item",
             @"item"
         ]) {
        id candidate = [key hasPrefix:@"_"] ? [SPKUtils getIvarForObj:source name:key.UTF8String] : SPKDirectKVCObject(source, key);
        context = SPKDirectThreadContextFromSourceInternal(candidate, visited, NO);
        if (context.threadId.length > 0)
            return context;
    }

    return allowActiveFallback ? SPKDirectActiveContext : nil;
}

// A source deep in the DM stack -- the visual-message viewer, a cell -- can usually reach
// a thread id but nothing else: only the thread view controller owns the info provider
// that carries the title and roster. The active context IS that controller's, so borrow
// what's missing from it whenever the ids agree. Without this the viewer resolves a
// nameless context and every prompt/list row built from it reads "Unknown Chat".
static SPKDirectThreadContext *SPKDirectContextEnrichedFromActiveContext(SPKDirectThreadContext *context) {
    SPKDirectThreadContext *active = SPKDirectActiveContext;
    if (!context || !active || context == active)
        return context;

    NSString *threadId = SPKDirectStringFromValue(context.threadId);
    if (threadId.length == 0 || ![threadId isEqualToString:SPKDirectStringFromValue(active.threadId)])
        return context;

    if (context.users.count == 0)
        context.users = active.users;
    if (context.threadName.length == 0)
        context.threadName = active.threadName.length > 0 ? active.threadName : SPKDirectNameFromUsers(context.users);
    if (context.groupPhotoUrl.length == 0)
        context.groupPhotoUrl = active.groupPhotoUrl;
    if (!context.isGroup)
        context.isGroup = active.isGroup;
    return context;
}

SPKDirectThreadContext *SPKDirectThreadContextFromSource(id source) {
    return SPKDirectContextEnrichedFromActiveContext(
        SPKDirectThreadContextFromSourceInternal(source, [NSMutableSet set], YES));
}

NSString *SPKDirectDisplayNameForThreadEntry(NSDictionary *entry) {
    if (![entry isKindOfClass:[NSDictionary class]])
        return nil;
    NSString *threadName = SPKDirectStringFromValue(entry[@"threadName"]);
    if (threadName.length > 0)
        return threadName;
    return SPKDirectNameFromUsers([entry[@"users"] isKindOfClass:[NSArray class]] ? entry[@"users"] : @[]);
}

NSString *SPKDirectParticipantSubtitleForThreadEntry(NSDictionary *entry) {
    if (![entry isKindOfClass:[NSDictionary class]] || ![entry[@"isGroup"] boolValue])
        return nil;
    NSArray *users = [entry[@"users"] isKindOfClass:[NSArray class]] ? entry[@"users"] : @[];
    NSUInteger count = users.count;
    if (count == 0)
        return nil;

    // IG's recipient list excludes the current user, so add yourself back to report the
    // real member count. Only when we actually have the roster.
    NSString *currentPk = [SPKUtils currentUserPK];
    if (currentPk.length > 0) {
        BOOL includesSelf = NO;
        for (NSDictionary *user in users) {
            if ([SPKDirectStringFromValue(user[@"pk"]) isEqualToString:currentPk]) {
                includesSelf = YES;
                break;
            }
        }
        if (!includesSelf)
            count += 1;
    }
    return [NSString stringWithFormat:@"%lu participant%@", (unsigned long)count, count == 1 ? @"" : @"s"];
}

void SPKDirectOpenProfileForThreadEntry(NSDictionary *entry) {
    if (![entry isKindOfClass:[NSDictionary class]] || [entry[@"isGroup"] boolValue])
        return;
    NSArray *users = [entry[@"users"] isKindOfClass:[NSArray class]] ? entry[@"users"] : @[];
    if (users.count != 1)
        return;
    NSDictionary *userDict = users.firstObject;
    NSString *username = SPKDirectStringFromValue(userDict[@"用户名"]);
    NSString *pk = SPKDirectStringFromValue(userDict[@"pk"]);
    if (username.length > 0 || pk.length > 0)
        [SPKUtils openInstagramProfileForUser:nil pk:pk username:username fromViewController:nil];
}

NSString *SPKDirectDisplayNameForThreadContext(SPKDirectThreadContext *context) {
    NSString *threadName = SPKDirectStringFromValue(context.threadName);
    if (threadName.length > 0)
        return threadName;
    return SPKDirectNameFromUsers(context.users ?: @[]);
}

static id SPKDirectInboxValueForKeys(id candidate, NSArray<NSString *> *keys) {
    if (!candidate)
        return nil;
    for (NSString *key in keys) {
        id value = nil;
        if ([candidate isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = (NSDictionary *)candidate;
            value = dict[key];
            if (!value && [key containsString:@"_"]) {
                NSString *camelKey = [key stringByReplacingOccurrencesOfString:@"_" withString:@""];
                value = dict[camelKey];
            }
        } else {
            value = SPKDirectKVCObject(candidate, key);
            if (!value) {
                NSString *ivarKey = [@"_" stringByAppendingString:key];
                value = [SPKUtils getIvarForObj:candidate name:ivarKey.UTF8String];
            }
        }
        if (value && value != (id)kCFNull)
            return value;
    }
    return nil;
}

static SPKDirectThreadContext *SPKDirectContextFromShallowInboxObject(id object) {
    if (!object)
        return nil;

    id target = object;

    id provider = [SPKUtils getIvarForObj:object name:"_threadInfoProvider"];
    if (!provider)
        provider = SPKDirectObjectForSelector(object, @"threadInfoProvider");
    if (!provider) {
        id threadSession = [SPKUtils getIvarForObj:object name:"_threadSession"];
        if (threadSession) {
            provider = [SPKUtils getIvarForObj:threadSession name:"_threadInfoProvider"];
            if (!provider)
                provider = SPKDirectObjectForSelector(threadSession, @"threadInfoProvider");
        }
    }
    if (!provider) {
        id vcCtx = [SPKUtils getIvarForObj:object name:"_threadViewControllerContext"];
        if (!vcCtx)
            vcCtx = SPKDirectObjectForSelector(object, @"threadViewControllerContext");
        if (vcCtx) {
            provider = SPKDirectObjectForSelector(vcCtx, @"threadInfoProvider");
        }
    }
    if (provider) {
        target = provider;
    }

    if ([target respondsToSelector:NSSelectorFromString(@"threadMetadata")]) {
        id meta = SPKDirectObjectForSelector(target, @"threadMetadata");
        if (meta)
            target = meta;
    }

    NSString *threadId = SPKDirectStringFromValue(SPKDirectInboxValueForKeys(target, @[ @"threadId", @"threadID", @"thread_id" ]));
    if (threadId.length == 0 && target != object) {
        threadId = SPKDirectStringFromValue(SPKDirectInboxValueForKeys(object, @[ @"threadId", @"threadID", @"thread_id" ]));
    }
    if (threadId.length == 0)
        return nil;

    NSString *threadName = SPKDirectStringFromValue(SPKDirectInboxValueForKeys(target, @[ @"threadName", @"threadTitle", @"thread_title", @"title", @"name" ]));
    if (threadName.length == 0 && target != object) {
        threadName = SPKDirectStringFromValue(SPKDirectInboxValueForKeys(object, @[ @"threadName", @"threadTitle", @"thread_title", @"title", @"name" ]));
    }

    id isGroupValue = SPKDirectInboxValueForKeys(target, @[ @"isGroup", @"isGroupThread", @"groupThread", @"is_group", @"is_group_thread" ]);
    if (!isGroupValue && target != object) {
        isGroupValue = SPKDirectInboxValueForKeys(object, @[ @"isGroup", @"isGroupThread", @"groupThread", @"is_group", @"is_group_thread" ]);
    }

    NSArray<NSDictionary *> *users = SPKDirectUsersFromObject(target);
    if (users.count == 0 && target != object) {
        users = SPKDirectUsersFromObject(object);
    }
    if (threadName.length == 0) {
        threadName = SPKDirectNameFromUsers(users);
    }

    SPKDirectThreadContext *context = [SPKDirectThreadContext new];
    context.threadId = threadId;
    context.threadName = threadName ?: @"";
    context.isGroup = [isGroupValue respondsToSelector:@selector(boolValue)] ? [isGroupValue boolValue] : NO;
    context.users = users ?: @[];
    if (context.isGroup) {
        context.groupPhotoUrl = SPKDirectGroupPhotoURLFromTarget(target)
                                    ?: SPKDirectGroupPhotoURLFromTarget(object);
    }
    return context;
}

static SPKDirectThreadContext *SPKDirectContextFromShallowInboxCandidate(id candidate) {
    if (!candidate)
        return nil;

    SPKDirectThreadContext *context = SPKDirectContextFromShallowInboxObject(candidate);
    if (context.threadId.length > 0)
        return context;

    NSArray<NSString *> *keys = @[
        @"_thread",
        @"thread",
        @"_directThread",
        @"directThread",
        @"_threadInfo",
        @"threadInfo",
        @"_threadSummary",
        @"threadSummary",
        @"_threadMetadata",
        @"threadMetadata",
        @"_threadViewModel",
        @"threadViewModel",
        @"_inboxItem",
        @"inboxItem",
        @"_item",
        @"item"
    ];

    for (NSString *key in keys) {
        id nested = nil;
        if ([candidate isKindOfClass:[NSDictionary class]]) {
            nested = ((NSDictionary *)candidate)[key];
        }
        if (!nested) {
            nested = [key hasPrefix:@"_"] ? [SPKUtils getIvarForObj:candidate name:key.UTF8String] : SPKDirectKVCObject(candidate, key);
        }
        context = SPKDirectContextFromShallowInboxObject(nested);
        if (context.threadId.length > 0)
            return context;
    }

    return nil;
}

SPKDirectThreadContext *SPKDirectThreadContextFromInboxViewModel(id viewModel) {
    return SPKDirectContextFromShallowInboxCandidate(viewModel);
}

NSDictionary *SPKDirectThreadEntryFromContext(SPKDirectThreadContext *context) {
    NSString *threadId = SPKDirectStringFromValue(context.threadId);
    if (threadId.length == 0)
        return nil;
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    entry[@"threadId"] = threadId;
    entry[@"threadName"] = context.threadName ?: @"";
    entry[@"isGroup"] = @(context.isGroup);
    entry[@"users"] = context.users ?: @[];
    if (context.groupPhotoUrl.length)
        entry[@"groupPhotoUrl"] = context.groupPhotoUrl;
    return entry.copy;
}

void SPKDirectSetActiveThreadContext(SPKDirectThreadContext *context) {
    NSString *oldThreadId = SPKDirectActiveContext.threadId ?: @"";
    NSString *newThreadId = context.threadId ?: @"";
    SPKDirectActiveContext = context;
    if (newThreadId.length > 0 && ![oldThreadId isEqualToString:newThreadId]) {
        SPKLog(@"消息", @"[Sparkle MessagesSeen] Active thread context set threadId=%@ threadName=%@ isGroup=%d",
               newThreadId,
               context.threadName ?: @"",
               context.isGroup);
    } else if (newThreadId.length == 0 && oldThreadId.length > 0) {
        SPKLog(@"消息", @"[Sparkle MessagesSeen] Active thread context cleared threadId=%@", oldThreadId);
    }
}

SPKDirectThreadContext *SPKDirectActiveThreadContext(void) {
    return SPKDirectActiveContext;
}

static NSArray<NSDictionary *> *SPKDirectManualSeenThreadListFromRawValue(id rawStored) {
    NSArray *stored = [rawStored isKindOfClass:[NSArray class]] ? rawStored : nil;
    NSMutableArray<NSDictionary *> *threads = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    for (id value in stored ?: @[]) {
        NSDictionary *dict = [value isKindOfClass:[NSDictionary class]] ? value : nil;
        NSString *threadId = SPKDirectStringFromValue(dict[@"threadId"]);
        if (threadId.length == 0 || [seen containsObject:threadId])
            continue;
        [seen addObject:threadId];

        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[@"threadId"] = threadId;
        entry[@"threadName"] = SPKDirectStringFromValue(dict[@"threadName"]) ?: @"";
        entry[@"isGroup"] = @([dict[@"isGroup"] respondsToSelector:@selector(boolValue)] ? [dict[@"isGroup"] boolValue] : NO);
        entry[@"users"] = [dict[@"users"] isKindOfClass:[NSArray class]] ? dict[@"users"] : @[];
        if (dict[@"addedAt"])
            entry[@"addedAt"] = dict[@"addedAt"];
        NSString *groupPhotoUrl = SPKDirectStringFromValue(dict[@"groupPhotoUrl"]);
        if (groupPhotoUrl.length)
            entry[@"groupPhotoUrl"] = groupPhotoUrl;
        [threads addObject:entry.copy];
    }

    return threads.copy;
}

static void SPKDirectUpdateManualSeenThreadCaches(NSArray<NSDictionary *> *threads) {
    SPKDirectManualSeenThreadsCache = [threads copy] ?: @[];
    NSMutableSet<NSString *> *threadIds = [NSMutableSet set];
    for (NSDictionary *entry in SPKDirectManualSeenThreadsCache) {
        NSString *threadId = SPKDirectStringFromValue(entry[@"threadId"]);
        if (threadId.length > 0)
            [threadIds addObject:threadId];
    }
    SPKDirectManualSeenThreadIdsCache = threadIds.copy;
}

static NSString *SPKDirectManualSeenThreadsKeyForMode(BOOL manualSeenEnabled) {
    // Separate lists per mode: ON → Excluded (chats using default seen),
    // OFF → Included (chats requiring manual seen).
    return manualSeenEnabled ? @"msgs_manual_seen_excluded" : @"msgs_manual_seen_included";
}

NSArray<NSDictionary *> *SPKDirectManualSeenThreadList(BOOL manualSeenEnabled) {
    NSString *baseKey = SPKDirectManualSeenThreadsKeyForMode(manualSeenEnabled);
    NSString *effectiveKey = SPKEffectivePreferenceKey(baseKey);
    // Rebuild when the mode or account changes (effective key differs).
    if (!SPKDirectManualSeenThreadsCache || ![effectiveKey isEqualToString:SPKDirectManualSeenCachedKey]) {
        SPKDirectManualSeenCachedKey = effectiveKey;
        SPKDirectUpdateManualSeenThreadCaches(SPKDirectManualSeenThreadListFromRawValue(SPKPreferenceObjectForKey(baseKey)));
    }
    return SPKDirectManualSeenThreadsCache;
}

void SPKDirectSetManualSeenThreadList(NSArray<NSDictionary *> *threads, BOOL manualSeenEnabled) {
    NSString *baseKey = SPKDirectManualSeenThreadsKeyForMode(manualSeenEnabled);
    NSArray *normalized = SPKDirectManualSeenThreadListFromRawValue(threads);
    SPKPreferenceSetObject(normalized, baseKey);
    SPKDirectManualSeenCachedKey = SPKEffectivePreferenceKey(baseKey);
    SPKDirectUpdateManualSeenThreadCaches(normalized);
}

BOOL SPKDirectManualSeenListContainsThreadId(NSString *threadId, BOOL manualSeenEnabled) {
    NSString *normalizedThreadId = SPKDirectStringFromValue(threadId);
    if (normalizedThreadId.length == 0)
        return NO;
    // Always go through the list (cheap when cached) so the membership set
    // matches the current mode/account, not a stale one.
    (void)SPKDirectManualSeenThreadList(manualSeenEnabled);
    return [SPKDirectManualSeenThreadIdsCache containsObject:normalizedThreadId];
}

void SPKDirectAddOrUpdateManualSeenThreadEntry(NSDictionary *entry, BOOL manualSeenEnabled) {
    NSString *threadId = SPKDirectStringFromValue(entry[@"threadId"]);
    if (threadId.length == 0) {
        SPKLog(@"消息", @"[Sparkle MessagesSeen] Ignored add/update for manual seen list: missing threadId entry=%@", entry);
        return;
    }

    NSMutableArray<NSDictionary *> *threads = [SPKDirectManualSeenThreadList(manualSeenEnabled) mutableCopy];
    NSInteger existingIndex = -1;
    for (NSInteger idx = 0; idx < (NSInteger)threads.count; idx++) {
        if ([threads[idx][@"threadId"] isEqualToString:threadId]) {
            existingIndex = idx;
            break;
        }
    }

    NSMutableDictionary *merged = [entry mutableCopy];
    merged[@"threadId"] = threadId;
    NSDictionary *existing = existingIndex >= 0 ? threads[existingIndex] : nil;
    if (!merged[@"threadName"] && existing[@"threadName"])
        merged[@"threadName"] = existing[@"threadName"];
    if (!merged[@"threadName"])
        merged[@"threadName"] = @"";
    if (!merged[@"isGroup"] && existing[@"isGroup"])
        merged[@"isGroup"] = existing[@"isGroup"];
    if (!merged[@"isGroup"])
        merged[@"isGroup"] = @(NO);
    if (![merged[@"users"] isKindOfClass:[NSArray class]] || [(NSArray *)merged[@"users"] count] == 0) {
        merged[@"users"] = [existing[@"users"] isKindOfClass:[NSArray class]] ? existing[@"users"] : @[];
    }
    if (existing[@"addedAt"]) {
        merged[@"addedAt"] = existing[@"addedAt"];
    }
    if (!merged[@"addedAt"])
        merged[@"addedAt"] = @([[NSDate date] timeIntervalSince1970]);
    if (!merged[@"groupPhotoUrl"] && existing[@"groupPhotoUrl"])
        merged[@"groupPhotoUrl"] = existing[@"groupPhotoUrl"];

    if (existingIndex >= 0) {
        threads[existingIndex] = merged.copy;
    } else {
        [threads addObject:merged.copy];
    }
    SPKDirectSetManualSeenThreadList(threads, manualSeenEnabled);
    SPKLog(@"消息", @"[Sparkle MessagesSeen] %@ manual seen list entry threadId=%@ threadName=%@ list=%@ count=%lu",
           existingIndex >= 0 ? @"Updated" : @"Added",
           threadId,
           merged[@"threadName"] ?: @"",
           SPKDirectManualSeenListTitle(manualSeenEnabled),
           (unsigned long)threads.count);
}

void SPKDirectRemoveManualSeenThreadId(NSString *threadId, BOOL manualSeenEnabled) {
    NSString *normalizedThreadId = SPKDirectStringFromValue(threadId);
    if (normalizedThreadId.length == 0) {
        SPKLog(@"消息", @"[Sparkle MessagesSeen] Ignored remove for manual seen list: missing threadId");
        return;
    }
    NSMutableArray<NSDictionary *> *threads = [SPKDirectManualSeenThreadList(manualSeenEnabled) mutableCopy];
    NSUInteger beforeCount = threads.count;
    [threads filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *entry, NSDictionary *bindings) {
                 (void)bindings;
                 return ![entry[@"threadId"] isEqualToString:normalizedThreadId];
             }]];
    SPKDirectSetManualSeenThreadList(threads, manualSeenEnabled);
    SPKLog(@"消息", @"[Sparkle MessagesSeen] Removed manual seen list entry threadId=%@ list=%@ before=%lu after=%lu",
           normalizedThreadId,
           SPKDirectManualSeenListTitle(manualSeenEnabled),
           (unsigned long)beforeCount,
           (unsigned long)threads.count);
}

static void SPKDirectEnrichManualSeenThreadEntryIfNeeded(NSDictionary *entry, BOOL manualSeenEnabled) {
    if ([entry[@"isGroup"] boolValue])
        return;
    NSString *threadId = SPKDirectStringFromValue(entry[@"threadId"]);
    NSArray *users = [entry[@"users"] isKindOfClass:[NSArray class]] ? entry[@"users"] : @[];

    NSString *currentPk = [SPKUtils currentUserPK];
    NSDictionary *user = nil;
    for (NSDictionary *u in users) {
        if (![u isKindOfClass:[NSDictionary class]])
            continue;
        NSString *pk = u[@"pk"];
        if (currentPk.length > 0 && [pk isEqualToString:currentPk])
            continue;
        user = u;
        break;
    }
    if (!user && users.count > 0) {
        user = users.firstObject;
    }

    NSString *username = SPKDirectStringFromValue(user[@"用户名"]);
    NSString *pk = SPKDirectStringFromValue(user[@"pk"]);
    NSString *profilePicUrl = SPKDirectStringFromValue(user[@"profilePicUrl"]);
    if (threadId.length == 0 || username.length == 0)
        return;
    if (pk.length > 0 && profilePicUrl.length > 0)
        return; // already fully enriched!

    [SPKInstagramAPI resolveUserForUsername:username
                                  completion:^(NSDictionary *resolvedUser, NSError *error) {
                                    if (![resolvedUser isKindOfClass:[NSDictionary class]] || error) {
                                        SPKLog(@"消息", @"[Sparkle MessagesSeen] Thread metadata enrichment failed threadId=%@ username=%@ error=%@",
                                               threadId,
                                               username,
                                               error);
                                        return;
                                    }

                                    NSString *resolvedUsername = SPKDirectStringFromValue(resolvedUser[@"用户名"]) ?: username;
                                    NSString *resolvedPk = SPKDirectStringFromValue(resolvedUser[@"id"] ?: resolvedUser[@"pk"]) ?: pk ?
                                                                                                                                      : @"";
                                    NSString *fullName = SPKDirectCleanFullName(SPKDirectStringFromValue(resolvedUser[@"full_name"] ?: resolvedUser[@"fullName"]), resolvedUsername) ?: SPKDirectStringFromValue(user[@"fullName"]) ?
                                                                                                                                                                                                                                    : @"";
                                    NSString *profilePic = SPKDirectStringFromValue(resolvedUser[@"profile_pic_url"] ?: resolvedUser[@"profile_pic_url_hd"]);

                                    NSMutableDictionary *updatedEntry = [entry mutableCopy];
                                    NSString *threadName = SPKDirectStringFromValue(updatedEntry[@"threadName"]);
                                    NSString *normalizedThreadName = SPKDirectNormalizeUsername(threadName);
                                    NSString *normalizedUsername = SPKDirectNormalizeUsername(resolvedUsername);
                                    if (threadName.length == 0 ||
                                        [normalizedThreadName isEqualToString:normalizedUsername] ||
                                        [[threadName stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"@"]] caseInsensitiveCompare:resolvedUsername] == NSOrderedSame) {
                                        updatedEntry[@"threadName"] = fullName.length > 0 ? fullName : resolvedUsername;
                                    }

                                    NSMutableDictionary *mutUser = [NSMutableDictionary dictionary];
                                    mutUser[@"pk"] = resolvedPk;
                                    mutUser[@"用户名"] = resolvedUsername;
                                    mutUser[@"fullName"] = fullName;
                                    if (profilePic.length > 0)
                                        mutUser[@"profilePicUrl"] = profilePic;

                                    updatedEntry[@"users"] = @[ mutUser.copy ];

                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        SPKDirectAddOrUpdateManualSeenThreadEntry(updatedEntry, manualSeenEnabled);
                                    });
                                }];
}

NSString *SPKDirectManualSeenListTitle(BOOL manualSeenEnabled) {
    return manualSeenEnabled ? @"Excluded Chats" : @"Included Chats";
}

NSUInteger SPKDirectManualSeenThreadCount(BOOL manualSeenEnabled) {
    return SPKDirectManualSeenThreadList(manualSeenEnabled).count;
}

NSDictionary *SPKDirectManualSeenThreadEntryForUserPK(NSString *pk, BOOL manualSeenEnabled) {
    if (pk.length == 0)
        return nil;
    NSArray<NSDictionary *> *threads = SPKDirectManualSeenThreadList(manualSeenEnabled);
    for (NSDictionary *entry in threads) {
        if ([entry[@"isGroup"] boolValue])
            continue;
        NSArray *users = entry[@"users"];
        for (NSDictionary *user in users) {
            if ([user[@"pk"] isEqualToString:pk]) {
                return entry;
            }
        }
    }
    return nil;
}

static BOOL SPKDirectManualSeenListContainsThreadIdInList(NSString *threadId, NSArray<NSDictionary *> *threads) {
    if (threads == SPKDirectManualSeenThreadsCache) {
        return SPKDirectManualSeenListContainsThreadId(threadId, [SPKUtils getBoolPref:@"msgs_manual_seen"]);
    }

    NSString *normalizedThreadId = SPKDirectStringFromValue(threadId);
    if (normalizedThreadId.length == 0)
        return NO;
    for (NSDictionary *entry in threads) {
        if ([entry[@"threadId"] isEqualToString:normalizedThreadId])
            return YES;
    }
    return NO;
}

static NSString *SPKDirectFastThreadIdForSource(id source) {
    NSString *threadId = SPKDirectThreadIdDirectlyFromObject(source);
    if (threadId.length > 0)
        return threadId;

    if ([source isKindOfClass:[UIView class]]) {
        UIViewController *viewController = [SPKUtils nearestViewControllerForView:(UIView *)source];
        threadId = SPKDirectThreadIdDirectlyFromObject(viewController);
        if (threadId.length > 0)
            return threadId;
    }

    threadId = SPKDirectActiveContext.threadId;
    return threadId.length > 0 ? threadId : nil;
}

static NSString *SPKDirectManualSeenListModeTitle(BOOL manualSeenEnabled) {
    return manualSeenEnabled ? @"Excluded" : @"Included";
}

static NSString *SPKDirectManualSeenListHelpText(BOOL manualSeenEnabled) {
    return manualSeenEnabled
               ? @"When Manually Mark Seen is enabled, chats in this list use Instagram's normal seen behavior and do not need the eye button. Add group chats from the open chat or inbox long-press menu."
               : @"When Manually Mark Seen is disabled, only chats in this list require the eye button or auto seen triggers to mark seen. Add group chats from the open chat or inbox long-press menu.";
}

BOOL SPKDirectManualSeenAppliesToSource(id source) {
    BOOL manualSeenEnabled = [SPKUtils getBoolPref:@"msgs_manual_seen"];
    NSArray<NSDictionary *> *threads = SPKDirectManualSeenThreadList(manualSeenEnabled);
    if (threads.count == 0)
        return manualSeenEnabled;

    NSString *threadId = SPKDirectFastThreadIdForSource(source);
    if (threadId.length == 0)
        return manualSeenEnabled;

    BOOL listed = SPKDirectManualSeenListContainsThreadIdInList(threadId, threads);
    return manualSeenEnabled ? !listed : listed;
}

BOOL SPKDirectShouldShowSeenButtonForSource(id source) {
    return SPKDirectManualSeenAppliesToSource(source);
}

static BOOL SPKDirectCurrentThreadRuleState(SPKDirectThreadContext *context, NSString **outThreadId, NSString **outThreadName, NSString **outListTitle, BOOL *outListed, BOOL *outManualSeenEnabled) {
    NSString *threadId = SPKDirectStringFromValue(context.threadId);
    if (threadId.length == 0)
        return NO;

    BOOL manualSeenEnabled = [SPKUtils getBoolPref:@"msgs_manual_seen"];
    BOOL listed = SPKDirectManualSeenListContainsThreadId(threadId, manualSeenEnabled);
    NSString *listTitle = SPKDirectManualSeenListTitle(manualSeenEnabled);
    NSString *threadName = context.threadName.length > 0 ? context.threadName : @"This chat";

    if (outThreadId)
        *outThreadId = threadId;
    if (outThreadName)
        *outThreadName = threadName;
    if (outListTitle)
        *outListTitle = listTitle;
    if (outListed)
        *outListed = listed;
    if (outManualSeenEnabled)
        *outManualSeenEnabled = manualSeenEnabled;
    return YES;
}

NSString *SPKDirectCurrentThreadRuleActionTitle(SPKDirectThreadContext *context) {
    if (!context)
        return nil;
    BOOL applies = SPKDirectManualSeenAppliesToSource(context);
    return applies ? @"Start Marking as Seen" : @"Stop Marking as Seen";
}

NSString *SPKDirectCurrentThreadRuleConfirmationTitle(SPKDirectThreadContext *context) {
    if (!context)
        return nil;
    BOOL applies = SPKDirectManualSeenAppliesToSource(context);
    return applies ? @"Confirm Start Marking as Seen" : @"Confirm Stop Marking as Seen";
}

NSString *SPKDirectCurrentThreadRuleConfirmationMessage(SPKDirectThreadContext *context) {
    NSString *threadName = nil;
    if (!SPKDirectCurrentThreadRuleState(context, NULL, &threadName, NULL, NULL, NULL))
        return nil;
    BOOL applies = SPKDirectManualSeenAppliesToSource(context);
    return applies
               ? [NSString stringWithFormat:@"Do you want to start marking %@ as seen?", threadName]
               : [NSString stringWithFormat:@"Do you want to stop marking %@ as seen?", threadName];
}

BOOL SPKDirectToggleCurrentThreadRule(SPKDirectThreadContext *context, NSString **notificationTitle, NSString **notificationSubtitle) {
    NSString *threadId = nil;
    NSString *threadName = nil;
    NSString *listTitle = nil;
    BOOL listed = NO;
    BOOL manualSeenEnabled = NO;
    if (!SPKDirectCurrentThreadRuleState(context, &threadId, &threadName, &listTitle, &listed, &manualSeenEnabled)) {
        SPKLog(@"消息", @"[Sparkle MessagesSeen] Toggle thread rule failed: missing current thread context=%@", context);
        return NO;
    }

    BOOL applies = SPKDirectManualSeenAppliesToSource(context);

    if (listed) {
        SPKDirectRemoveManualSeenThreadId(threadId, manualSeenEnabled);
    } else {
        NSDictionary *entry = SPKDirectThreadEntryFromContext(context);
        if (!entry)
            return NO;
        SPKDirectAddOrUpdateManualSeenThreadEntry(entry, manualSeenEnabled);
        SPKDirectEnrichManualSeenThreadEntryIfNeeded(entry, manualSeenEnabled);
    }
    SPKLog(@"消息", @"[Sparkle MessagesSeen] %@ %@ threadId=%@ threadName=%@ manualSeenEnabled=%d",
           listed ? @"Removed from" : @"Added to",
           listTitle,
           threadId,
           threadName,
           manualSeenEnabled);

    if (notificationTitle) {
        *notificationTitle = applies
                                 ? [NSString stringWithFormat:@"Messages seen on for %@", threadName]
                                 : [NSString stringWithFormat:@"Messages seen off for %@", threadName];
    }
    if (notificationSubtitle)
        *notificationSubtitle = listTitle;
    return YES;
}

#pragma mark - Manual-seen chats list

@interface SPKDirectManualSeenThreadsViewController : SPKUserListViewController
@property (nonatomic, assign) BOOL manualSeenEnabled;
@end

@implementation SPKDirectManualSeenThreadsViewController

- (instancetype)init {
    if ((self = [super init])) {
        _manualSeenEnabled = [SPKUtils getBoolPref:@"msgs_manual_seen"];
        self.title = SPKDirectManualSeenListTitle(_manualSeenEnabled);
        self.showsAddButton = YES;
        self.infoText = SPKDirectManualSeenListHelpText(_manualSeenEnabled);
        self.emptyTitle = @"No chats yet";
        self.emptySubtitle = _manualSeenEnabled
                                 ? @"Add chats that should keep Instagram's normal seen behavior."
                                 : @"Add chats that require the eye button to mark seen.";
    }
    return self;
}

- (NSString *)displayNameForEntry:(NSDictionary *)entry {
    return SPKDirectDisplayNameForThreadEntry(entry) ?: @"Unknown Chat";
}

- (NSString *)subtitleForEntry:(NSDictionary *)entry {
    NSString *participants = SPKDirectParticipantSubtitleForThreadEntry(entry);
    if (participants)
        return participants;
    NSArray *users = [entry[@"users"] isKindOfClass:[NSArray class]] ? entry[@"users"] : @[];
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSDictionary *user in users) {
        NSString *username = [user[@"用户名"] isKindOfClass:[NSString class]] ? user[@"用户名"] : nil;
        if (username.length > 0)
            [parts addObject:[@"@" stringByAppendingString:username]];
    }
    return [parts componentsJoinedByString:@", "];
}

- (NSArray<SPKUserListItem *> *)buildItems {
    NSArray<NSDictionary *> *threads = [SPKDirectManualSeenThreadList(self.manualSeenEnabled) sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSNumber *aAdded = [a[@"addedAt"] respondsToSelector:@selector(compare:)] ? a[@"addedAt"] : @0;
        NSNumber *bAdded = [b[@"addedAt"] respondsToSelector:@selector(compare:)] ? b[@"addedAt"] : @0;
        return [bAdded compare:aAdded];
    }];

    NSMutableArray<SPKUserListItem *> *items = [NSMutableArray array];
    for (NSDictionary *entry in threads) {
        SPKUserListItem *item = [SPKUserListItem new];
        item.representedObject = entry;
        BOOL isGroup = [entry[@"isGroup"] boolValue];

        if (isGroup) {
            item.isGroup = YES;
            item.title = [self displayNameForEntry:entry];
            item.subtitle = [self subtitleForEntry:entry];
            // Shared cache key matches Deleted Messages' group photos; a synthetic
            // "grp_" PK can't self-heal, but SPKAvatarView draws the group glyph.
            NSString *threadId = [entry[@"threadId"] isKindOfClass:[NSString class]] ? entry[@"threadId"] : nil;
            NSString *groupPhotoUrl = [entry[@"groupPhotoUrl"] isKindOfClass:[NSString class]] ? entry[@"groupPhotoUrl"] : nil;
            if (threadId.length) {
                item.pk = [@"grp_" stringByAppendingString:threadId];
                item.avatarURLString = groupPhotoUrl;
            } else {
                item.avatarURLString = groupPhotoUrl;
            }
        } else {
            NSArray *users = [entry[@"users"] isKindOfClass:[NSArray class]] ? entry[@"users"] : @[];
            NSString *pk = nil, *username = nil, *fullName = nil, *profilePicUrl = nil;
            for (NSDictionary *user in users) {
                if (!pk.length && [user[@"pk"] isKindOfClass:[NSString class]])
                    pk = user[@"pk"];
                if (!username.length && [user[@"用户名"] isKindOfClass:[NSString class]])
                    username = user[@"用户名"];
                if (!fullName.length && [user[@"fullName"] isKindOfClass:[NSString class]])
                    fullName = user[@"fullName"];
                if (!profilePicUrl.length && [user[@"profilePicUrl"] isKindOfClass:[NSString class]])
                    profilePicUrl = user[@"profilePicUrl"];
                if (pk.length && username.length && fullName.length && profilePicUrl.length)
                    break;
            }
            if (!profilePicUrl.length && pk.length)
                profilePicUrl = spkDirectUserResolverProfilePicURLStringForPK(pk);
            item.title = username.length ? [@"@" stringByAppendingString:username] : [self displayNameForEntry:entry];
            item.subtitle = username.length ? (fullName.length ? fullName : nil) : [self subtitleForEntry:entry];
            item.pk = pk;
            item.avatarURLString = profilePicUrl;
        }
        [items addObject:item];
    }
    return items;
}

- (void)listDidUpdateItemCount:(NSUInteger)count {
    self.title = [NSString stringWithFormat:@"%lu %@", (unsigned long)count, SPKDirectManualSeenListModeTitle(self.manualSeenEnabled)];
}

- (void)didSelectItem:(SPKUserListItem *)item {
    SPKDirectOpenProfileForThreadEntry(item.representedObject);
}

- (void)didDeleteItem:(SPKUserListItem *)item {
    NSDictionary *entry = item.representedObject;
    NSString *threadId = [entry[@"threadId"] isKindOfClass:[NSString class]] ? entry[@"threadId"] : nil;
    if (threadId.length == 0)
        return;
    NSString *threadName = [self displayNameForEntry:entry];
    SPKDirectRemoveManualSeenThreadId(threadId, self.manualSeenEnabled);
    SPKNotify(kSPKNotificationDirectThreadSeenRule,
              [NSString stringWithFormat:@"Removed %@", threadName],
              SPKDirectManualSeenListTitle(self.manualSeenEnabled),
              @"circle_check_filled",
              SPKNotificationToneSuccess);
    [self reloadItems];
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
                                                         message:@"输入 Instagram 用户名以添加一对一私信。"
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

    SPKLog(@"消息", @"[Sparkle MessagesSeen] Settings add chat lookup started username=%@ list=%@",
           username, SPKDirectManualSeenListTitle(self.manualSeenEnabled));

    __weak typeof(self) weakSelf = self;
    [SPKInstagramAPI resolveUserForUsername:username
                                  completion:^(NSDictionary *user, NSError *error) {
                                      __strong typeof(weakSelf) strongSelf = weakSelf;
                                      if (!strongSelf)
                                          return;
                                      if (![user isKindOfClass:[NSDictionary class]] || error) {
                                          SPKLog(@"消息", @"[Sparkle MessagesSeen] Settings add chat user lookup failed username=%@ error=%@", username, error);
                                          [strongSelf presentError:[NSString stringWithFormat:@"User '%@' was not found.", username]];
                                          return;
                                      }
                                      NSString *pk = SPKDirectStringFromValue(user[@"pk"] ?: user[@"id"]);
                                      NSString *resolvedUsername = SPKDirectStringFromValue(user[@"用户名"]) ?: username;
                                      NSString *fullName = SPKDirectStringFromValue(user[@"full_name"] ?: user[@"fullName"]) ?: @"";
                                      NSString *profilePicUrl = SPKDirectStringFromValue(user[@"profile_pic_url"] ?: user[@"profile_pic_url_hd"]);
                                      if (pk.length == 0) {
                                          SPKLog(@"消息", @"[Sparkle MessagesSeen] Settings add chat user lookup missing pk username=%@ response=%@", username, user);
                                          [strongSelf presentError:@"Could not resolve this user's Instagram id."];
                                          return;
                                      }
                                      [strongSelf resolveThreadForPK:pk username:resolvedUsername fullName:fullName profilePicUrl:profilePicUrl];
                                  }];
}

- (void)resolveThreadForPK:(NSString *)pk username:(NSString *)resolvedUsername fullName:(NSString *)fullName profilePicUrl:(NSString *)profilePicUrl {
    NSString *encodedRecipients = [[NSString stringWithFormat:@"[%@]", pk] stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    __weak typeof(self) weakSelf = self;
    [SPKInstagramAPI sendRequestWithMethod:@"GET"
                                      path:[NSString stringWithFormat:@"direct_v2/threads/get_by_participants/?recipient_users=%@", encodedRecipients]
                                      body:nil
                                completion:^(NSDictionary *threadResponse, NSError *threadError) {
                                    __strong typeof(weakSelf) innerSelf = weakSelf;
                                    if (!innerSelf)
                                        return;
                                    NSDictionary *thread = threadResponse[@"thread"];
                                    if (![thread isKindOfClass:[NSDictionary class]] || threadError) {
                                        SPKLog(@"消息", @"[Sparkle MessagesSeen] Settings add chat thread lookup failed username=%@ pk=%@ error=%@", resolvedUsername, pk, threadError);
                                        [innerSelf presentError:[NSString stringWithFormat:@"No 1:1 DM thread was found with @%@.", resolvedUsername]];
                                        return;
                                    }
                                    NSString *threadId = SPKDirectStringFromValue(thread[@"thread_id"] ?: thread[@"threadId"]);
                                    if (threadId.length == 0) {
                                        SPKLog(@"消息", @"[Sparkle MessagesSeen] Settings add chat thread lookup missing threadId username=%@ pk=%@ response=%@", resolvedUsername, pk, thread);
                                        [innerSelf presentError:[NSString stringWithFormat:@"No 1:1 DM thread was found with @%@.", resolvedUsername]];
                                        return;
                                    }
                                    NSString *threadName = SPKDirectStringFromValue(thread[@"thread_title"] ?: thread[@"threadName"]) ?: resolvedUsername;
                                    NSString *message = fullName.length > 0
                                                            ? [NSString stringWithFormat:@"@%@ (%@)", resolvedUsername, fullName]
                                                            : [@"@" stringByAppendingString:resolvedUsername];
                                    [SPKIGAlertPresenter presentAlertFromViewController:innerSelf
                                                                                  title:@"添加到列表？"
                                                                                message:message
                                                                                actions:@[
                                                                                    [SPKIGAlertAction actionWithTitle:@"取消"
                                                                                                                style:SPKIGAlertActionStyleCancel
                                                                                                              handler:nil],
                                                                                    [SPKIGAlertAction actionWithTitle:@"Add"
                                                                                                                style:SPKIGAlertActionStyleDefault
                                                                                                              handler:^{
                                                                                                                  NSMutableDictionary *usersEntry = [@{
                                                                                                                      @"pk" : pk,
                                                                                                                      @"用户名" : resolvedUsername,
                                                                                                                      @"fullName" : fullName,
                                                                                                                  } mutableCopy];
                                                                                                                  if (profilePicUrl.length > 0)
                                                                                                                      usersEntry[@"profilePicUrl"] = profilePicUrl;
                                                                                                                  SPKDirectAddOrUpdateManualSeenThreadEntry(@{@"threadId" : threadId,
                                                                                                                                                              @"threadName" : threadName,
                                                                                                                                                              @"isGroup" : @(NO),
                                                                                                                                                              @"users" : @[ usersEntry.copy ] },
                                                                                                                                                            innerSelf.manualSeenEnabled);
                                                                                                                  SPKNotify(kSPKNotificationDirectThreadSeenRule,
                                                                                                                            [NSString stringWithFormat:@"Added %@", threadName],
                                                                                                                            SPKDirectManualSeenListTitle(innerSelf.manualSeenEnabled),
                                                                                                                            @"circle_check_filled",
                                                                                                                            SPKNotificationToneSuccess);
                                                                                                                  [innerSelf reloadItems];
                                                                                                              }],
                                                                                ]];
                                }];
}

@end

UIViewController *SPKDirectManualSeenListViewController(void) {
    return [[SPKDirectManualSeenThreadsViewController alloc] init];
}
