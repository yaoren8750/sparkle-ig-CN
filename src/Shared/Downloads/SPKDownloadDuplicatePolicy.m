#import "SPKDownloadDuplicatePolicy.h"

#import <Photos/Photos.h>

#import "../../Utils.h"
#import "../Gallery/SPKGalleryCoreDataStack.h"
#import "../Gallery/SPKGalleryFile.h"
#import "../Gallery/SPKGalleryHiddenSources.h"
#import "../Gallery/SPKGallerySaveMetadata.h"
#import "../UI/SPKIGAlertPresenter.h"

// Constants
static NSString *const kSPKPhotosSaveLedgerKey = @"general_detect_duplicate_photos_ledger_v2";
static NSUInteger const kSPKPhotosSaveLedgerLimit = 2000;

// Internal decision enums for alerts
typedef NS_ENUM(NSInteger, SPKDownloadDuplicateDecision) {
    SPKDownloadDuplicateDecisionDownloadAgain = 1,
    SPKDownloadDuplicateDecisionDeleteExistingAndDownloadAgain = 2,
    SPKDownloadDuplicateDecisionCancel = 3,
};

typedef NS_ENUM(NSInteger, SPKDownloadBulkDuplicateDecision) {
    SPKDownloadBulkDuplicateDecisionSkipExisting = 1,
    SPKDownloadBulkDuplicateDecisionDownloadAllAnyway,
    SPKDownloadBulkDuplicateDecisionCancel,
};

// Helper functions
static NSString *SPKNormalizedMediaURLString(NSString *string) {
    NSURLComponents *components = [NSURLComponents componentsWithString:string];
    if (!components)
        return string;
    components.query = nil;
    components.fragment = nil;
    return components.string ?: string;
}

static NSString *SPKDuplicateKey(SPKGallerySaveMetadata *metadata, NSInteger mediaType) {
    if (!metadata)
        return nil;
    NSString *identity = nil;
    if (metadata.sourceMediaPK.length > 0) {
        identity = [@"pk:" stringByAppendingString:metadata.sourceMediaPK];
        // Differentiate carousel slides by their img_index
        if (metadata.sourceMediaURLString.length > 0) {
            NSURLComponents *components = [NSURLComponents componentsWithString:metadata.sourceMediaURLString];
            for (NSURLQueryItem *item in components.queryItems) {
                if ([item.name isEqualToString:@"img_index"] && item.value.length > 0) {
                    identity = [identity stringByAppendingFormat:@"|idx:%@", item.value];
                    break;
                }
            }
        }
    } else if (metadata.sourceMediaURLString.length > 0) {
        identity = [@"url:" stringByAppendingString:SPKNormalizedMediaURLString(metadata.sourceMediaURLString)];
    }
    if (identity.length == 0)
        return nil;
    return [NSString stringWithFormat:@"%ld|%@", (long)mediaType, identity];
}

static NSString *SPKMediaTypeLabel(NSInteger mediaType) {
    switch (mediaType) {
    case SPKGalleryMediaTypeVideo:
        return @"video";
    case SPKGalleryMediaTypeAudio:
        return @"audio";
    case SPKGalleryMediaTypeImage:
    default:
        return @"photo";
    }
}

static NSString *SPKDestinationLabel(SPKDownloadDuplicateDestination destination) {
    return destination == SPKDownloadDuplicateDestinationPhotos ? @"Photos" : @"图库";
}

static SPKGalleryFile *SPKExistingGalleryFile(SPKGallerySaveMetadata *metadata, NSInteger mediaType) {
    NSString *key = SPKDuplicateKey(metadata, mediaType);
    if (key.length == 0)
        return nil;
    __block SPKGalleryFile *match = nil;
    NSManagedObjectContext *context = [SPKGalleryCoreDataStack shared].viewContext;
    [context performBlockAndWait:^{
        NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"SPKGalleryFile"];
        // Narrow to the same sourceMediaPK when we have one. A row with a different
        // (or empty) sourceMediaPK can never produce a "pk:"-based key equal to this
        // one, so this is equivalent to scanning every row of the media type — but it
        // avoids fetching the whole table and stat-ing each file, which is what made
        // auto-save stutter the story viewer on large galleries.
        NSPredicate *predicate = nil;
        if (metadata.sourceMediaPK.length > 0) {
            predicate = [NSPredicate predicateWithFormat:@"mediaType == %d AND sourceMediaPK == %@",
                                                         (int)mediaType, metadata.sourceMediaPK];
        } else {
            predicate = [NSPredicate predicateWithFormat:@"mediaType == %d", (int)mediaType];
        }        // "Already in the Gallery" has to mean the Gallery the user can actually see.
        // With per-account filtering on, another account's copy is invisible to them, so
        // counting it as a duplicate would silently make the media unsavable.
        NSPredicate *accountScope = SPKGalleryAccountScopePredicate();
        if (accountScope)
            predicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[ predicate, accountScope ]];
        request.predicate = predicate;
        NSArray<SPKGalleryFile *> *files = [context executeFetchRequest:request error:nil] ?: @[];
        for (SPKGalleryFile *file in files) {
            SPKGallerySaveMetadata *stored = [[SPKGallerySaveMetadata alloc] init];
            stored.sourceMediaPK = file.sourceMediaPK;
            stored.sourceMediaURLString = file.sourceMediaURLString;
            if ([SPKDuplicateKey(stored, mediaType) isEqualToString:key] && [file fileExists]) {
                match = file;
                break;
            }
        }
    }];
    return match;
}

static NSMutableDictionary<NSString *, NSString *> *SPKPhotosSaveLedger(void) {
    NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kSPKPhotosSaveLedgerKey];
    return [saved isKindOfClass:NSDictionary.class] ? [saved mutableCopy] : [NSMutableDictionary dictionary];
}

static void SPKPhotosSaveLedgerRemoveKey(NSString *key) {
    if (key.length == 0)
        return;
    @synchronized([SPKDownloadDuplicatePolicy class]) {
        NSMutableDictionary<NSString *, NSString *> *ledger = SPKPhotosSaveLedger();
        if (!ledger[key])
            return;
        [ledger removeObjectForKey:key];
        [[NSUserDefaults standardUserDefaults] setObject:ledger forKey:kSPKPhotosSaveLedgerKey];
    }
}

// The Photos counterpart of the Gallery branch's `fileExists`: a ledger entry only
// counts while the asset it points at is still in the library, so deleting the photo in
// Photos lets it be saved again instead of being skipped forever.
static BOOL SPKPhotosLedgerEntryIsLive(NSString *key, NSString *localIdentifier) {
    if (localIdentifier.length == 0)
        return NO;
    // Verifying means *reading* the library, which add-only and limited access don't
    // allow -- a fetch there comes back empty even for assets we did save, which would
    // read as "deleted" and re-save every item on every view. Without read access the
    // ledger is the only evidence there is, so trust it.
    if ([PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite] != PHAuthorizationStatusAuthorized)
        return YES;

    if ([PHAsset fetchAssetsWithLocalIdentifiers:@[ localIdentifier ] options:nil].count > 0)
        return YES;

    SPKPhotosSaveLedgerRemoveKey(key);
    return NO;
}

static BOOL SPKHasDuplicate(SPKDownloadDuplicateDestination destination, SPKGallerySaveMetadata *metadata, NSInteger mediaType) {
    NSString *key = SPKDuplicateKey(metadata, mediaType);
    if (key.length == 0)
        return NO;
    if (destination == SPKDownloadDuplicateDestinationPhotos) {
        return SPKPhotosLedgerEntryIsLive(key, SPKPhotosSaveLedger()[key]);
    }
    return SPKExistingGalleryFile(metadata, mediaType) != nil;
}

static BOOL SPKPresentSingleDuplicateAlert(SPKDownloadDuplicateDestination destination,
                                           SPKGallerySaveMetadata *metadata,
                                           NSInteger mediaType,
                                           UIViewController *presenter,
                                           void (^continuation)(SPKDownloadDuplicateDecision)) {
    if (!SPKHasDuplicate(destination, metadata, mediaType))
        return NO;
    NSString *message = [NSString stringWithFormat:@"此%@之前已下载到%@。",
                                                   SPKMediaTypeLabel(mediaType),
                                                   SPKDestinationLabel(destination)];
    [SPKIGAlertPresenter presentAlertFromViewController:presenter
                                                  title:@"检测到重复下载"
                                                message:message
                                                actions:@[
                                                    [SPKIGAlertAction actionWithTitle:@"仍然下载"
                                                                                style:SPKIGAlertActionStyleDefault
                                                                              handler:^{
                                                                                  if (continuation)
                                                                                      continuation(SPKDownloadDuplicateDecisionDownloadAgain);
                                                                              }],
                                                    [SPKIGAlertAction actionWithTitle:@"删除现有文件并下载"
                                                                                style:SPKIGAlertActionStyleDestructive
                                                                              handler:^{
                                                                                  if (continuation)
                                                                                      continuation(SPKDownloadDuplicateDecisionDeleteExistingAndDownloadAgain);
                                                                              }],
                                                    [SPKIGAlertAction actionWithTitle:@"取消"
                                                                                style:SPKIGAlertActionStyleCancel
                                                                              handler:^{
                                                                                  if (continuation)
                                                                                      continuation(SPKDownloadDuplicateDecisionCancel);
                                                                              }],
                                                ]];
    return YES;
}

static BOOL SPKPresentBulkDuplicateAlert(NSUInteger duplicateCount,
                                         NSUInteger totalCount,
                                         UIViewController *presenter,
                                         void (^continuation)(SPKDownloadBulkDuplicateDecision)) {
    if (duplicateCount == 0 || !continuation)
        return NO;
    NSString *message = [NSString stringWithFormat:@"%lu / %lu 个项目已下载。",
                                                   (unsigned long)duplicateCount, (unsigned long)totalCount];
    [SPKIGAlertPresenter presentAlertFromViewController:presenter ?: topMostController()
                                                  title:@"检测到重复下载"
                                                message:message
                                                actions:@[
                                                    [SPKIGAlertAction actionWithTitle:@"跳过已存在的"
                                                                                style:SPKIGAlertActionStyleDefault
                                                                              handler:^{
                                                                                  continuation(SPKDownloadBulkDuplicateDecisionSkipExisting);
                                                                              }],
                                                    [SPKIGAlertAction actionWithTitle:@"仍然全部下载"
                                                                                style:SPKIGAlertActionStyleDefault
                                                                              handler:^{
                                                                                  continuation(SPKDownloadBulkDuplicateDecisionDownloadAllAnyway);
                                                                              }],
                                                    [SPKIGAlertAction actionWithTitle:@"取消"
                                                                                style:SPKIGAlertActionStyleCancel
                                                                              handler:^{
                                                                                  continuation(SPKDownloadBulkDuplicateDecisionCancel);
                                                                              }],
                                                ]];
    return YES;
}

static void SPKDeleteExistingDuplicate(SPKDownloadDuplicateDestination destination,
                                       SPKGallerySaveMetadata *metadata,
                                       NSInteger mediaType,
                                       void (^completion)(BOOL, NSError *)) {
    if (destination == SPKDownloadDuplicateDestinationGallery) {
        SPKGalleryFile *file = SPKExistingGalleryFile(metadata, mediaType);
        NSError *error = nil;
        BOOL success = !file || [file removeWithError:&error];
        if (completion)
            completion(success, error);
        return;
    }
    NSString *key = SPKDuplicateKey(metadata, mediaType);
    NSMutableDictionary<NSString *, NSString *> *ledger = SPKPhotosSaveLedger();
    NSString *localIdentifier = ledger[key];
    PHFetchResult<PHAsset *> *assets = localIdentifier.length > 0
                                           ? [PHAsset fetchAssetsWithLocalIdentifiers:@[ localIdentifier ] options:nil]
                                           : nil;
    if (assets.count == 0) {
        [ledger removeObjectForKey:key];
        [[NSUserDefaults standardUserDefaults] setObject:ledger forKey:kSPKPhotosSaveLedgerKey];
        if (completion)
            completion(YES, nil);
        return;
    }
    [[PHPhotoLibrary sharedPhotoLibrary]
        performChanges:^{
            [PHAssetChangeRequest deleteAssets:assets];
        }
        completionHandler:^(BOOL success, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (success) {
                    NSMutableDictionary<NSString *, NSString *> *updatedLedger = SPKPhotosSaveLedger();
                    [updatedLedger removeObjectForKey:key];
                    [[NSUserDefaults standardUserDefaults] setObject:updatedLedger forKey:kSPKPhotosSaveLedgerKey];
                }
                if (completion)
                    completion(success, error);
            });
        }];
}
@implementation SPKDownloadDuplicatePolicy

- (BOOL)duplicateDetectionEnabled {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:kSPKDownloadDetectDuplicatesKey])
        return NO;
    return YES;
}

- (BOOL)duplicateDestinationFor:(SPKDownloadDestination)destination outValue:(SPKDownloadDuplicateDestination *)outValue {
    switch (destination) {
    case SPKDownloadDestinationPhotos:
        if (outValue)
            *outValue = SPKDownloadDuplicateDestinationPhotos;
        return YES;
    case SPKDownloadDestinationGallery:
        if (outValue)
            *outValue = SPKDownloadDuplicateDestinationGallery;
        return YES;
    default:
        return NO;
    }
}

- (NSInteger)mediaTypeForKind:(SPKDownloadMediaKind)kind {
    switch (kind) {
    case SPKDownloadMediaKindVideo:
        return SPKGalleryMediaTypeVideo;
    case SPKDownloadMediaKindAudio:
        return SPKGalleryMediaTypeAudio;
    case SPKDownloadMediaKindImage:
        return SPKGalleryMediaTypeImage;
    default:
        return SPKGalleryMediaTypeImage;
    }
}

- (NSUInteger)duplicateCountForRequest:(SPKDownloadRequest *)request destination:(SPKDownloadDuplicateDestination)dest {
    NSUInteger duplicateCount = 0;
    for (SPKDownloadItemRequest *item in request.items) {
        SPKGallerySaveMetadata *metadata = item.metadata ?: request.metadata;
        if (SPKHasDuplicate(dest, metadata, [self mediaTypeForKind:item.mediaKind])) {
            duplicateCount++;
        }
    }
    return duplicateCount;
}

- (void)runPreflightForRequest:(SPKDownloadRequest *)request
                     presenter:(UIViewController *)presenter
                    completion:(SPKDownloadPreflightCompletion)completion {
    if (![self duplicateDetectionEnabled]) {
        completion(SPKDownloadPreflightContinue);
        return;
    }
    if (request.destination != SPKDownloadDestinationPhotos && request.destination != SPKDownloadDestinationGallery) {
        completion(SPKDownloadPreflightContinue);
        return;
    }
    if (request.duplicatePolicy == SPKDownloadDuplicatePolicyAlwaysDownload) {
        completion(SPKDownloadPreflightContinue);
        return;
    }
    if (request.duplicatePolicy == SPKDownloadDuplicatePolicySkipExisting) {
        completion(SPKDownloadPreflightSkipSucceeded);
        return;
    }

    SPKDownloadDuplicateDestination dest = SPKDownloadDuplicateDestinationGallery;
    if (![self duplicateDestinationFor:request.destination outValue:&dest]) {
        completion(SPKDownloadPreflightContinue);
        return;
    }
    if (request.items.count == 1) {
        SPKDownloadItemRequest *item = request.items.firstObject;
        SPKGallerySaveMetadata *metadata = item.metadata ?: request.metadata;
        BOOL presented = SPKPresentSingleDuplicateAlert(dest, metadata, [self mediaTypeForKind:item.mediaKind],
                                                        presenter ?: topMostController(),
                                                        ^(SPKDownloadDuplicateDecision decision) {
                                                            if (decision == SPKDownloadDuplicateDecisionCancel) {
                                                                completion(SPKDownloadPreflightCancelled);
                                                                return;
                                                            }
                                                            if (decision == SPKDownloadDuplicateDecisionDeleteExistingAndDownloadAgain) {
                                                                SPKDeleteExistingDuplicate(dest, metadata, [self mediaTypeForKind:item.mediaKind],
                                                                                           ^(BOOL success, NSError *error) {
                                                                                               (void)error;
                                                                                               if (success)
                                                                                                   completion(SPKDownloadPreflightContinue);
                                                                                               else
                                                                                                   completion(SPKDownloadPreflightCancelled);
                                                                                           });
                                                            } else {
                                                                completion(SPKDownloadPreflightContinue);
                                                            }
                                                        });
        if (!presented)
            completion(SPKDownloadPreflightContinue);
        return;
    }

    NSUInteger duplicateCount = [self duplicateCountForRequest:request destination:dest];
    if (duplicateCount == 0) {
        completion(SPKDownloadPreflightContinue);
        return;
    }

    BOOL presented = SPKPresentBulkDuplicateAlert(duplicateCount, request.items.count,
                                                  presenter ?: topMostController(),
                                                  ^(SPKDownloadBulkDuplicateDecision decision) {
                                                      switch (decision) {
                                                      case SPKDownloadBulkDuplicateDecisionSkipExisting:
                                                          completion(SPKDownloadPreflightSkipSucceeded);
                                                          break;
                                                      case SPKDownloadBulkDuplicateDecisionDownloadAllAnyway:
                                                          completion(SPKDownloadPreflightContinue);
                                                          break;
                                                      case SPKDownloadBulkDuplicateDecisionCancel:
                                                      default:
                                                          completion(SPKDownloadPreflightCancelled);
                                                          break;
                                                      }
                                                  });
    if (!presented)
        completion(SPKDownloadPreflightContinue);
}

#pragma mark - Public Utilities

+ (BOOL)hasDuplicateForDestination:(SPKDownloadDuplicateDestination)destination
                          metadata:(SPKGallerySaveMetadata *)metadata
                         mediaType:(NSInteger)mediaType {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:kSPKDownloadDetectDuplicatesKey])
        return NO;
    return SPKHasDuplicate(destination, metadata, mediaType);
}

+ (BOOL)destinationContainsMediaForMetadata:(SPKGallerySaveMetadata *)metadata
                                  mediaType:(NSInteger)mediaType
                                destination:(SPKDownloadDestination)destination {
    switch (destination) {
    case SPKDownloadDestinationPhotos:
        return SPKHasDuplicate(SPKDownloadDuplicateDestinationPhotos, metadata, mediaType);
    case SPKDownloadDestinationGallery:
        return SPKHasDuplicate(SPKDownloadDuplicateDestinationGallery, metadata, mediaType);
    default:
        return NO;
    }
}

+ (void)recordPhotosSaveWithMetadata:(SPKGallerySaveMetadata *)metadata
                           mediaType:(NSInteger)mediaType
                assetLocalIdentifier:(NSString *)assetLocalIdentifier {
    NSString *key = SPKDuplicateKey(metadata, mediaType);
    if (key.length == 0 || assetLocalIdentifier.length == 0)
        return;
    @synchronized(self) {
        NSMutableDictionary<NSString *, NSString *> *ledger = SPKPhotosSaveLedger();
        ledger[key] = assetLocalIdentifier;
        if (ledger.count > kSPKPhotosSaveLedgerLimit) {
            NSArray<NSString *> *keys = ledger.allKeys;
            NSUInteger removeCount = ledger.count - kSPKPhotosSaveLedgerLimit;
            [ledger removeObjectsForKeys:[keys subarrayWithRange:NSMakeRange(0, removeCount)]];
        }
        [[NSUserDefaults standardUserDefaults] setObject:ledger forKey:kSPKPhotosSaveLedgerKey];
    }
}

@end
