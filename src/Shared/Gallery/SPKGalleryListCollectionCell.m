#import "SPKGalleryListCollectionCell.h"
#import "../../AssetUtils.h"
#import "../../Utils.h"
#import "SPKGalleryFile.h"

@interface SPKGalleryListCollectionCell ()

@property (nonatomic, strong) SPKGalleryFile *file;

@property (nonatomic, strong) UIImageView *thumbnailView;
@property (nonatomic, strong) UIImageView *rowTypeIcon;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *technicalLabel;
@property (nonatomic, strong) UIView *pillBackground;
@property (nonatomic, strong) UILabel *pillLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UIView *folderContextChip;
@property (nonatomic, strong) UIImageView *folderContextIcon;
@property (nonatomic, strong) UILabel *folderContextLabel;
@property (nonatomic, strong) NSLayoutConstraint *folderContextChipLeadingConstraint;
@property (nonatomic, strong) UIImageView *favoriteIcon;
@property (nonatomic, strong) UIButton *moreButton;
@property (nonatomic, strong) UIImageView *selectionIndicator;
@property (nonatomic, strong) UIView *highlightOverlay;
@property (nonatomic, strong) UIView *separator;
@property (nonatomic, strong) NSLayoutConstraint *thumbnailLeadingConstraint;
/// Bumped on every reconfigure so an async thumbnail that finishes after the cell
/// has been recycled is dropped instead of painted onto the wrong row.
@property (nonatomic, assign) NSUInteger thumbnailToken;

@end

@implementation SPKGalleryListCollectionCell

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        [self setupViews];
    }
    return self;
}

- (void)setupViews {
    self.contentView.backgroundColor = [SPKUtils SPKColor_InstagramBackground];

    self.highlightOverlay = [[UIView alloc] init];
    self.highlightOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    self.highlightOverlay.backgroundColor = [SPKUtils SPKColor_ListRowPressedOverlay];
    self.highlightOverlay.hidden = YES;
    self.highlightOverlay.userInteractionEnabled = NO;
    [self.contentView addSubview:self.highlightOverlay];

    self.thumbnailView = [[UIImageView alloc] init];
    self.thumbnailView.translatesAutoresizingMaskIntoConstraints = NO;
    self.thumbnailView.contentMode = UIViewContentModeScaleAspectFill;
    self.thumbnailView.clipsToBounds = YES;
    self.thumbnailView.layer.cornerRadius = 6;
    self.thumbnailView.backgroundColor = [SPKUtils SPKColor_InstagramSecondaryBackground];
    [self.contentView addSubview:self.thumbnailView];

    self.rowTypeIcon = [[UIImageView alloc] init];
    self.rowTypeIcon.translatesAutoresizingMaskIntoConstraints = NO;
    self.rowTypeIcon.contentMode = UIViewContentModeScaleAspectFit;
    self.rowTypeIcon.tintColor = [SPKUtils SPKColor_InstagramSecondaryText];
    [self.contentView addSubview:self.rowTypeIcon];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.titleLabel.textColor = [SPKUtils SPKColor_InstagramPrimaryText];
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.contentView addSubview:self.titleLabel];

    self.technicalLabel = [[UILabel alloc] init];
    self.technicalLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.technicalLabel.font = [UIFont systemFontOfSize:12];
    self.technicalLabel.textColor = [SPKUtils SPKColor_InstagramSecondaryText];
    self.technicalLabel.numberOfLines = 1;
    self.technicalLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.contentView addSubview:self.technicalLabel];

    self.pillBackground = [[UIView alloc] init];
    self.pillBackground.translatesAutoresizingMaskIntoConstraints = NO;
    self.pillBackground.backgroundColor = [SPKUtils SPKColor_InstagramTertiaryBackground];
    self.pillBackground.layer.cornerRadius = 5;
    self.pillBackground.clipsToBounds = YES;
    [self.contentView addSubview:self.pillBackground];

    self.pillLabel = [[UILabel alloc] init];
    self.pillLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.pillLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    self.pillLabel.textColor = [SPKUtils SPKColor_InstagramSecondaryText];
    self.pillLabel.numberOfLines = 1;
    [self.pillBackground addSubview:self.pillLabel];

    self.dateLabel = [[UILabel alloc] init];
    self.dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.dateLabel.font = [UIFont systemFontOfSize:11];
    self.dateLabel.textColor = [SPKUtils SPKColor_InstagramTertiaryText];
    self.dateLabel.numberOfLines = 1;
    self.dateLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.contentView addSubview:self.dateLabel];

    self.folderContextChip = [[UIView alloc] init];
    self.folderContextChip.translatesAutoresizingMaskIntoConstraints = NO;
    self.folderContextChip.backgroundColor = [SPKUtils SPKColor_InstagramTertiaryBackground];
    self.folderContextChip.layer.cornerRadius = 5;
    self.folderContextChip.clipsToBounds = YES;
    self.folderContextChip.hidden = YES;
    [self.contentView addSubview:self.folderContextChip];

    self.folderContextIcon = [[UIImageView alloc] init];
    self.folderContextIcon.translatesAutoresizingMaskIntoConstraints = NO;
    self.folderContextIcon.contentMode = UIViewContentModeScaleAspectFit;
    self.folderContextIcon.tintColor = [SPKUtils SPKColor_InstagramSecondaryText];
    [self.folderContextChip addSubview:self.folderContextIcon];

    self.folderContextLabel = [[UILabel alloc] init];
    self.folderContextLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.folderContextLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    self.folderContextLabel.textColor = [SPKUtils SPKColor_InstagramSecondaryText];
    self.folderContextLabel.numberOfLines = 1;
    self.folderContextLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.folderContextChip addSubview:self.folderContextLabel];

    UIImage *favImg = [SPKAssetUtils instagramIconNamed:@"heart_filled" pointSize:14.0];
    self.favoriteIcon = [[UIImageView alloc] initWithImage:favImg];
    self.favoriteIcon.contentMode = UIViewContentModeScaleAspectFit;
    self.favoriteIcon.translatesAutoresizingMaskIntoConstraints = NO;
    self.favoriteIcon.tintColor = [SPKUtils SPKColor_InstagramFavorite];
    self.favoriteIcon.hidden = YES;
    [self.contentView addSubview:self.favoriteIcon];

    self.selectionIndicator = [[UIImageView alloc] init];
    self.selectionIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.selectionIndicator.contentMode = UIViewContentModeScaleAspectFit;
    self.selectionIndicator.tintColor = [SPKUtils SPKColor_InstagramSecondaryText];
    self.selectionIndicator.hidden = YES;
    [self.contentView addSubview:self.selectionIndicator];

    UIImage *moreImg = [SPKAssetUtils instagramIconNamed:@"more" pointSize:22.0];
    self.moreButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.moreButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.moreButton setImage:moreImg forState:UIControlStateNormal];
    self.moreButton.tintColor = [SPKUtils SPKColor_InstagramSecondaryText];
    self.moreButton.accessibilityLabel = @"更多";
    self.moreButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    self.moreButton.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    [self.contentView addSubview:self.moreButton];

    self.thumbnailLeadingConstraint = [self.thumbnailView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16];

    // Folder context chip trails the date on the third row; hidden when the cell
    // isn't showing a search result's home folder.
    self.folderContextChipLeadingConstraint = [self.folderContextChip.leadingAnchor constraintEqualToAnchor:self.dateLabel.trailingAnchor constant:8];

    self.separator = [[UIView alloc] init];
    self.separator.translatesAutoresizingMaskIntoConstraints = NO;
    self.separator.backgroundColor = [SPKUtils SPKColor_InstagramSeparator];
    [self.contentView addSubview:self.separator];

    [NSLayoutConstraint activateConstraints:@[
        [self.highlightOverlay.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.highlightOverlay.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.highlightOverlay.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [self.highlightOverlay.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

        [self.selectionIndicator.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                              constant:16],
        [self.selectionIndicator.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.selectionIndicator.widthAnchor constraintEqualToConstant:20],
        [self.selectionIndicator.heightAnchor constraintEqualToConstant:20],

        self.thumbnailLeadingConstraint,
        [self.thumbnailView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.thumbnailView.widthAnchor constraintEqualToConstant:52],
        [self.thumbnailView.heightAnchor constraintEqualToConstant:52],

        [self.moreButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                       constant:-8],
        [self.moreButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.moreButton.widthAnchor constraintEqualToConstant:40],
        [self.moreButton.heightAnchor constraintEqualToConstant:40],

        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.thumbnailView.trailingAnchor
                                                      constant:12],
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.thumbnailView.topAnchor
                                                  constant:-1],
        [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.favoriteIcon.leadingAnchor
                                                                 constant:-4],

        [self.rowTypeIcon.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.rowTypeIcon.centerYAnchor constraintEqualToAnchor:self.technicalLabel.centerYAnchor],
        [self.rowTypeIcon.widthAnchor constraintEqualToConstant:14],
        [self.rowTypeIcon.heightAnchor constraintEqualToConstant:14],

        [self.technicalLabel.leadingAnchor constraintEqualToAnchor:self.rowTypeIcon.trailingAnchor
                                                          constant:4],
        [self.technicalLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor
                                                      constant:3],
        [self.technicalLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.moreButton.leadingAnchor
                                                                     constant:-8],

        [self.pillBackground.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.pillBackground.topAnchor constraintEqualToAnchor:self.technicalLabel.bottomAnchor
                                                      constant:4],
        [self.pillLabel.leadingAnchor constraintEqualToAnchor:self.pillBackground.leadingAnchor
                                                     constant:8],
        [self.pillLabel.trailingAnchor constraintEqualToAnchor:self.pillBackground.trailingAnchor
                                                      constant:-8],
        [self.pillLabel.topAnchor constraintEqualToAnchor:self.pillBackground.topAnchor
                                                 constant:3],
        [self.pillLabel.bottomAnchor constraintEqualToAnchor:self.pillBackground.bottomAnchor
                                                    constant:-3],

        [self.dateLabel.leadingAnchor constraintEqualToAnchor:self.pillBackground.trailingAnchor
                                                     constant:8],
        [self.dateLabel.centerYAnchor constraintEqualToAnchor:self.pillBackground.centerYAnchor],
        [self.dateLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.moreButton.leadingAnchor
                                                                constant:-8],

        self.folderContextChipLeadingConstraint,
        [self.folderContextChip.centerYAnchor constraintEqualToAnchor:self.pillBackground.centerYAnchor],
        [self.folderContextChip.trailingAnchor constraintLessThanOrEqualToAnchor:self.moreButton.leadingAnchor
                                                                        constant:-8],

        [self.folderContextIcon.leadingAnchor constraintEqualToAnchor:self.folderContextChip.leadingAnchor
                                                             constant:7],
        [self.folderContextIcon.centerYAnchor constraintEqualToAnchor:self.folderContextChip.centerYAnchor],
        [self.folderContextIcon.widthAnchor constraintEqualToConstant:12],
        [self.folderContextIcon.heightAnchor constraintEqualToConstant:12],

        [self.folderContextLabel.leadingAnchor constraintEqualToAnchor:self.folderContextIcon.trailingAnchor
                                                              constant:3],
        [self.folderContextLabel.trailingAnchor constraintEqualToAnchor:self.folderContextChip.trailingAnchor
                                                               constant:-8],
        [self.folderContextLabel.topAnchor constraintEqualToAnchor:self.folderContextChip.topAnchor
                                                          constant:3],
        [self.folderContextLabel.bottomAnchor constraintEqualToAnchor:self.folderContextChip.bottomAnchor
                                                             constant:-3],

        [self.favoriteIcon.trailingAnchor constraintEqualToAnchor:self.moreButton.leadingAnchor
                                                         constant:-6],
        [self.favoriteIcon.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],
        [self.favoriteIcon.widthAnchor constraintEqualToConstant:14],
        [self.favoriteIcon.heightAnchor constraintEqualToConstant:14],

        [self.separator.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                     constant:80],
        [self.separator.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.separator.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        [self.separator.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
    ]];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.highlightOverlay.hidden = !highlighted;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    // Minimal for the same reason as SPKGalleryGridCell: configureWithGalleryFile:
    // (plus the setMoreActionsMenu: that callers pair with it) reassigns all of
    // this immediately after dequeue, and clearing it here costs an Auto Layout
    // invalidation per property, per cell -- which measured as essentially the
    // entire dequeue cost while scrolling.
    self.thumbnailToken++;
    self.file = nil;
    self.thumbnailView.image = nil;
    // The menu is the one thing not every caller sets, and a stale one would
    // attach the previous row's actions to this cell.
    self.moreButton.menu = nil;
    self.moreButton.showsMenuAsPrimaryAction = NO;
}

- (UIImage *)selectionIndicatorImageSelected:(BOOL)selected {
    NSString *resourceName = selected ? @"circle_check_filled" : @"circle";
    return [SPKAssetUtils instagramIconNamed:resourceName pointSize:20.0];
}

- (void)setFolderContextName:(NSString *)folderName {
    // The home folder of a search result is shown as a chip at the tail of the
    // third row (after the source pill and date), led by a folder glyph.
    if (folderName.length == 0) {
        self.folderContextChip.hidden = YES;
        self.folderContextLabel.text = nil;
        return;
    }
    if (!self.folderContextIcon.image) {
        self.folderContextIcon.image = [SPKAssetUtils instagramIconNamed:@"folder" pointSize:12.0];
    }
    self.folderContextLabel.text = folderName;
    self.folderContextChip.hidden = NO;
}

- (void)configureWithGalleryFile:(SPKGalleryFile *)file
                   selectionMode:(BOOL)selectionMode
                        selected:(BOOL)selected {
    self.file = file;
    self.titleLabel.text = [file listPrimaryTitle];
    self.technicalLabel.text = [file listTechnicalLine];
    self.pillLabel.text = [file shortSourceLabel];
    [self setFolderContextName:nil];
    self.dateLabel.text = [file listDownloadDateString];

    BOOL isVideo = (file.mediaType == SPKGalleryMediaTypeVideo);
    BOOL isAudio = (file.mediaType == SPKGalleryMediaTypeAudio);
    UIImage *rowIcon = [SPKAssetUtils instagramIconNamed:(isAudio ? @"audio_filled" : (isVideo ? @"video_filled" : @"photo_filled"))
                                               pointSize:12];
    self.rowTypeIcon.image = rowIcon;

    self.favoriteIcon.hidden = !file.isFavorite;

    [self setSelectionMode:selectionMode selected:selected animated:NO];

    // In-memory hits only on the main thread; disk reads and decodes happen on a
    // background queue so scrolling never stalls on them. See the grid cell.
    NSUInteger token = ++self.thumbnailToken;
    UIImage *thumb = [SPKGalleryFile cachedThumbnailForFile:file];
    if (thumb) {
        self.thumbnailView.image = thumb;
    } else {
        self.thumbnailView.image = nil;
        __weak typeof(self) weakSelf = self;
        [SPKGalleryFile loadThumbnailAsyncForFile:file
                                       completion:^(UIImage *loaded) {
                                           if (loaded && weakSelf.thumbnailToken == token) {
                                               weakSelf.thumbnailView.image = loaded;
                                           }
                                       }];
    }
}

- (void)setSelectionMode:(BOOL)selectionMode selected:(BOOL)selected animated:(BOOL)animated {
    self.selectionIndicator.image = selectionMode ? [self selectionIndicatorImageSelected:selected] : nil;
    if (selectionMode) {
        self.selectionIndicator.hidden = NO;
    }
    if (!selectionMode) {
        self.moreButton.hidden = (self.moreButton.menu == nil);
    }

    self.thumbnailLeadingConstraint.constant = selectionMode ? 56.0 : 16.0;

    void (^applyState)(void) = ^{
        self.selectionIndicator.alpha = selectionMode ? 1.0 : 0.0;
        self.moreButton.alpha = (selectionMode || self.moreButton.menu == nil) ? 0.0 : 1.0;
        [self.contentView layoutIfNeeded];
    };
    void (^finishState)(void) = ^{
        self.selectionIndicator.hidden = !selectionMode;
        self.moreButton.hidden = selectionMode || (self.moreButton.menu == nil);
    };

    if (animated) {
        [UIView animateWithDuration:0.22
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:applyState
                         completion:^(__unused BOOL finished) {
                             finishState();
                         }];
    } else {
        applyState();
        finishState();
    }
}

- (void)setMoreActionsMenu:(UIMenu *)menu {
    self.moreButton.menu = menu;
    self.moreButton.showsMenuAsPrimaryAction = (menu != nil);

    BOOL hidden = (menu == nil);
    self.moreButton.hidden = hidden;
    // Callers configure the cell first and attach the menu second, so
    // setSelectionMode:selected:animated: has already run and computed the
    // button's alpha from a menu that was still nil -- leaving it at 0. Without
    // re-deriving alpha here the button unhides but stays fully transparent.
    self.moreButton.alpha = hidden ? 0.0 : 1.0;
}

@end
