#import "SPKProfileAnalyzerModels.h"
#import <objc/runtime.h>

// Reads a value from an IGUser's `_fieldCache` dict, walking the superclass
// chain to find the ivar. Returns nil for missing keys and NSNull.
static id spkFieldCacheValue(id obj, NSString *key) {
    if (!obj || !key)
        return nil;
    Ivar fcIvar = NULL;
    for (Class c = [obj class]; c && !fcIvar; c = class_getSuperclass(c)) {
        fcIvar = class_getInstanceVariable(c, "_fieldCache");
    }
    if (!fcIvar)
        return nil;
    NSDictionary *fc = object_getIvar(obj, fcIvar);
    if (![fc isKindOfClass:[NSDictionary class]])
        return nil;
    id v = fc[key];
    if (!v || [v isKindOfClass:[NSNull class]])
        return nil;
    return v;
}

static NSString *spkStringFromValue(id value) {
    if ([value isKindOfClass:[NSString class]])
        return value;
    if ([value respondsToSelector:@selector(stringValue)])
        return [value stringValue];
    return nil;
}

#pragma mark - User

@implementation SPKProfileAnalyzerUser

+ (instancetype)userFromAPIDict:(NSDictionary *)d {
    if (![d isKindOfClass:[NSDictionary class]])
        return nil;
    NSString *pk = spkStringFromValue(d[@"pk"] ?: d[@"pk_id"] ?
                                                              : d[@"id"]);
    if (!pk.length)
        return nil;

    SPKProfileAnalyzerUser *u = [self new];
    u.pk = pk;
    u.username = [d[@"用户名"] isKindOfClass:[NSString class]] ? d[@"用户名"] : @"";
    u.fullName = [d[@"full_name"] isKindOfClass:[NSString class]] ? d[@"full_name"] : nil;
    u.profilePicURL = [d[@"profile_pic_url"] isKindOfClass:[NSString class]] ? d[@"profile_pic_url"] : nil;
    u.profilePicID = spkStringFromValue(d[@"profile_pic_id"]);
    u.isPrivate = [d[@"is_private"] boolValue];
    u.isVerified = [d[@"is_verified"] boolValue];
    return u;
}

+ (instancetype)userFromIGUserObject:(id)igUser {
    if (!igUser)
        return nil;
    NSString *pk = spkStringFromValue(spkFieldCacheValue(igUser, @"strong_id__")
                                          ?: spkFieldCacheValue(igUser, @"pk")
                                             ?
                                             : spkFieldCacheValue(igUser, @"pk_id"));
    if (!pk.length)
        return nil;

    SPKProfileAnalyzerUser *u = [self new];
    u.pk = pk;
    id un = spkFieldCacheValue(igUser, @"用户名");
    u.username = [un isKindOfClass:[NSString class]] ? un : @"";
    id fn = spkFieldCacheValue(igUser, @"full_name");
    if ([fn isKindOfClass:[NSString class]])
        u.fullName = fn;
    id pic = spkFieldCacheValue(igUser, @"profile_pic_url");
    if ([pic isKindOfClass:[NSString class]])
        u.profilePicURL = pic;
    u.profilePicID = spkStringFromValue(spkFieldCacheValue(igUser, @"profile_pic_id"));
    u.isPrivate = [spkFieldCacheValue(igUser, @"is_private") boolValue];
    u.isVerified = [spkFieldCacheValue(igUser, @"is_verified") boolValue];
    return u;
}

+ (instancetype)userFromJSONDict:(NSDictionary *)d {
    if (![d[@"pk"] isKindOfClass:[NSString class]])
        return nil;
    SPKProfileAnalyzerUser *u = [self new];
    u.pk = d[@"pk"];
    u.username = [d[@"用户名"] isKindOfClass:[NSString class]] ? d[@"用户名"] : @"";
    u.fullName = [d[@"full_name"] isKindOfClass:[NSString class]] ? d[@"full_name"] : nil;
    u.profilePicURL = [d[@"profile_pic_url"] isKindOfClass:[NSString class]] ? d[@"profile_pic_url"] : nil;
    u.profilePicID = [d[@"profile_pic_id"] isKindOfClass:[NSString class]] ? d[@"profile_pic_id"] : nil;
    u.isPrivate = [d[@"is_private"] boolValue];
    u.isVerified = [d[@"is_verified"] boolValue];
    return u;
}

- (NSDictionary *)toJSONDict {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"pk"] = self.pk ?: @"";
    d[@"用户名"] = self.username ?: @"";
    if (self.fullName)
        d[@"full_name"] = self.fullName;
    if (self.profilePicURL)
        d[@"profile_pic_url"] = self.profilePicURL;
    if (self.profilePicID)
        d[@"profile_pic_id"] = self.profilePicID;
    d[@"is_private"] = @(self.isPrivate);
    d[@"is_verified"] = @(self.isVerified);
    return d;
}

- (id)copyWithZone:(NSZone *)zone {
    SPKProfileAnalyzerUser *u = [SPKProfileAnalyzerUser new];
    u.pk = self.pk;
    u.username = self.username;
    u.fullName = self.fullName;
    u.profilePicURL = self.profilePicURL;
    u.profilePicID = self.profilePicID;
    u.isPrivate = self.isPrivate;
    u.isVerified = self.isVerified;
    return u;
}

- (NSUInteger)hash {
    return self.pk.hash;
}
- (BOOL)isEqual:(id)other {
    if (other == self)
        return YES;
    if (![other isKindOfClass:[SPKProfileAnalyzerUser class]])
        return NO;
    return [self.pk isEqualToString:((SPKProfileAnalyzerUser *)other).pk];
}

@end

#pragma mark - Visit

@implementation SPKProfileAnalyzerVisit

+ (instancetype)visitFromJSONDict:(NSDictionary *)d {
    if (![d isKindOfClass:[NSDictionary class]])
        return nil;
    NSDictionary *userDict = d[@"user"];
    if (![userDict isKindOfClass:[NSDictionary class]])
        return nil;
    SPKProfileAnalyzerUser *u = [SPKProfileAnalyzerUser userFromJSONDict:userDict];
    if (!u)
        return nil;
    double first = [d[@"first_seen"] doubleValue];
    double last = [d[@"last_seen"] doubleValue];
    if (last <= 0)
        last = [[NSDate date] timeIntervalSince1970]; // legacy zero -> "now"
    if (first <= 0)
        first = last;
    SPKProfileAnalyzerVisit *v = [self new];
    v.user = u;
    v.firstSeen = [NSDate dateWithTimeIntervalSince1970:first];
    v.lastSeen = [NSDate dateWithTimeIntervalSince1970:last];
    v.visitCount = MAX(1, [d[@"visit_count"] integerValue]);
    return v;
}

- (NSDictionary *)toJSONDict {
    return @{
        @"user" : [self.user toJSONDict],
        @"first_seen" : @([self.firstSeen timeIntervalSince1970]),
        @"last_seen" : @([self.lastSeen timeIntervalSince1970]),
        @"visit_count" : @(self.visitCount),
    };
}

@end

#pragma mark - Snapshot

@implementation SPKProfileAnalyzerSnapshot

+ (instancetype)snapshotFromJSONDict:(NSDictionary *)d {
    if (![d isKindOfClass:[NSDictionary class]])
        return nil;
    if (![d[@"self_pk"] isKindOfClass:[NSString class]])
        return nil;
    SPKProfileAnalyzerSnapshot *s = [self new];
    s.scanDate = [NSDate dateWithTimeIntervalSince1970:[d[@"scan_date"] doubleValue]];
    s.selfPK = d[@"self_pk"];
    s.selfUsername = [d[@"self_username"] isKindOfClass:[NSString class]] ? d[@"self_username"] : nil;
    s.selfFullName = [d[@"self_full_name"] isKindOfClass:[NSString class]] ? d[@"self_full_name"] : nil;
    s.selfProfilePicURL = [d[@"self_profile_pic_url"] isKindOfClass:[NSString class]] ? d[@"self_profile_pic_url"] : nil;
    s.followerCount = [d[@"follower_count"] integerValue];
    s.followingCount = [d[@"following_count"] integerValue];
    s.mediaCount = [d[@"media_count"] integerValue];

    NSMutableArray *f = [NSMutableArray array];
    if ([d[@"followers"] isKindOfClass:[NSArray class]]) {
        for (NSDictionary *u in d[@"followers"]) {
            SPKProfileAnalyzerUser *user = [SPKProfileAnalyzerUser userFromJSONDict:u];
            if (user)
                [f addObject:user];
        }
    }
    s.followers = f;

    NSMutableArray *g = [NSMutableArray array];
    if ([d[@"following"] isKindOfClass:[NSArray class]]) {
        for (NSDictionary *u in d[@"following"]) {
            SPKProfileAnalyzerUser *user = [SPKProfileAnalyzerUser userFromJSONDict:u];
            if (user)
                [g addObject:user];
        }
    }
    s.following = g;
    return s;
}

- (NSDictionary *)toJSONDict {
    NSMutableArray *f = [NSMutableArray arrayWithCapacity:self.followers.count];
    for (SPKProfileAnalyzerUser *u in self.followers)
        [f addObject:[u toJSONDict]];
    NSMutableArray *g = [NSMutableArray arrayWithCapacity:self.following.count];
    for (SPKProfileAnalyzerUser *u in self.following)
        [g addObject:[u toJSONDict]];

    return @{
        @"scan_date" : @([self.scanDate timeIntervalSince1970]),
        @"self_pk" : self.selfPK ?: @"",
        @"self_username" : self.selfUsername ?: @"",
        @"self_full_name" : self.selfFullName ?: @"",
        @"self_profile_pic_url" : self.selfProfilePicURL ?: @"",
        @"follower_count" : @(self.followerCount),
        @"following_count" : @(self.followingCount),
        @"media_count" : @(self.mediaCount),
        @"followers" : f,
        @"following" : g,
    };
}

@end

#pragma mark - Profile change

@implementation SPKProfileAnalyzerProfileChange
- (BOOL)usernameChanged {
    return ![(self.previous.username ?: @"") isEqualToString:(self.current.username ?: @"")];
}
- (BOOL)fullNameChanged {
    return ![(self.previous.fullName ?: @"") isEqualToString:(self.current.fullName ?: @"")];
}
// Compare profile_pic_id (stable per upload); URL diffing is useless because
// IG rotates the CDN host per request. Skip when either side lacks the id.
- (BOOL)profilePicChanged {
    NSString *a = self.previous.profilePicID;
    NSString *b = self.current.profilePicID;
    if (!a.length || !b.length)
        return NO;
    return ![a isEqualToString:b];
}
@end

#pragma mark - Report

@implementation SPKProfileAnalyzerReport

static NSArray *spkSubtract(NSArray *a, NSSet *bSet) {
    if (!a.count)
        return @[];
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:a.count];
    for (SPKProfileAnalyzerUser *u in a)
        if (![bSet containsObject:u])
            [out addObject:u];
    return out;
}

static NSArray *spkIntersect(NSArray *a, NSSet *bSet) {
    if (!a.count)
        return @[];
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:a.count];
    for (SPKProfileAnalyzerUser *u in a)
        if ([bSet containsObject:u])
            [out addObject:u];
    return out;
}

+ (SPKProfileAnalyzerReport *)reportFromCurrent:(SPKProfileAnalyzerSnapshot *)current
                                       previous:(SPKProfileAnalyzerSnapshot *)previous {
    SPKProfileAnalyzerReport *r = [self new];
    r.current = current;
    r.previous = previous;
    r.mutualFollowers = @[];
    r.notFollowingYouBack = @[];
    r.youDontFollowBack = @[];
    r.recentFollowers = @[];
    r.lostFollowers = @[];
    r.youStartedFollowing = @[];
    r.youUnfollowed = @[];
    r.profileUpdates = @[];
    if (!current)
        return r;

    NSSet *followersSet = [NSSet setWithArray:current.followers];
    NSSet *followingSet = [NSSet setWithArray:current.following];

    r.mutualFollowers = spkIntersect(current.followers, followingSet);
    r.notFollowingYouBack = spkSubtract(current.following, followersSet);
    r.youDontFollowBack = spkSubtract(current.followers, followingSet);

    if (previous) {
        NSSet *prevFollowers = [NSSet setWithArray:previous.followers];
        NSSet *prevFollowing = [NSSet setWithArray:previous.following];
        r.recentFollowers = spkSubtract(current.followers, prevFollowers);
        r.lostFollowers = spkSubtract(previous.followers, followersSet);
        r.youStartedFollowing = spkSubtract(current.following, prevFollowing);
        r.youUnfollowed = spkSubtract(previous.following, followingSet);

        // Same pk in both snapshots, any tracked field differs.
        NSMutableDictionary *prevByPK = [NSMutableDictionary dictionary];
        for (SPKProfileAnalyzerUser *u in previous.followers)
            prevByPK[u.pk] = u;
        for (SPKProfileAnalyzerUser *u in previous.following)
            prevByPK[u.pk] = u;

        NSMutableArray *updates = [NSMutableArray array];
        NSMutableSet *seen = [NSMutableSet set];
        NSArray *currentAll = [current.followers arrayByAddingObjectsFromArray:current.following];
        for (SPKProfileAnalyzerUser *u in currentAll) {
            if ([seen containsObject:u.pk])
                continue;
            [seen addObject:u.pk];
            SPKProfileAnalyzerUser *prev = prevByPK[u.pk];
            if (!prev)
                continue;
            SPKProfileAnalyzerProfileChange *ch = [SPKProfileAnalyzerProfileChange new];
            ch.previous = prev;
            ch.current = u;
            if (ch.usernameChanged || ch.fullNameChanged || ch.profilePicChanged)
                [updates addObject:ch];
        }
        r.profileUpdates = updates;
    }
    return r;
}

@end

#pragma mark - Change event

@implementation SPKProfileAnalyzerChangeEvent

- (NSString *)eventID {
    return [NSString stringWithFormat:@"%ld|%@|%.0f",
                                      (long)self.type, self.user.pk ?: @"", [self.date timeIntervalSince1970]];
}

- (SPKProfileAnalyzerProfileChange *)asProfileChange {
    if (self.type != SPKPAChangeTypeProfileUpdate || !self.previousUser)
        return nil;
    SPKProfileAnalyzerProfileChange *ch = [SPKProfileAnalyzerProfileChange new];
    ch.previous = self.previousUser;
    ch.current = self.user;
    return ch;
}

+ (instancetype)eventFromJSONDict:(NSDictionary *)d {
    if (![d isKindOfClass:[NSDictionary class]])
        return nil;
    SPKProfileAnalyzerUser *u = [SPKProfileAnalyzerUser userFromJSONDict:d[@"user"]];
    if (!u)
        return nil;
    SPKProfileAnalyzerChangeEvent *e = [self new];
    e.type = [d[@"type"] integerValue];
    e.user = u;
    e.previousUser = [SPKProfileAnalyzerUser userFromJSONDict:d[@"previous_user"]]; // nil-safe
    e.date = [NSDate dateWithTimeIntervalSince1970:[d[@"date"] doubleValue]];
    e.seen = [d[@"seen"] boolValue];
    return e;
}

- (NSDictionary *)toJSONDict {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"type"] = @(self.type);
    d[@"user"] = [self.user toJSONDict];
    if (self.previousUser)
        d[@"previous_user"] = [self.previousUser toJSONDict];
    d[@"date"] = @([self.date timeIntervalSince1970]);
    d[@"seen"] = @(self.seen);
    return d;
}

+ (SPKProfileAnalyzerChangeEvent *)eventOfType:(SPKPAChangeType)type
                                          user:(SPKProfileAnalyzerUser *)user
                                          date:(NSDate *)date {
    SPKProfileAnalyzerChangeEvent *e = [self new];
    e.type = type;
    e.user = user;
    e.date = date;
    e.seen = NO;
    return e;
}

+ (NSArray<SPKProfileAnalyzerChangeEvent *> *)eventsFromReport:(SPKProfileAnalyzerReport *)report
                                                          date:(NSDate *)date {
    if (!date)
        date = [NSDate date];
    NSMutableArray<SPKProfileAnalyzerChangeEvent *> *out = [NSMutableArray array];
    for (SPKProfileAnalyzerUser *u in report.recentFollowers)
        [out addObject:[self eventOfType:SPKPAChangeTypeNewFollower user:u date:date]];
    for (SPKProfileAnalyzerUser *u in report.lostFollowers)
        [out addObject:[self eventOfType:SPKPAChangeTypeLostFollower user:u date:date]];
    for (SPKProfileAnalyzerUser *u in report.youStartedFollowing)
        [out addObject:[self eventOfType:SPKPAChangeTypeStartedFollowing user:u date:date]];
    for (SPKProfileAnalyzerUser *u in report.youUnfollowed)
        [out addObject:[self eventOfType:SPKPAChangeTypeUnfollowed user:u date:date]];
    for (SPKProfileAnalyzerProfileChange *ch in report.profileUpdates) {
        SPKProfileAnalyzerChangeEvent *e = [self eventOfType:SPKPAChangeTypeProfileUpdate user:ch.current date:date];
        e.previousUser = ch.previous;
        [out addObject:e];
    }
    return out;
}

@end
