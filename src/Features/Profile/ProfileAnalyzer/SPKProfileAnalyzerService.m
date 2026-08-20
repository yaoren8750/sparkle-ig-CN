#import "SPKProfileAnalyzerService.h"
#import "../../../Networking/SPKInstagramAPI.h"
#import "../../../Utils.h"
#import "SPKProfileAnalyzerStorage.h"

// Refuse accounts above ~13k total connections; the same cushion keeps
// a single scan inside IG's friendships rate limits.
const NSInteger SPKProfileAnalyzerMaxConnectionCount = 13000;

NSNotificationName const SPKProfileAnalyzerProgressDidChangeNotification = @"SPKProfileAnalyzerProgressDidChangeNotification";

#define SPK_PA_PAGE_DELAY_S 0.5       // rate-limit cushion between pages
#define SPK_PA_MAX_PAGE_RETRIES 4     // retries for a throttled/empty page
#define SPK_PA_RETRY_BASE_DELAY_S 2.0 // backoff base; grows linearly per retry
// A stage is considered too incomplete to trust when it collects less than this
// fraction of the count IG reported in users/info. Persisting a short list would
// corrupt mutuals / not-following-back / unfollowed categories.
#define SPK_PA_MIN_COMPLETE_FRACTION 0.90

@interface SPKProfileAnalyzerService () {
@public
    NSInteger _expectedFollowers;
    NSInteger _expectedFollowing;
}
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, assign) double currentFraction;
@property (nonatomic, copy, nullable) NSString *currentStatus;
@end

@implementation SPKProfileAnalyzerService

+ (instancetype)sharedService {
    static SPKProfileAnalyzerService *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [self new];
    });
    return s;
}

- (void)cancel {
    self.cancelled = YES;
}

- (NSError *)errorWithCode:(SPKProfileAnalyzerError)code message:(NSString *)msg {
    return [NSError errorWithDomain:@"SPKProfileAnalyzer"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey : msg ?: @""}];
}

- (void)finishWithSnapshot:(SPKProfileAnalyzerSnapshot *)s
                     error:(NSError *)e
                completion:(SPKPACompletion)completion {
    self.isRunning = NO;
    self.cancelled = NO;
    self.currentFraction = 0;
    self.currentStatus = nil;
    [self postProgressRunning:NO];
    if (completion)
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(s, e);
        });
}

- (void)reportProgress:(SPKPAProgress)p status:(NSString *)s fraction:(double)f {
    self.currentFraction = f;
    self.currentStatus = s;
    [self postProgressRunning:YES];
    if (!p)
        return;
    dispatch_async(dispatch_get_main_queue(), ^{
        p(s, f);
    });
}

- (void)postProgressRunning:(BOOL)running {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[@"fraction"] = @(self.currentFraction);
    info[@"running"] = @(running);
    if (self.currentStatus)
        info[@"status"] = self.currentStatus;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SPKProfileAnalyzerProgressDidChangeNotification
                                                            object:nil
                                                          userInfo:info];
    });
}

- (void)runForSelfWithHeaderInfo:(SPKPAHeaderInfo)headerInfo
                        progress:(SPKPAProgress)progress
                      completion:(SPKPACompletion)completion {
    if (self.isRunning) {
        if (completion)
            completion(nil, [self errorWithCode:SPKProfileAnalyzerErrorAlreadyRunning
                                        message:@"已有其他分析正在运行"]);
        return;
    }
    
    self.isRunning = YES;
    self.cancelled = NO;
    
    NSString *selfPK = [SPKUtils currentUserPK];
    if (!selfPK.length) {
        [self finishWithSnapshot:nil
                           error:[self errorWithCode:SPKProfileAnalyzerErrorNoSession
                                             message:@"未找到当前有效的 Instagram 会话"]
                      completion:completion];
        return;
    }
    
    __weak typeof(self) weakSelf = self;
    
    [self reportProgress:progress
                  status:@"正在获取个人资料信息..."
                fraction:0.02];
    
    [SPKInstagramAPI sendRequestWithMethod:@"GET"
                                      path:[NSString stringWithFormat:@"users/%@/info/", selfPK]
                                      body:nil
                                completion:^(NSDictionary *resp, NSError *error) {
        
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf)
            return;
        
        if (strongSelf.cancelled) {
            [strongSelf finishWithSnapshot:nil
                                     error:[strongSelf errorWithCode:SPKProfileAnalyzerErrorCancelled
                                                             message:@"分析已取消"]
                                completion:completion];
            return;
        }
        
        NSDictionary *user =
        [resp[@"user"] isKindOfClass:[NSDictionary class]]
        ? resp[@"user"]
        : nil;
        
        if (!user) {
            [strongSelf finishWithSnapshot:nil
                                     error:[strongSelf errorWithCode:SPKProfileAnalyzerErrorNetwork
                                                             message:@"无法获取个人资料信息"]
                                completion:completion];
            return;
        }
        
        NSInteger followerCount = [user[@"follower_count"] integerValue];
        NSInteger followingCount = [user[@"following_count"] integerValue];
        
        if (followerCount + followingCount > SPKProfileAnalyzerMaxConnectionCount) {
            [strongSelf finishWithSnapshot:nil
                                     error:[strongSelf errorWithCode:SPKProfileAnalyzerErrorTooManyFollowers
                                                             message:@"关注者数量过多，无法进行分析"]
                                completion:completion];
            return;
        }
        
        SPKProfileAnalyzerSnapshot *snap =
        [SPKProfileAnalyzerSnapshot new];
        
        snap.selfPK = selfPK;
        
        // API 字段名不能汉化
        snap.selfUsername = user[@"username"];
        snap.selfFullName = user[@"full_name"];
        snap.selfProfilePicURL = user[@"profile_pic_url"];
        
        snap.followerCount = followerCount;
        snap.followingCount = followingCount;
        snap.mediaCount = [user[@"media_count"] integerValue];
        snap.scanDate = [NSDate date];
        
        strongSelf->_expectedFollowers = followerCount;
        strongSelf->_expectedFollowing = followingCount;
        
        // Cache the header so the dashboard can paint identity even before
        // the scan completes, then notify the caller for an immediate header paint.
        [SPKProfileAnalyzerStorage saveHeaderInfo:user
                                        forUserPK:selfPK];
        
        if (headerInfo) {
            dispatch_async(dispatch_get_main_queue(), ^{
                headerInfo(user);
            });
        }
        
        [strongSelf fetchFollowersForPK:selfPK
                               snapshot:snap
                               progress:progress
                             completion:completion];
    }];
}
#pragma mark - Paginated fetchers

- (void)fetchFollowersForPK:(NSString *)pk
                   snapshot:(SPKProfileAnalyzerSnapshot *)snap
                   progress:(SPKPAProgress)progress
                 completion:(SPKPACompletion)completion {
    NSMutableArray *acc = [NSMutableArray array];
    
    [self pagePath:[NSString stringWithFormat:@"friendships/%@/followers/", pk]
               acc:acc
             maxId:nil
             total:snap.followerCount
             stage:@"followers"
          progress:progress
        completion:^(NSArray *users, NSError *error) {
        
        if (error || self.cancelled) {
            [self finishWithSnapshot:nil
                               error:error ?: [self errorWithCode:SPKProfileAnalyzerErrorCancelled
                                                          message:@"分析已取消"]
                          completion:completion];
            return;
        }
        
        if (![self stageCount:users.count
         plausibleForExpected:snap.followerCount]) {
            
            [self finishWithSnapshot:nil
                               error:[self errorWithCode:SPKProfileAnalyzerErrorNetwork
                                                 message:@"无法获取完整的粉丝列表（Instagram 请求受到限制）。请几分钟后再试。"]
                          completion:completion];
            return;
        }
        
        snap.followers = users;
        
        [self fetchFollowingForPK:pk
                         snapshot:snap
                         progress:progress
                       completion:completion];
    }];
}

- (void)fetchFollowingForPK:(NSString *)pk
                   snapshot:(SPKProfileAnalyzerSnapshot *)snap
                   progress:(SPKPAProgress)progress
                 completion:(SPKPACompletion)completion {
    NSMutableArray *acc = [NSMutableArray array];
    
    [self pagePath:[NSString stringWithFormat:@"friendships/%@/following/", pk]
               acc:acc
             maxId:nil
             total:snap.followingCount
             stage:@"following"
          progress:progress
        completion:^(NSArray *users, NSError *error) {
        
        if (error || self.cancelled) {
            [self finishWithSnapshot:nil
                               error:error ?: [self errorWithCode:SPKProfileAnalyzerErrorCancelled
                                                          message:@"分析已取消"]
                          completion:completion];
            return;
        }
        
        if (![self stageCount:users.count
         plausibleForExpected:snap.followingCount]) {
            
            [self finishWithSnapshot:nil
                               error:[self errorWithCode:SPKProfileAnalyzerErrorNetwork
                                                 message:@"无法获取完整的关注列表（Instagram 请求受到限制）。请几分钟后再试。"]
                          completion:completion];
            return;
        }
        
        snap.following = users;
        
        // Persist (rotates current -> previous) before reporting completion so
        // observers reading storage immediately see the new snapshot.
        [SPKProfileAnalyzerStorage saveSnapshot:snap
                                      forUserPK:snap.selfPK];
        
        [self finishWithSnapshot:snap
                           error:nil
                      completion:completion];
    }];
}

// Guards against persisting a truncated graph. IG's reported count can lag the
// real list slightly, so we allow a small shortfall but reject a big one.
- (BOOL)stageCount:(NSInteger)collected plausibleForExpected:(NSInteger)expected {
    if (expected <= 0)
        return YES; // nothing to compare against
    if (collected >= expected)
        return YES; // got everything (or more)
    double fraction = (double)collected / (double)expected;
    return fraction >= SPK_PA_MIN_COMPLETE_FRACTION;
}

- (void)pagePath:(NSString *)basePath
             acc:(NSMutableArray *)acc
           maxId:(NSString *)maxId
           total:(NSInteger)total
           stage:(NSString *)stage
        progress:(SPKPAProgress)progress
      completion:(void (^)(NSArray *users, NSError *error))completion {
    [self pagePath:basePath acc:acc maxId:maxId total:total stage:stage retry:0 progress:progress completion:completion];
}

- (void)pagePath:(NSString *)basePath
             acc:(NSMutableArray *)acc
           maxId:(NSString *)maxId
           total:(NSInteger)total
           stage:(NSString *)stage
           retry:(NSInteger)retry
        progress:(SPKPAProgress)progress
      completion:(void (^)(NSArray *users, NSError *error))completion {
    if (self.cancelled) {
        completion(nil, [self errorWithCode:SPKProfileAnalyzerErrorCancelled
                                    message:@"分析已取消"]);
        return;
    }
    
    NSString *path = maxId.length
    ? [NSString stringWithFormat:@"%@?max_id=%@", basePath, maxId]
    : basePath;
    
    __weak typeof(self) weakSelf = self;
    
    [SPKInstagramAPI sendRequestWithMethod:@"GET"
                                      path:path
                                      body:nil
                                completion:^(NSDictionary *resp, NSError *error) {
        
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf)
            return;
        
        // Detect a usable page. IG soft-throttles by returning HTTP 200 with a
        // non-"ok" status and neither `users` nor `next_max_id`. Treating that
        // as "end of list" silently truncates the graph and corrupts every
        // derived category, so we retry it with backoff instead.
        
        NSArray *users =
        [resp[@"users"] isKindOfClass:[NSArray class]]
        ? resp[@"users"]
        : nil;
        
        id next = resp[@"next_max_id"];
        
        NSString *nextMax =
        [next isKindOfClass:[NSString class]]
        ? next
        : ([next respondsToSelector:@selector(stringValue)]
           ? [next stringValue]
           : nil);
        
        NSString *status =
        [resp[@"status"] isKindOfClass:[NSString class]]
        ? resp[@"status"]
        : nil;
        
        BOOL statusOK =
        (status == nil) || [status isEqualToString:@"ok"];
        
        BOOL gotPage =
        (users != nil); // empty array is a valid "no more users" page when status ok
        
        if (error || !gotPage || !statusOK) {
            
            // Transient: retry up to a few times with escalating backoff.
            if (retry < SPK_PA_MAX_PAGE_RETRIES &&
                !strongSelf.cancelled) {
                
                double delay =
                SPK_PA_RETRY_BASE_DELAY_S * (double)(retry + 1);
                
                dispatch_after(
                               dispatch_time(DISPATCH_TIME_NOW,
                                             (int64_t)(delay * NSEC_PER_SEC)),
                               dispatch_get_main_queue(),
                               ^{
                                   [strongSelf pagePath:basePath
                                                    acc:acc
                                                  maxId:maxId
                                                  total:total
                                                  stage:stage
                                                  retry:retry + 1
                                               progress:progress
                                             completion:completion];
                               });
                
                return;
            }
            
            // Out of retries — fail loudly rather than persist a partial list.
            NSString *msg =
            error.localizedDescription
            ?: @"Instagram 请求受到限制，请几分钟后再试。";
            
            completion(nil,
                       [strongSelf errorWithCode:SPKProfileAnalyzerErrorNetwork
                                         message:msg]);
            return;
        }
        
        for (NSDictionary *d in users) {
            SPKProfileAnalyzerUser *u =
            [SPKProfileAnalyzerUser userFromAPIDict:d];
            
            if (u)
                [acc addObject:u];
        }
        
        // Weight each stage by its share of expected work;
        // 3% reserved for user-info.
        NSInteger followerTarget =
        strongSelf->_expectedFollowers;
        
        NSInteger followingTarget =
        strongSelf->_expectedFollowing;
        
        double total0 =
        MAX(1, followerTarget + followingTarget);
        
        BOOL isFollowers =
        [stage isEqualToString:@"followers"];
        
        double stageWeight =
        (isFollowers ? followerTarget : followingTarget) / total0;
        
        double stageOffset =
        isFollowers
        ? 0.0
        : (double)followerTarget / total0;
        
        double stageLocal =
        total > 0
        ? MIN(1.0,
              (double)acc.count / (double)total)
        : 0;
        
        double frac =
        0.03 +
        (stageOffset + stageLocal * stageWeight) * 0.97;
        
        NSString *label =
        isFollowers
        ? [NSString stringWithFormat:
           @"正在获取粉丝... • %lu / %ld",
           (unsigned long)acc.count,
           (long)total]
        : [NSString stringWithFormat:
           @"正在获取关注... • %lu / %ld",
           (unsigned long)acc.count,
           (long)total];
        
        [strongSelf reportProgress:progress
                            status:label
                          fraction:frac];
        
        if (!nextMax.length || strongSelf.cancelled) {
            
            completion(
                       acc,
                       strongSelf.cancelled
                       ? [strongSelf errorWithCode:
                          SPKProfileAnalyzerErrorCancelled
                                           message:@"分析已取消"]
                       : nil
                       );
            
            return;
        }
        
        dispatch_after(
                       dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(SPK_PA_PAGE_DELAY_S * NSEC_PER_SEC)),
                       dispatch_get_main_queue(),
                       ^{
                           [strongSelf pagePath:basePath
                                            acc:acc
                                          maxId:nextMax
                                          total:total
                                          stage:stage
                                          retry:0
                                       progress:progress
                                     completion:completion];
                       });
    }];
}
@end
