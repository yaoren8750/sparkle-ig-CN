#import "SPKProfileAnalyzerStorage.h"
#import "../../../Shared/SPKStoragePaths.h"

NSNotificationName const SPKProfileAnalyzerDataDidChangeNotification = @"SPKProfileAnalyzerDataDidChangeNotification";

@implementation SPKProfileAnalyzerStorage

// Serial queue for visit-list reads + writes — prevents racing record / refresh
// / remove writes from resurrecting deleted entries.
static dispatch_queue_t spkVisitQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("com.sparkle.profileanalyzer.visits", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

// Serial queue for change-log reads + writes — keeps run-time appends from
// racing mark-seen writes.
static dispatch_queue_t spkChangeLogQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("com.sparkle.profileanalyzer.changelog", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

// Hard cap on stored events to bound disk use on very active accounts.
static const NSUInteger kSPKPAChangeLogCap = 3000;

// Strip NSNull recursively — NSJSONSerialization rejects it and IG payloads carry it.
static id spkStripNull(id obj) {
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:[obj count]];
        for (id k in obj) {
            id v = obj[k];
            if (v && ![v isKindOfClass:[NSNull class]])
                out[k] = spkStripNull(v);
        }
        return out;
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:[obj count]];
        for (id v in obj)
            if (v && ![v isKindOfClass:[NSNull class]])
                [out addObject:spkStripNull(v)];
        return out;
    }
    return obj;
}

static void spkPostDataChanged(NSString *userPK) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SPKProfileAnalyzerDataDidChangeNotification
                                                            object:nil
                                                          userInfo:userPK.length ? @{@"user_pk" : userPK} : @{}];
    });
}

static NSString *spkSafePK(NSString *userPK) {
    if (!userPK.length)
        return @"anon";
    return [userPK stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
}

static NSString *spkStorageDir(void) {
    NSString *dir = [SPKStoragePaths profileAnalyzerDirectory];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static NSString *spkPath(NSString *userPK, NSString *slot) {
    return [spkStorageDir() stringByAppendingPathComponent:
                                [NSString stringWithFormat:@"%@.%@.json", spkSafePK(userPK), slot]];
}

static NSDictionary *spkReadJSON(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length)
        return nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
}

static BOOL spkWriteJSON(NSString *path, NSDictionary *dict) {
    NSError *err = nil;
    id sanitized = spkStripNull(dict ?: @{});
    NSData *data = [NSJSONSerialization dataWithJSONObject:sanitized options:0 error:&err];
    if (!data)
        return NO;
    return [data writeToFile:path atomically:YES];
}

#pragma mark - Snapshots

+ (SPKProfileAnalyzerSnapshot *)currentSnapshotForUserPK:(NSString *)userPK {
    return [SPKProfileAnalyzerSnapshot snapshotFromJSONDict:spkReadJSON(spkPath(userPK, @"current"))];
}

+ (SPKProfileAnalyzerSnapshot *)previousSnapshotForUserPK:(NSString *)userPK {
    return [SPKProfileAnalyzerSnapshot snapshotFromJSONDict:spkReadJSON(spkPath(userPK, @"previous"))];
}

+ (SPKProfileAnalyzerSnapshot *)baselineSnapshotForUserPK:(NSString *)userPK {
    return [SPKProfileAnalyzerSnapshot snapshotFromJSONDict:spkReadJSON(spkPath(userPK, @"baseline"))];
}

+ (BOOL)saveBaselineSnapshot:(SPKProfileAnalyzerSnapshot *)snapshot forUserPK:(NSString *)userPK {
    if (!snapshot)
        return NO;
    BOOL ok = spkWriteJSON(spkPath(userPK, @"baseline"), [snapshot toJSONDict]);
    if (ok)
        spkPostDataChanged(userPK);
    return ok;
}

+ (void)clearBaselineForUserPK:(NSString *)userPK {
    [[NSFileManager defaultManager] removeItemAtPath:spkPath(userPK, @"baseline") error:nil];
    spkPostDataChanged(userPK);
}

+ (BOOL)saveSnapshot:(SPKProfileAnalyzerSnapshot *)snapshot forUserPK:(NSString *)userPK {
    if (!snapshot)
        return NO;
    NSString *cur = spkPath(userPK, @"current");
    NSString *prev = spkPath(userPK, @"previous");
    NSFileManager *fm = [NSFileManager defaultManager];
    // Capture the outgoing snapshot before it rotates out so we can diff it against
    // the incoming one and append the delta to the durable change log — the
    // current/previous pair only spans a single run, the log keeps the history.
    SPKProfileAnalyzerSnapshot *outgoing = [self currentSnapshotForUserPK:userPK];
    if ([fm fileExistsAtPath:cur]) {
        [fm removeItemAtPath:prev error:nil];
        [fm moveItemAtPath:cur toPath:prev error:nil];
    }
    BOOL ok = spkWriteJSON(cur, [snapshot toJSONDict]);
    if (ok) {
        if (outgoing) {
            SPKProfileAnalyzerReport *rep = [SPKProfileAnalyzerReport reportFromCurrent:snapshot previous:outgoing];
            [self appendChangeEvents:[SPKProfileAnalyzerChangeEvent eventsFromReport:rep date:snapshot.scanDate]
                           forUserPK:userPK];
        }
        spkPostDataChanged(userPK);
    }
    return ok;
}

+ (BOOL)updateCurrentSnapshot:(SPKProfileAnalyzerSnapshot *)snapshot forUserPK:(NSString *)userPK {
    if (!snapshot)
        return NO;
    BOOL ok = spkWriteJSON(spkPath(userPK, @"current"), [snapshot toJSONDict]);
    if (ok)
        spkPostDataChanged(userPK);
    return ok;
}

+ (void)resetForUserPK:(NSString *)userPK {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *slot in @[ @"current", @"previous", @"baseline", @"header", @"visits", @"changelog" ]) {
        [fm removeItemAtPath:spkPath(userPK, slot) error:nil];
    }
    spkPostDataChanged(userPK);
}

+ (void)resetAll {
    [[NSFileManager defaultManager] removeItemAtPath:spkStorageDir() error:nil];
    spkPostDataChanged(nil);
}

#pragma mark - Change log

+ (NSArray<SPKProfileAnalyzerChangeEvent *> *)changeEventsForUserPK:(NSString *)userPK {
    __block NSArray *result = @[];
    dispatch_sync(spkChangeLogQueue(), ^{
        NSArray *list = spkReadJSON(spkPath(userPK, @"changelog"))[@"events"];
        if (![list isKindOfClass:[NSArray class]])
            return;
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:list.count];
        for (NSDictionary *d in list) {
            SPKProfileAnalyzerChangeEvent *e = [SPKProfileAnalyzerChangeEvent eventFromJSONDict:d];
            if (e)
                [out addObject:e];
        }
        result = out; // stored newest-first
    });
    return result;
}

+ (void)appendChangeEvents:(NSArray<SPKProfileAnalyzerChangeEvent *> *)events forUserPK:(NSString *)userPK {
    if (!events.count)
        return;
    dispatch_sync(spkChangeLogQueue(), ^{
        NSArray *existing = spkReadJSON(spkPath(userPK, @"changelog"))[@"events"];
        NSMutableArray *list = [NSMutableArray array];
        NSMutableSet *ids = [NSMutableSet set];
        // Newest run on top, then the existing log; de-dup by eventID.
        for (SPKProfileAnalyzerChangeEvent *e in events) {
            if ([ids containsObject:e.eventID])
                continue;
            [ids addObject:e.eventID];
            [list addObject:[e toJSONDict]];
        }
        if ([existing isKindOfClass:[NSArray class]]) {
            for (NSDictionary *d in existing) {
                SPKProfileAnalyzerChangeEvent *e = [SPKProfileAnalyzerChangeEvent eventFromJSONDict:d];
                if (!e || [ids containsObject:e.eventID])
                    continue;
                [ids addObject:e.eventID];
                [list addObject:d];
            }
        }
        if (list.count > kSPKPAChangeLogCap) {
            [list removeObjectsInRange:NSMakeRange(kSPKPAChangeLogCap, list.count - kSPKPAChangeLogCap)];
        }
        spkWriteJSON(spkPath(userPK, @"changelog"), @{@"events" : list});
    });
    spkPostDataChanged(userPK);
}

+ (NSDictionary<NSNumber *, NSNumber *> *)unseenChangeCountsForUserPK:(NSString *)userPK {
    NSMutableDictionary<NSNumber *, NSNumber *> *counts = [NSMutableDictionary dictionary];
    for (SPKProfileAnalyzerChangeEvent *e in [self changeEventsForUserPK:userPK]) {
        if (e.seen)
            continue;
        NSNumber *k = @(e.type);
        counts[k] = @([counts[k] integerValue] + 1);
    }
    return counts;
}

+ (void)markChangeEventsSeenForType:(SPKPAChangeType)type forUserPK:(NSString *)userPK {
    __block BOOL changed = NO;
    dispatch_sync(spkChangeLogQueue(), ^{
        NSArray *existing = spkReadJSON(spkPath(userPK, @"changelog"))[@"events"];
        if (![existing isKindOfClass:[NSArray class]])
            return;
        NSMutableArray *list = [NSMutableArray arrayWithCapacity:existing.count];
        for (NSDictionary *d in existing) {
            if ([d isKindOfClass:[NSDictionary class]] &&
                [d[@"type"] integerValue] == type && ![d[@"seen"] boolValue]) {
                NSMutableDictionary *m = [d mutableCopy];
                m[@"seen"] = @YES;
                [list addObject:m];
                changed = YES;
            } else {
                [list addObject:d];
            }
        }
        if (changed)
            spkWriteJSON(spkPath(userPK, @"changelog"), @{@"events" : list});
    });
    if (changed)
        spkPostDataChanged(userPK);
}

+ (void)removeChangeEventsWithIDs:(NSArray<NSString *> *)eventIDs forUserPK:(NSString *)userPK {
    if (!eventIDs.count)
        return;
    NSSet *doomed = [NSSet setWithArray:eventIDs];
    __block BOOL changed = NO;
    dispatch_sync(spkChangeLogQueue(), ^{
        NSArray *existing = spkReadJSON(spkPath(userPK, @"changelog"))[@"events"];
        if (![existing isKindOfClass:[NSArray class]])
            return;
        NSMutableArray *list = [NSMutableArray arrayWithCapacity:existing.count];
        for (NSDictionary *d in existing) {
            // `eventID` is derived (type + pk + date), not stored, so rebuild to compare —
            // the same thing `appendChangeEvents:` does to de-dup.
            SPKProfileAnalyzerChangeEvent *e = [SPKProfileAnalyzerChangeEvent eventFromJSONDict:d];
            if (e && [doomed containsObject:e.eventID]) {
                changed = YES;
                continue;
            }
            [list addObject:d];
        }
        if (changed)
            spkWriteJSON(spkPath(userPK, @"changelog"), @{@"events" : list});
    });
    if (changed)
        spkPostDataChanged(userPK);
}

+ (void)clearChangeLogForUserPK:(NSString *)userPK {
    dispatch_sync(spkChangeLogQueue(), ^{
        [[NSFileManager defaultManager] removeItemAtPath:spkPath(userPK, @"changelog") error:nil];
    });
    spkPostDataChanged(userPK);
}

#pragma mark - Header cache

+ (NSDictionary *)headerInfoForUserPK:(NSString *)userPK {
    return spkReadJSON(spkPath(userPK, @"header"));
}

+ (void)saveHeaderInfo:(NSDictionary *)info forUserPK:(NSString *)userPK {
    if (![info isKindOfClass:[NSDictionary class]] || !info.count)
        return;
    NSMutableDictionary *stored = [info mutableCopy];
    stored[@"cached_at"] = @([[NSDate date] timeIntervalSince1970]);
    spkWriteJSON(spkPath(userPK, @"header"), stored);
}

#pragma mark - Visited profiles

+ (NSArray<SPKProfileAnalyzerVisit *> *)visitedProfilesForUserPK:(NSString *)userPK {
    __block NSArray *result = @[];
    dispatch_sync(spkVisitQueue(), ^{
        NSDictionary *root = spkReadJSON(spkPath(userPK, @"visits"));
        NSArray *list = root[@"visits"];
        if (![list isKindOfClass:[NSArray class]])
            return;
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:list.count];
        for (NSDictionary *d in list) {
            if (![d isKindOfClass:[NSDictionary class]])
                continue;
            SPKProfileAnalyzerVisit *v = [SPKProfileAnalyzerVisit visitFromJSONDict:d];
            if (v)
                [out addObject:v];
        }
        result = out;
    });
    return result;
}

// Locate a visit entry by pk with type-safe lookups; NSNotFound when absent.
static NSInteger spkVisitIndexForPK(NSArray *list, NSString *pk) {
    if (!pk.length)
        return NSNotFound;
    for (NSInteger i = 0; i < (NSInteger)list.count; i++) {
        id entry = list[i];
        if (![entry isKindOfClass:[NSDictionary class]])
            continue;
        id u = entry[@"user"];
        if (![u isKindOfClass:[NSDictionary class]])
            continue;
        id storedPK = u[@"pk"];
        if (![storedPK isKindOfClass:[NSString class]])
            continue;
        if ([(NSString *)storedPK isEqualToString:pk])
            return i;
    }
    return NSNotFound;
}

+ (void)recordVisitForUser:(SPKProfileAnalyzerUser *)user forUserPK:(NSString *)userPK {
    if (!user.pk.length)
        return;
    dispatch_sync(spkVisitQueue(), ^{
        NSDictionary *root = spkReadJSON(spkPath(userPK, @"visits"));
        NSMutableArray *list = [(root[@"visits"] ?: @[]) mutableCopy];

        NSDate *now = [NSDate date];
        NSInteger foundIdx = spkVisitIndexForPK(list, user.pk);
        if (foundIdx == NSNotFound) {
            SPKProfileAnalyzerVisit *v = [SPKProfileAnalyzerVisit new];
            v.user = user;
            v.firstSeen = now;
            v.lastSeen = now;
            v.visitCount = 1;
            [list insertObject:[v toJSONDict] atIndex:0];
        } else {
            // Merge: don't clobber known-good fields with empty values from a
            // half-loaded fieldCache. Booleans only flip on, never off.
            NSMutableDictionary *d = [list[foundIdx] mutableCopy];
            NSDictionary *prevUser = [d[@"user"] isKindOfClass:[NSDictionary class]] ? d[@"user"] : @{};
            NSMutableDictionary *merged = [prevUser mutableCopy];
            NSDictionary *fresh = [user toJSONDict];
            for (NSString *k in @[ @"pk", @"用户名", @"full_name", @"profile_pic_url", @"profile_pic_id" ]) {
                id v = fresh[k];
                if ([v isKindOfClass:[NSString class]] && [(NSString *)v length])
                    merged[k] = v;
            }
            if ([fresh[@"is_verified"] boolValue])
                merged[@"is_verified"] = @YES;
            if ([fresh[@"is_private"] boolValue])
                merged[@"is_private"] = @YES;

            d[@"user"] = merged;
            d[@"last_seen"] = @([now timeIntervalSince1970]);
            d[@"visit_count"] = @([d[@"visit_count"] integerValue] + 1);
            [list removeObjectAtIndex:foundIdx];
            [list insertObject:d atIndex:0]; // most-recent first
        }
        spkWriteJSON(spkPath(userPK, @"visits"), @{@"visits" : list});
        spkPostDataChanged(userPK);
    });
}

+ (void)removeVisitForUserPK:(NSString *)userPK visitedPK:(NSString *)visitedPK {
    if (!visitedPK.length)
        return;
    dispatch_sync(spkVisitQueue(), ^{
        NSDictionary *root = spkReadJSON(spkPath(userPK, @"visits"));
        NSMutableArray *list = [(root[@"visits"] ?: @[]) mutableCopy];
        NSInteger removeIdx = spkVisitIndexForPK(list, visitedPK);
        if (removeIdx == NSNotFound)
            return;
        [list removeObjectAtIndex:removeIdx];
        spkWriteJSON(spkPath(userPK, @"visits"), @{@"visits" : list});
        spkPostDataChanged(userPK);
    });
}

+ (void)clearVisitsForUserPK:(NSString *)userPK {
    dispatch_sync(spkVisitQueue(), ^{
        [[NSFileManager defaultManager] removeItemAtPath:spkPath(userPK, @"visits") error:nil];
        spkPostDataChanged(userPK);
    });
}

+ (void)refreshVisitedUser:(SPKProfileAnalyzerUser *)user forUserPK:(NSString *)userPK {
    if (!user.pk.length)
        return;
    dispatch_sync(spkVisitQueue(), ^{
        NSDictionary *root = spkReadJSON(spkPath(userPK, @"visits"));
        NSMutableArray *list = [(root[@"visits"] ?: @[]) mutableCopy];
        NSInteger idx = spkVisitIndexForPK(list, user.pk);
        if (idx == NSNotFound)
            return; // deleted between trigger + write
        NSMutableDictionary *d = [list[idx] mutableCopy];
        d[@"user"] = [user toJSONDict];
        list[idx] = d;
        spkWriteJSON(spkPath(userPK, @"visits"), @{@"visits" : list});
    });
}

#pragma mark - Maintenance / backup

+ (NSString *)storageRootPath {
    return spkStorageDir();
}

+ (unsigned long long)storageSizeBytesForUserPK:(NSString *)userPK {
    unsigned long long total = 0;
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *slot in @[ @"current", @"previous", @"baseline", @"header", @"visits", @"changelog" ]) {
        NSDictionary *attrs = [fm attributesOfItemAtPath:spkPath(userPK, slot) error:nil];
        if ([attrs[NSFileType] isEqualToString:NSFileTypeRegular]) {
            total += [attrs[NSFileSize] unsignedLongLongValue];
        }
    }
    return total;
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
        spkPostDataChanged(nil);
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

    // Distinct account PKs present in the archive ("<pk>.<slot>.json").
    NSArray<NSString *> *slots = @[ @"current", @"previous", @"baseline", @"header", @"visits", @"changelog" ];
    NSMutableSet<NSString *> *pks = [NSMutableSet set];
    for (NSString *entry in entries) {
        for (NSString *slot in slots) {
            NSString *suffix = [NSString stringWithFormat:@".%@.json", slot];
            if ([entry hasSuffix:suffix]) {
                [pks addObject:[entry substringToIndex:entry.length - suffix.length]];
                break;
            }
        }
    }

    __block NSInteger added = 0;
    for (NSString *safePK in pks) {
        if (ownerFilterPK.length > 0 && ![safePK isEqualToString:spkSafePK(ownerFilterPK)])
            continue;

        // Snapshots: fill-only — adopt the archive's set only when we have no current
        // snapshot, so an import never overwrites local analysis or a pinned baseline.
        if (![fm fileExistsAtPath:spkPath(safePK, @"current")]) {
            for (NSString *slot in @[ @"current", @"previous", @"baseline", @"header" ]) {
                NSString *src = [sourcePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@.json", safePK, slot]];
                if ([fm fileExistsAtPath:src])
                    [fm copyItemAtPath:src toPath:spkPath(safePK, slot) error:nil];
            }
        }

        // Visits: union, keeping local entries and adding archive ones we don't have.
        NSString *srcVisits = [sourcePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.visits.json", safePK]];
        if (![fm fileExistsAtPath:srcVisits])
            continue;
        dispatch_sync(spkVisitQueue(), ^{
            NSMutableArray *liveList = [(spkReadJSON(spkPath(safePK, @"visits"))[@"visits"] ?: @[]) mutableCopy];
            NSArray *srcList = spkReadJSON(srcVisits)[@"visits"] ?: @[];
            BOOL changed = NO;
            for (id entry in srcList) {
                if (![entry isKindOfClass:[NSDictionary class]])
                    continue;
                id u = entry[@"user"];
                NSString *vpk = ([u isKindOfClass:[NSDictionary class]] && [u[@"pk"] isKindOfClass:[NSString class]]) ? u[@"pk"] : nil;
                if (vpk.length == 0 || spkVisitIndexForPK(liveList, vpk) != NSNotFound)
                    continue;
                [liveList addObject:entry];
                changed = YES;
                added++;
            }
            if (changed) {
                [liveList sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                    double la = [a[@"last_seen"] doubleValue], lb = [b[@"last_seen"] doubleValue];
                    if (la > lb)
                        return NSOrderedAscending; // newest-first
                    if (la < lb)
                        return NSOrderedDescending;
                    return NSOrderedSame;
                }];
                spkWriteJSON(spkPath(safePK, @"visits"), @{@"visits" : liveList});
                spkPostDataChanged(safePK);
            }
        });

        // Change log: union by eventID, keeping local entries. If either side
        // marked an event seen, it stays seen. Sorted newest-first afterwards.
        NSString *srcLog = [sourcePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.changelog.json", safePK]];
        if (![fm fileExistsAtPath:srcLog])
            continue;
        dispatch_sync(spkChangeLogQueue(), ^{
            NSArray *srcList = spkReadJSON(srcLog)[@"events"];
            if (![srcList isKindOfClass:[NSArray class]] || !srcList.count)
                return;
            NSArray *liveRaw = spkReadJSON(spkPath(safePK, @"changelog"))[@"events"];
            NSMutableArray *merged = [NSMutableArray array];
            NSMutableDictionary<NSString *, NSNumber *> *idxByID = [NSMutableDictionary dictionary];
            void (^absorb)(NSArray *) = ^(NSArray *entries) {
                for (NSDictionary *d in entries) {
                    SPKProfileAnalyzerChangeEvent *e = [SPKProfileAnalyzerChangeEvent eventFromJSONDict:d];
                    if (!e)
                        continue;
                    NSNumber *at = idxByID[e.eventID];
                    if (at) { // seen wins across duplicates
                        if ([d[@"seen"] boolValue]) {
                            NSMutableDictionary *m = [merged[at.unsignedIntegerValue] mutableCopy];
                            m[@"seen"] = @YES;
                            merged[at.unsignedIntegerValue] = m;
                        }
                    } else {
                        idxByID[e.eventID] = @(merged.count);
                        [merged addObject:d];
                    }
                }
            };
            absorb([liveRaw isKindOfClass:[NSArray class]] ? liveRaw : @[]);
            absorb(srcList);
            [merged sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                double la = [a[@"date"] doubleValue], lb = [b[@"date"] doubleValue];
                if (la > lb)
                    return NSOrderedAscending; // newest-first
                if (la < lb)
                    return NSOrderedDescending;
                return NSOrderedSame;
            }];
            if (merged.count > kSPKPAChangeLogCap) {
                [merged removeObjectsInRange:NSMakeRange(kSPKPAChangeLogCap, merged.count - kSPKPAChangeLogCap)];
            }
            spkWriteJSON(spkPath(safePK, @"changelog"), @{@"events" : merged});
            spkPostDataChanged(safePK);
        });
    }
    return added;
}

@end
