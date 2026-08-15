#import "SPKRegramImporter.h"

#import <sqlite3.h>

#import "../../Settings/SPKSettingsTransferManager.h"
#import "../../Utils.h"
#import "SPKGalleryFile.h"
#import "SPKGallerySaveMetadata.h"

#pragma mark - Enum mapping

// Regram `ZRGVFILE.ZTYPE` → Sparkle media type. Falls back to extension sniffing.
static SPKGalleryMediaType SPKRegramMediaType(int rgType, NSString *path) {
    switch (rgType) {
        case 1:
            return SPKGalleryMediaTypeImage;
        case 2:
            return SPKGalleryMediaTypeVideo;
        case 3:
            return SPKGalleryMediaTypeAudio;
        default:
            return [SPKGalleryFile inferMediaTypeFromFileURL:[NSURL fileURLWithPath:path ?: @""]];
    }
}

// Regram `ZRGVFILE.ZSOURCE` → Sparkle source. Regram's enum is its own, non-contiguous set. The
// COMPLETE value set (0–13) and its semantics were reverse-engineered from Regram.dylib's
// `+[RGMediaVaultManager sourceGroups]`, which buckets every source into a UI group (observed slug
// in parentheses). Regram's grouping is coarser than Sparkle's, so where Sparkle has a finer source
// (Profile / Thumbnail / AudioPage) we prefer it over Regram's catch-all "Other" bucket. Values with
// no Sparkle equivalent fall through to Other; the filename-slug heuristic in the import pipeline
// then recovers the real source anyway, since Regram basenames share Sparkle's
// `epoch_user_slug_date` layout.
//
// Regram sourceGroups (authoritative): Feed{1,11} Stories{2} Reels{5,6} DMs{3,4} Notes{7}
// Instants{12} Comments{13} Other{0,8,9,10}. Per-value slugs (RE'd from the slug string pool +
// DB correlation): 1 feed, 2 story, 3 dm, 4 dm-story, 5 tv, 6 reel, 7 dm-note, 8 profile-photo,
// 9 highlight-cover, 10 cover, 11 post-audio, 12 instant, 13 comment; 0 = default/unspecified.
static SPKGallerySource SPKRegramSource(int rgSource) {
    switch (rgSource) {
        case 1:
            return SPKGallerySourceFeed;  // _feed  (Feed group)
        case 2:
            return SPKGallerySourceStories;  // _story  (Stories group)
        case 3:
            return SPKGallerySourceDMs;  // _dm  (DMs group)
        case 4:
            return SPKGallerySourceDMs;  // _dm-story  (DMs group)
        case 7:
            // Notes group in Regram. Sparkle has no Notes source; notes live on the messages tab, so
            // they're filed under DMs (no separate filter entry) rather than Other.
            return SPKGallerySourceDMs;
        case 5:
            return SPKGallerySourceReels;  // _tv  (IGTV; Reels group)
        case 6:
            return SPKGallerySourceReels;  // _reel  (Reels group)
        case 8:
            return SPKGallerySourceProfile;  // _profile-photo  (Regram: Other; refined to Profile)
        case 9:
            return SPKGallerySourceThumbnail;  // _highlight-cover  (Regram: Other; a cover image)
        case 10:
            return SPKGallerySourceThumbnail;  // _cover  (Regram: Other; refined to Thumbnail)
        case 11:
            return SPKGallerySourceAudioPage;  // _post-audio  (Regram: Feed; refined to AudioPage)
        case 12:
            return SPKGallerySourceInstants;  // _instant  (Instants group)
        case 13:
            return SPKGallerySourceComments;  // _comment  (Comments group)
        // 0 = default/unspecified (no slug) → Other. (7 = Notes/_dm-note handled above → DMs.)
        default:
            return SPKGallerySourceOther;
    }
}

// Regram `ZMEDIAID` is either a bare numeric media pk, "<mediaPK>_<userPK>", or a synthetic id
// (e.g. "instant_url_..."). Return the leading digits when they look like a real pk, else nil.
static NSString *SPKRegramMediaPK(NSString *mediaId) {
    if (mediaId.length == 0) {
        return nil;
    }
    NSString *head = [[mediaId componentsSeparatedByString:@"_"] firstObject];
    if (head.length == 0) {
        return nil;
    }
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if ([head rangeOfCharacterFromSet:nonDigits].location != NSNotFound) {
        return nil;
    }
    return head;
}

#pragma mark - Filesystem helpers

// Depth-first search for the first entry whose last path component matches (case-insensitively)
// any of `names`. The Regram vault is small, so an unbounded walk is fine.
static NSString *SPKRegramFindNamed(NSString *root, NSArray<NSString *> *names) {
    if (root.length == 0) {
        return nil;
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *e = [fm enumeratorAtPath:root];
    for (NSString *rel in e) {
        NSString *last = rel.lastPathComponent.lowercaseString;
        for (NSString *n in names) {
            if ([last isEqualToString:n.lowercaseString]) {
                return [root stringByAppendingPathComponent:rel];
            }
        }
    }
    return nil;
}

// Resolves a picked folder/zip URL to a local working directory root.
static NSString *SPKRegramWorkingRoot(NSURL *url) {
    NSNumber *isDir = nil;
    [url getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
    if (isDir.boolValue) {
        return url.path;  // asCopy:YES already handed us an owned copy of the folder
    }
    NSString *ext = url.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"zip"]) {
        return [SPKSettingsTransferManager expandZipArchiveAtURL:url error:nil];
    }
    if ([ext isEqualToString:@"sqlite"]) {
        return url.path.stringByDeletingLastPathComponent;
    }
    return nil;
}

// Locates the MediaVault.sqlite for a resolved working root, expanding an inner MediaVault.zip if the
// user picked a full export folder/zip. Returns the sqlite path (with `Files/` alongside), or nil.
static NSString *SPKRegramLocateSQLite(NSString *root) {
    NSString *sqlitePath = SPKRegramFindNamed(root, @[ @"MediaVault.sqlite" ]);
    if (sqlitePath) {
        return sqlitePath;
    }
    NSString *innerZip = SPKRegramFindNamed(root, @[ @"MediaVault.zip" ]);
    if (innerZip) {
        NSString *expanded = [SPKSettingsTransferManager expandZipArchiveAtURL:[NSURL fileURLWithPath:innerZip] error:nil];
        return SPKRegramFindNamed(expanded, @[ @"MediaVault.sqlite" ]);
    }
    return nil;
}

#pragma mark - SQLite read

static NSArray<NSDictionary *> *SPKRegramReadRows(NSString *sqlitePath, NSString *filesRoot) {
    sqlite3 *db = NULL;
    // Read-write so SQLite can merge a WAL sidecar if the export wasn't checkpointed.
    if (sqlite3_open(sqlitePath.fileSystemRepresentation, &db) != SQLITE_OK) {
        if (db) {
            sqlite3_close(db);
        }
        SPKLog(@"Regram", @"Could not open MediaVault.sqlite");
        return @[];
    }

    const char *sql =
        "SELECT f.ZTYPE, f.ZSOURCE, f.ZISFAVORITE, f.ZRELATIVEPATH, f.ZFOLDERPATH, "
        "f.ZMEDIACODE, f.ZMEDIAID, f.ZWIDTH, f.ZHEIGHT, f.ZDURATION, f.ZDATE, "
        "u.ZUSERNAME, u.ZFULLNAME, u.ZPK "
        "FROM ZRGVFILE f LEFT JOIN ZRGVUSER u ON f.ZUSER = u.Z_PK "
        "ORDER BY f.ZDATE";

    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        SPKLog(@"Regram", @"Unexpected MediaVault schema: %s", sqlite3_errmsg(db));
        sqlite3_close(db);
        return @[];
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];

    NSString *(^text)(int) = ^NSString *(int col) {
        const unsigned char *t = sqlite3_column_text(stmt, col);
        return t ? [NSString stringWithUTF8String:(const char *)t] : nil;
    };

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        NSString *relativePath = text(3);
        if (relativePath.length == 0) {
            continue;
        }
        NSString *mediaPath = [filesRoot stringByAppendingPathComponent:relativePath];
        if (![fm fileExistsAtPath:mediaPath]) {
            continue;  // orphaned DB row with no backing file
        }

        NSMutableDictionary *row = [NSMutableDictionary dictionary];
        row[@"type"] = @(sqlite3_column_int(stmt, 0));
        row[@"source"] = @(sqlite3_column_int(stmt, 1));
        row[@"favorite"] = @(sqlite3_column_int(stmt, 2) != 0);
        row[@"path"] = mediaPath;
        row[@"basename"] = relativePath.lastPathComponent;
        if (text(5).length) {
            row[@"mediaCode"] = text(5);
        }
        if (text(6).length) {
            row[@"mediaId"] = text(6);
        }
        if (sqlite3_column_type(stmt, 7) != SQLITE_NULL) {
            row[@"width"] = @(sqlite3_column_double(stmt, 7));
        }
        if (sqlite3_column_type(stmt, 8) != SQLITE_NULL) {
            row[@"height"] = @(sqlite3_column_double(stmt, 8));
        }
        if (sqlite3_column_type(stmt, 9) != SQLITE_NULL) {
            row[@"duration"] = @(sqlite3_column_double(stmt, 9));
        }
        if (sqlite3_column_type(stmt, 10) != SQLITE_NULL) {
            row[@"date"] = [NSDate dateWithTimeIntervalSinceReferenceDate:sqlite3_column_double(stmt, 10)];
        }
        if (text(11).length) {
            row[@"用户名"] = text(11);
        }
        if (text(12).length) {
            row[@"fullName"] = text(12);
        }
        if (text(13).length) {
            row[@"userPK"] = text(13);
        }
        [rows addObject:row];
    }

    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return rows;
}

#pragma mark - Public reader API

@implementation SPKRegramImporter

+ (NSArray<NSDictionary *> *)vaultRowsFromPickedURL:(NSURL *)url {
    if (!url) {
        return nil;
    }
    NSString *root = SPKRegramWorkingRoot(url);
    NSString *sqlitePath = SPKRegramLocateSQLite(root);
    if (!sqlitePath) {
        return nil;  // not a Regram vault
    }
    NSString *filesRoot = [sqlitePath.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"Files"];
    SPKLog(@"Regram", @"Vault sqlite=%@ filesRoot exists=%d", sqlitePath, [[NSFileManager defaultManager] fileExistsAtPath:filesRoot]);
    NSArray<NSDictionary *> *rows = SPKRegramReadRows(sqlitePath, filesRoot);
    return rows.count > 0 ? rows : nil;
}

+ (NSString *)filePathForRow:(NSDictionary *)row {
    return row[@"path"];
}

+ (SPKGalleryMediaType)mediaTypeForRow:(NSDictionary *)row {
    return SPKRegramMediaType([row[@"type"] intValue], row[@"path"]);
}

+ (BOOL)isFavoriteRow:(NSDictionary *)row {
    return [row[@"favorite"] boolValue];
}

+ (SPKGallerySaveMetadata *)metadataForRow:(NSDictionary *)row {
    SPKGallerySaveMetadata *meta = [SPKGallerySaveMetadata new];
    meta.source = (int16_t)SPKRegramSource([row[@"source"] intValue]);
    meta.sourceUsername = row[@"用户名"];
    meta.sourceUserPK = row[@"userPK"];
    meta.sourceFullName = row[@"fullName"];
    meta.sourceMediaCode = row[@"mediaCode"];
    meta.sourceMediaPK = SPKRegramMediaPK(row[@"mediaId"]);
    if ([row[@"width"] doubleValue] > 0) {
        meta.pixelWidth = (int32_t)[row[@"width"] doubleValue];
    }
    if ([row[@"height"] doubleValue] > 0) {
        meta.pixelHeight = (int32_t)[row[@"height"] doubleValue];
    }
    if ([row[@"duration"] doubleValue] > 0) {
        meta.durationSeconds = [row[@"duration"] doubleValue];
    }
    meta.importCapturedDate = row[@"date"];
    // Fill gaps (posted date, and source/user when the DB was sparse) from the Regram basename,
    // which shares Sparkle's own `epoch_user_slug_date` filename layout.
    SPKGalleryApplyImportHeuristicsFromFilename(row[@"basename"], meta);
    return meta;
}

@end
