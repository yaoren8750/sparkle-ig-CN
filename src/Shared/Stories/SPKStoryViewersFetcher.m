#import "SPKStoryViewersFetcher.h"

#import "../../Networking/SPKInstagramAPI.h"
#import "../../Utils.h"

// Safety cap so a malformed/looping cursor can never spin forever. 200 pages ×
// ~50/page comfortably exceeds any real viewer list.
static const NSInteger kSPKViewersMaxPages = 200;
// friendships/show_many batch size — IG throttles /friendships/, 50/request is
// the same cushion the Profile Analyzer list uses.
static const NSInteger kSPKViewersFriendshipBatch = 50;

@implementation SPKStoryViewerModel
@end

@interface SPKStoryViewersFetcher ()
@property (nonatomic, copy) NSString *mediaID;
@property (nonatomic, copy) void (^progress)(NSInteger);
@property (nonatomic, copy) void (^completion)(NSArray<SPKStoryViewerModel *> *, NSInteger, NSError *_Nullable);
@property (nonatomic, strong) NSMutableArray<SPKStoryViewerModel *> *accumulated;
@property (nonatomic, assign) NSInteger totalCount;
@property (nonatomic, assign) NSInteger pageCount;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, assign) BOOL needsFriendshipBackfill;
@end

@implementation SPKStoryViewersFetcher

+ (instancetype)fetchAllViewersForMediaID:(NSString *)mediaID
                                 progress:(void (^)(NSInteger))progress
                               completion:(void (^)(NSArray<SPKStoryViewerModel *> *, NSInteger, NSError *_Nullable))completion {
    SPKStoryViewersFetcher *fetcher = [SPKStoryViewersFetcher new];
    fetcher.mediaID = mediaID;
    fetcher.progress = progress;
    fetcher.completion = completion;
    fetcher.accumulated = [NSMutableArray array];
    if (mediaID.length == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion)
                completion(@[], 0, [NSError errorWithDomain:@"SPKStoryViewers" code:1 userInfo:@{NSLocalizedDescriptionKey : @"Missing story id"}]);
        });
        return fetcher;
    }
    [fetcher fetchNextPageWithCursor:nil];
    return fetcher;
}

- (void)cancel {
    self.cancelled = YES;
    self.progress = nil;
    self.completion = nil;
}

- (void)fetchNextPageWithCursor:(NSString *)cursor {
    if (self.cancelled)
        return;
    if (self.pageCount >= kSPKViewersMaxPages) {
        [self finishWithError:nil];
        return;
    }
    self.pageCount++;

    NSMutableString *path = [NSMutableString stringWithFormat:@"media/%@/list_reel_media_viewer/?story_has_interactive_stickers=false", self.mediaID];
    if (cursor.length > 0) {
        NSString *encoded = [cursor stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]] ?: cursor;
        [path appendFormat:@"&max_id=%@", encoded];
    }

    __weak typeof(self) weakSelf = self;
    [SPKInstagramAPI sendRequestWithMethod:@"GET"
                                      path:path
                                      body:nil
                                completion:^(NSDictionary *response, NSError *error) {
                                    [weakSelf handlePage:response error:error firstPage:(cursor == nil)];
                                }];
}

- (void)handlePage:(NSDictionary *)response error:(NSError *)error firstPage:(BOOL)firstPage {
    if (self.cancelled)
        return;

    if (![response isKindOfClass:[NSDictionary class]]) {
        // Only surface an error if we got nothing at all; a mid-pagination
        // hiccup still returns what we have so far.
        [self finishWithError:(firstPage ? (error ?: [NSError errorWithDomain:@"SPKStoryViewers" code:2 userInfo:@{NSLocalizedDescriptionKey : @"Could not load viewers"}]) : nil)];
        return;
    }

    id totalRaw = response[@"total_viewer_count"] ?: response[@"user_count"];
    if ([totalRaw respondsToSelector:@selector(integerValue)]) {
        NSInteger reported = [totalRaw integerValue];
        if (reported > self.totalCount)
            self.totalCount = reported;
    }

    // The endpoint returns `viewers`, each entry a wrapper
    // { has_liked, is_spam_viewer, reply_text, user: { … friendship_status … } }.
    // Older/alt shapes may return a flat `users` array of user dicts directly.
    id entries = response[@"viewers"] ?: response[@"users"];
    if ([entries isKindOfClass:[NSArray class]]) {
        for (id entry in (NSArray *)entries) {
            if (![entry isKindOfClass:[NSDictionary class]])
                continue;
            SPKStoryViewerModel *model = [self modelFromViewerEntry:(NSDictionary *)entry];
            if (model)
                [self.accumulated addObject:model];
        }
    }

    if (self.progress) {
        NSInteger count = self.accumulated.count;
        void (^progress)(NSInteger) = self.progress;
        dispatch_async(dispatch_get_main_queue(), ^{
            progress(count);
        });
    }

    id nextRaw = response[@"next_max_id"];
    NSString *next = [nextRaw isKindOfClass:[NSString class]] ? (NSString *)nextRaw
                     : ([nextRaw respondsToSelector:@selector(stringValue)] ? [nextRaw stringValue] : nil);
    BOOL hasMore = response[@"more_available"] ? [response[@"more_available"] boolValue] : (next.length > 0);
    if (hasMore && next.length > 0) {
        [self fetchNextPageWithCursor:next];
    } else {
        [self finishWithError:nil];
    }
}

- (SPKStoryViewerModel *)modelFromViewerEntry:(NSDictionary *)entry {
    // Unwrap the per-viewer envelope: the user lives under `user` (with
    // has_liked/reply_text on the envelope); a flat entry is the user itself.
    NSDictionary *dict = entry;
    BOOL liked = [entry[@"has_liked"] boolValue];
    id nestedUser = entry[@"user"];
    if ([nestedUser isKindOfClass:[NSDictionary class]])
        dict = (NSDictionary *)nestedUser;

    SPKStoryViewerModel *model = [SPKStoryViewerModel new];
    model.liked = liked;
    id pk = dict[@"pk"] ?: dict[@"pk_id"] ?: dict[@"id"];
    model.pk = [pk isKindOfClass:[NSString class]] ? pk : ([pk respondsToSelector:@selector(stringValue)] ? [pk stringValue] : nil);
    if (model.pk.length == 0)
        return nil;
    model.username = [dict[@"用户名"] isKindOfClass:[NSString class]] ? dict[@"用户名"] : nil;
    model.fullName = [dict[@"full_name"] isKindOfClass:[NSString class]] ? dict[@"full_name"] : nil;
    model.profilePicURL = [dict[@"profile_pic_url"] isKindOfClass:[NSString class]] ? dict[@"profile_pic_url"] : nil;
    model.isVerified = [dict[@"is_verified"] boolValue];

    id friendship = dict[@"friendship_status"];
    if ([friendship isKindOfClass:[NSDictionary class]]) {
        model.following = [((NSDictionary *)friendship)[@"following"] boolValue];
        model.followedBy = [((NSDictionary *)friendship)[@"followed_by"] boolValue];
        model.friendshipKnown = YES;
    } else {
        self.needsFriendshipBackfill = YES;
    }
    return model;
}

// After paging completes, fill in following/followedBy for any viewers whose
// entry lacked friendship_status, in throttle-safe batches. Then deliver.
- (void)finishWithError:(NSError *)error {
    if (self.cancelled)
        return;

    if (error && self.accumulated.count == 0) {
        [self deliver:error];
        return;
    }

    if (!self.needsFriendshipBackfill) {
        [self deliver:nil];
        return;
    }

    NSMutableArray<NSString *> *pending = [NSMutableArray array];
    for (SPKStoryViewerModel *model in self.accumulated) {
        if (!model.friendshipKnown && model.pk.length)
            [pending addObject:model.pk];
    }
    if (pending.count == 0) {
        [self deliver:nil];
        return;
    }
    [self backfillFriendshipsForPKs:pending];
}

- (void)backfillFriendshipsForPKs:(NSMutableArray<NSString *> *)pending {
    if (self.cancelled)
        return;
    if (pending.count == 0) {
        [self deliver:nil];
        return;
    }
    NSRange range = NSMakeRange(0, MIN((NSUInteger)kSPKViewersFriendshipBatch, pending.count));
    NSArray<NSString *> *batch = [pending subarrayWithRange:range];
    [pending removeObjectsInRange:range];

    __weak typeof(self) weakSelf = self;
    [SPKInstagramAPI fetchFriendshipStatusesForPKs:batch
                                        completion:^(NSDictionary *statuses, NSError *error) {
                                            typeof(self) self = weakSelf;
                                            if (!self || self.cancelled)
                                                return;
                                            if ([statuses isKindOfClass:[NSDictionary class]]) {
                                                for (SPKStoryViewerModel *model in self.accumulated) {
                                                    id s = model.pk ? statuses[model.pk] : nil;
                                                    if ([s isKindOfClass:[NSDictionary class]]) {
                                                        model.following = [((NSDictionary *)s)[@"following"] boolValue];
                                                        model.followedBy = [((NSDictionary *)s)[@"followed_by"] boolValue];
                                                        model.friendshipKnown = YES;
                                                    }
                                                }
                                            }
                                            // Continue with the remaining batches regardless of a
                                            // single batch failing — partial follow state is fine.
                                            [self backfillFriendshipsForPKs:pending];
                                        }];
}

- (void)deliver:(NSError *)error {
    void (^completion)(NSArray *, NSInteger, NSError *) = self.completion;
    NSArray *viewers = [self.accumulated copy];
    NSInteger total = MAX(self.totalCount, (NSInteger)viewers.count);
    self.completion = nil;
    self.progress = nil;
    if (!completion)
        return;
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(viewers, total, error);
    });
}

@end
