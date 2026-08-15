#import "SPKStoragePaths.h"
#import "../Utils.h"

static NSString *SPKDocumentsDirectory(void) {
    return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
}

static BOOL SPKEnsureDirectory(NSString *path) {
    if (!path.length)
        return NO;
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL isDirectory = NO;
    if ([fm fileExistsAtPath:path isDirectory:&isDirectory])
        return isDirectory;

    NSError *error = nil;
    BOOL created = [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error];
    if (!created)
        SPKWarnLog(@"Storage", @"Failed to create directory %@: %@", path, error);
    return created;
}

static NSString *SPKStorageRoot(void) {
    NSString *root = [SPKDocumentsDirectory() stringByAppendingPathComponent:@"Sparkle"];
    SPKEnsureDirectory(root);
    return root;
}

static NSString *SPKStorageFeatureDirectory(NSString *featureName) {
    NSString *directory = [SPKStorageRoot() stringByAppendingPathComponent:featureName];
    SPKEnsureDirectory(directory);
    return directory;
}

@implementation SPKStoragePaths

+ (NSString *)galleryDirectory {
    return SPKStorageFeatureDirectory(@"图库");
}

+ (NSString *)deletedMessagesDirectory {
    return SPKStorageFeatureDirectory(@"DeletedMessages");
}

+ (NSString *)deletedMessagesPendingDirectory {
    return SPKStorageFeatureDirectory(@"DeletedMessagesPending");
}

+ (NSString *)profileAnalyzerDirectory {
    return SPKStorageFeatureDirectory(@"ProfileAnalyzer");
}

+ (NSString *)downloadsDirectory {
    return SPKStorageFeatureDirectory(@"下载");
}

+ (NSString *)avatarCacheDirectory {
    return SPKStorageFeatureDirectory(@"Avatars");
}

+ (unsigned long long)sizeOfDirectory:(NSString *)path {
    if (path.length == 0)
        return 0;
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL isDirectory = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory)
        return 0;

    NSArray<NSURLResourceKey> *resourceKeys = @[ NSURLIsRegularFileKey, NSURLFileSizeKey ];
    NSURL *root = [NSURL fileURLWithPath:path isDirectory:YES];
    NSDirectoryEnumerator<NSURL *> *enumerator = [fm enumeratorAtURL:root
                                          includingPropertiesForKeys:resourceKeys
                                                             options:0
                                                        errorHandler:nil];
    unsigned long long total = 0;
    for (NSURL *fileURL in enumerator) {
        NSDictionary<NSURLResourceKey, id> *values = [fileURL resourceValuesForKeys:resourceKeys error:nil];
        if ([values[NSURLIsRegularFileKey] boolValue]) {
            total += [values[NSURLFileSizeKey] unsignedLongLongValue];
        }
    }
    return total;
}

+ (NSDictionary<NSString *, NSNumber *> *)storageBreakdown {
    unsigned long long gallery = [self sizeOfDirectory:[self galleryDirectory]];
    unsigned long long downloads = [self sizeOfDirectory:[self downloadsDirectory]];
    unsigned long long deletedMessages = [self sizeOfDirectory:[self deletedMessagesDirectory]] + [self sizeOfDirectory:[self deletedMessagesPendingDirectory]];
    unsigned long long profileAnalyzer = [self sizeOfDirectory:[self profileAnalyzerDirectory]];
    unsigned long long avatars = [self sizeOfDirectory:[self avatarCacheDirectory]];
    unsigned long long total = gallery + downloads + deletedMessages + profileAnalyzer + avatars;

    return @{
        @"gallery" : @(gallery),
        @"downloads" : @(downloads),
        @"deletedMessages" : @(deletedMessages),
        @"profileAnalyzer" : @(profileAnalyzer),
        @"avatars" : @(avatars),
        @"total" : @(total),
    };
}

@end
