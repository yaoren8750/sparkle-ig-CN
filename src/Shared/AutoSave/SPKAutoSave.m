#import "SPKAutoSave.h"

#import "../../Utils.h"
#import "../Downloads/SPKDownloadHelpers.h"
#import "../Downloads/SPKDownloadJob.h"
#import "../Downloads/SPKDownloadService.h"
#import "../Downloads/SPKDownloadTypes.h"
#import "../Gallery/SPKGalleryFile.h"
#import "../Gallery/SPKGallerySaveMetadata.h"
#import "../Gallery/SPKGalleryViewController.h"
#import "../MediaDownload/SPKMediaQualityManager.h"
#import "../UI/SPKNotificationCenter.h"

NSString *const kSPKAutoSaveDestinationKey = @"downloads_autosave_destination";
NSString *const kSPKAutoSaveVideoQualityKey = @"downloads_autosave_video_quality";
NSString *const kSPKAutoSavePhotoQualityKey = @"downloads_autosave_photo_quality";
NSString *const kSPKAutoSaveKeepHistoryKey = @"downloads_autosave_keep_history";

static NSMutableSet<NSString *> *SPKAutoSaveNotificationIdentifiers(void) {
    static NSMutableSet<NSString *> *identifiers = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        identifiers = [NSMutableSet set];
    });
    return identifiers;
}

SPKDownloadDestination SPKAutoSaveDestination(void) {
    return [[SPKUtils getStringPref:kSPKAutoSaveDestinationKey] isEqualToString:@"photos"]
               ? SPKDownloadDestinationPhotos
               : SPKDownloadDestinationGallery;
}

void SPKAutoSaveRegisterNotificationIdentifier(NSString *identifier) {
    if (identifier.length == 0)
        return;
    [SPKAutoSaveNotificationIdentifiers() addObject:identifier];
}

#pragma mark - Session state

// Feedback is session-scoped: one "started" pill on the first save, one summary once
// every job has drained. All of this is touched only from the main thread -- submission
// runs from the story overlay's layoutSubviews, and the job watcher observes on the main
// queue -- so no locking.
static NSUInteger SPKAutoSaveSessionSavedCount = 0;
static NSUInteger SPKAutoSaveSessionFailedCount = 0;
static NSUInteger SPKAutoSaveSessionPendingCount = 0;
static BOOL SPKAutoSaveSessionStarted = NO;
static BOOL SPKAutoSaveSessionEnded = NO;
// Bumped on every reset so an armed flush timeout belonging to a finished session
// can tell that it's stale and bow out.
static NSUInteger SPKAutoSaveSessionGeneration = 0;
// Captured on the session's first submission rather than read at flush time, so
// changing the destination mid-session can't make the summary offer to open the
// place the items didn't go.
static SPKDownloadDestination SPKAutoSaveSessionDestination = SPKDownloadDestinationGallery;

// A job that never reports a terminal state (dropped as a duplicate inside the quality
// manager, or lost to an app-level failure) would otherwise pin the summary forever.
static const NSTimeInterval kSPKAutoSaveDrainTimeout = 30.0;

static void SPKAutoSaveResetSession(void) {
    SPKAutoSaveSessionSavedCount = 0;
    SPKAutoSaveSessionFailedCount = 0;
    SPKAutoSaveSessionPendingCount = 0;
    SPKAutoSaveSessionStarted = NO;
    SPKAutoSaveSessionEnded = NO;
    SPKAutoSaveSessionDestination = SPKDownloadDestinationGallery;
    SPKAutoSaveSessionGeneration++;
}

static void SPKAutoSaveFlushSummaryIfDrained(void) {
    if (!SPKAutoSaveSessionEnded || SPKAutoSaveSessionPendingCount > 0)
        return;

    NSUInteger saved = SPKAutoSaveSessionSavedCount;
    NSUInteger failed = SPKAutoSaveSessionFailedCount;
    BOOL toPhotos = SPKAutoSaveSessionDestination == SPKDownloadDestinationPhotos;
    SPKAutoSaveResetSession();

    if (saved == 0 && failed == 0)
        return;

    NSString *title = saved == 1 ? @"Auto-saved 1 item"
                                 : [NSString stringWithFormat:@"Auto-saved %lu items", (unsigned long)saved];
    NSString *subtitle = toPhotos ? @"点击打开照片" : @"点击打开图库";
    if (failed > 0) {
        subtitle = failed == 1 ? @"1 item failed" : [NSString stringWithFormat:@"%lu items failed", (unsigned long)failed];
        if (saved == 0)
            title = @"Auto-save failed";
    }

    // Nothing landed, so there's nothing to go look at -- leave the pill inert.
    void (^onTap)(void) = nil;
    if (saved > 0) {
        onTap = toPhotos ? ^{
            [SPKUtils openPhotosApp];
        }
                         : ^{
                               // Presents from the topmost controller and runs the Vault's Face ID /
                               // passcode gate itself, so this is safe from wherever the pill is tapped.
                               [SPKGalleryViewController presentGallery];
                           };
    }

    SPKNotifyTappable(kSPKNotificationAutoSaveSummary, title, subtitle, toPhotos ? @"photo" : @"sparkle_gallery",
                      saved > 0 ? SPKNotificationToneSuccess : SPKNotificationToneError, onTap);
}

static void SPKAutoSaveNoteSubmission(NSString *notificationIdentifier, SPKDownloadDestination destination) {
    // A save arriving after the session was declared over means a new session began
    // without the previous one draining (it timed out, or the viewer reopened fast).
    // Start clean rather than folding the two together.
    if (SPKAutoSaveSessionEnded)
        SPKAutoSaveResetSession();

    SPKAutoSaveSessionPendingCount++;
    if (SPKAutoSaveSessionStarted)
        return;
    SPKAutoSaveSessionStarted = YES;
    SPKAutoSaveSessionDestination = destination;

    SPKNotify(notificationIdentifier, @"Auto-save started",
              [NSString stringWithFormat:@"Saving to %@", SPKDownloadDestinationDisplayName(destination)],
              @"info_filled", SPKNotificationToneInfo);
}

#pragma mark - Submission

BOOL SPKAutoSaveSubmitMedia(id media,
                            SPKActionButtonSource source,
                            NSString *username,
                            NSString *notificationIdentifier) {
    if (!media)
        return NO;

    NSURL *photoURL = nil;
    NSURL *videoURL = nil;
    SPKGallerySaveMetadata *metadata = nil;
    if (!SPKResolveGalleryDownloadForMedia(media, source, username, &photoURL, &videoURL, &metadata))
        return NO;
    metadata.isAutoSave = YES;

    BOOL isVideo = (videoURL != nil);
    NSString *quality = [SPKUtils getStringPref:(isVideo ? kSPKAutoSaveVideoQualityKey : kSPKAutoSavePhotoQualityKey)];
    if (quality.length == 0)
        quality = isVideo ? @"high_ignore_dash" : @"high";

    SPKDownloadSourceSurface surface = [SPKDownloadHelpers sourceSurfaceForActionButtonSource:source];
    SPKDownloadDestination destination = SPKAutoSaveDestination();
    SPKAutoSaveNoteSubmission(notificationIdentifier, destination);

    // The quality manager owns DASH resolution + muxing -- skipping it is what made
    // auto-saved videos land as raw DASH artifacts instead of playable files.
    if ([SPKMediaQualityManager handleDownloadDestination:destination
                                               identifier:notificationIdentifier
                                                presenter:nil
                                               sourceView:nil
                                              mediaObject:media
                                                 photoURL:photoURL
                                                 videoURL:videoURL
                                          galleryMetadata:metadata
                                             showProgress:NO
                                            sourceSurface:surface
                                          qualityOverride:quality]) {
        return YES;
    }

    // The manager declines when it can't analyze the media into any option. The
    // resolved URL is still downloadable, so fall back to a plain quiet submission.
    NSURL *url = videoURL ?: photoURL;
    NSString *extension = url.pathExtension.length > 0 ? url.pathExtension : (isVideo ? @"mp4" : @"jpg");
    [SPKDownloadHelpers submitRemoteURL:url
                              extension:extension
                            destination:destination
                               metadata:metadata
                         notificationID:notificationIdentifier
                              presenter:nil
                             anchorView:nil
                          sourceSurface:surface
                           showProgress:NO];
    return YES;
}

#pragma mark - Job watcher

// A job can report a terminal state more than once (the scheduler posts per item
// change), so remember the ones already handled to avoid double-counting the summary
// and double-posting the pill.
static NSMutableSet<NSString *> *SPKAutoSaveHandledJobIDs(void) {
    static NSMutableSet<NSString *> *jobIDs = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        jobIDs = [NSMutableSet set];
    });
    return jobIDs;
}

static void SPKAutoSaveHandleFinishedJob(SPKDownloadJob *job) {
    NSString *identifier = job.request.notificationIdentifier;
    if (identifier.length == 0 || ![SPKAutoSaveNotificationIdentifiers() containsObject:identifier])
        return;

    if (job.jobID.length == 0 || [SPKAutoSaveHandledJobIDs() containsObject:job.jobID])
        return;
    [SPKAutoSaveHandledJobIDs() addObject:job.jobID];

    // Terminal means fully saved, merge included: a DASH item runs FFmpeg inside the
    // job and only then reaches Succeeded. That's what makes the drained count honest.
    if (SPKAutoSaveSessionPendingCount > 0)
        SPKAutoSaveSessionPendingCount--;

    if (job.state == SPKDownloadStateSucceeded) {
        SPKAutoSaveSessionSavedCount++;
        // Auto-saves are background noise in the Downloads list, so they're pruned
        // unless the user opts to keep them.
        if (![SPKUtils getBoolPref:kSPKAutoSaveKeepHistoryKey]) {
            [[SPKDownloadService shared] removeJobID:job.jobID];
        }
    } else {
        SPKAutoSaveSessionFailedCount++;
        SPKLog(@"General", @"[Sparkle AutoSave] Download did not succeed jobID=%@ state=%ld", job.jobID, (long)job.state);
    }

    // The viewer is usually already dismissed by the time a merge lands, so this --
    // not the dismissal -- is what normally posts the summary.
    SPKAutoSaveFlushSummaryIfDrained();
}

void SPKAutoSaveStartWatching(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:SPKDownloadJobDidChangeNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
                                                          SPKDownloadJob *snapshot = note.userInfo[SPKDownloadNotificationSnapshotKey];
                                                          if (!snapshot || !SPKDownloadStateIsTerminal(snapshot.state))
                                                              return;
                                                          SPKAutoSaveHandleFinishedJob(snapshot);
                                                      }];
    });
}

void SPKAutoSaveSessionDidEnd(void) {
    if (!SPKAutoSaveSessionStarted || SPKAutoSaveSessionEnded)
        return;
    SPKAutoSaveSessionEnded = YES;

    if (SPKAutoSaveSessionPendingCount == 0) {
        SPKAutoSaveFlushSummaryIfDrained();
        return;
    }

    // The summary is deliberately withheld until everything lands, which can be a while
    // after dismissal when High quality is muxing DASH video and audio. Say so, rather
    // than leaving the viewer thinking nothing happened.
    NSUInteger pending = SPKAutoSaveSessionPendingCount;
    SPKNotify(kSPKNotificationAutoSavePending, @"Auto-save still working",
              pending == 1 ? @"1 item is being processed"
                           : [NSString stringWithFormat:@"%lu items are being processed", (unsigned long)pending],
              @"history", SPKNotificationToneInfo);

    // Still downloading or merging. The watcher posts the summary the moment the last
    // job lands; this only catches jobs that never report back at all.
    NSUInteger generation = SPKAutoSaveSessionGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSPKAutoSaveDrainTimeout * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                       if (generation != SPKAutoSaveSessionGeneration)
                           return;
                       SPKLog(@"General", @"[Sparkle AutoSave] Drain timed out with %lu job(s) outstanding",
                              (unsigned long)SPKAutoSaveSessionPendingCount);
                       SPKAutoSaveSessionPendingCount = 0;
                       SPKAutoSaveFlushSummaryIfDrained();
                   });
}
