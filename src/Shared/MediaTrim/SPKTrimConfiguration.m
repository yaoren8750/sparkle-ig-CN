#import "SPKTrimConfiguration.h"

@implementation SPKTrimDoneOption

+ (instancetype)optionWithTitle:(NSString *)title
                     identifier:(NSString *)identifier
                       iconName:(NSString *)iconName {
    SPKTrimDoneOption *option = [[self alloc] init];
    option.title = title;
    option.identifier = identifier;
    option.iconName = iconName;
    return option;
}

@end

@implementation SPKTrimConfiguration

- (instancetype)init {
    self = [super init];
    if (self) {
        _mediaKind = SPKTrimMediaKindVideo;
        _allowsFrameOnly = YES;
        _allowsAudioOnly = YES;
        _allowsCrop = YES;
        _minimumDuration = 0.3;
        _title = @"裁剪";
    }
    return self;
}

+ (instancetype)configurationWithVideoURL:(NSURL *)videoURL {
    SPKTrimConfiguration *config = [[self alloc] init];
    config.sourceURL = videoURL;
    config.mediaKind = SPKTrimMediaKindVideo;
    return config;
}

+ (instancetype)configurationWithAudioURL:(NSURL *)audioURL {
    SPKTrimConfiguration *config = [[self alloc] init];
    config.sourceURL = audioURL;
    config.mediaKind = SPKTrimMediaKindAudio;
    config.allowsFrameOnly = NO;
    config.allowsCrop = NO;
    config.title = @"裁剪音频";
    return config;
}

@end
