#import "../../AssetUtils.h"
#import "../../Utils.h"

// Replace the Meta-AI "gen AI" search glyph with the plain search icon
// when Meta AI in Explore & Search is hidden.

static inline BOOL SPKSearchIconRemapActive(void) {
    return [SPKUtils getBoolPref:@"general_hide_meta_ai_explore"];
}

static BOOL SPKNameIsGenAISearchIcon(NSString *name) {
    return [name isKindOfClass:[NSString class]] &&
           [name containsString:@"gen_ai"] &&
           [name containsString:@"search"];
}

static NSString *SPKPlainSearchIconName(NSString *genAIName) {
    // ig_icon_search_gen_ai_pano_outline_20
    // ->
    // ig_icon_search_pano_outline_20
    return [genAIName stringByReplacingOccurrencesOfString:@"_gen_ai"
                                                withString:@""];
}

%group SPKSearchBarIconRemapHooks

%hook UIImage

+ (UIImage *)imageNamed:(NSString *)name
               inBundle:(NSBundle *)bundle
compatibleWithTraitCollection:(UITraitCollection *)traitCollection {

    // Name check first; preference is only read for matching icons.
    if (SPKNameIsGenAISearchIcon(name) &&
        SPKSearchIconRemapActive()) {

        NSString *plain = SPKPlainSearchIconName(name);

        UIImage *replacement =
            %orig(plain, bundle, traitCollection);

        if (!replacement) {
            replacement =
                %orig(plain, nil, traitCollection);
        }

        if (!replacement) {
            replacement =
                [SPKAssetUtils instagramIconNamed:@"search"];
        }

        if (replacement) {
            return replacement;
        }
    }

    return %orig;
}


+ (UIImage *)imageNamed:(NSString *)name
               inBundle:(NSBundle *)bundle
     withConfiguration:(UIImageConfiguration *)configuration {

    if (SPKNameIsGenAISearchIcon(name) &&
        SPKSearchIconRemapActive()) {

        NSString *plain = SPKPlainSearchIconName(name);

        UIImage *replacement =
            %orig(plain, bundle, configuration);

        if (!replacement) {
            replacement =
                %orig(plain, nil, configuration);
        }

        if (!replacement) {
            replacement =
                [SPKAssetUtils instagramIconNamed:@"search"];
        }

        if (replacement) {
            return replacement;
        }
    }

    return %orig;
}


+ (UIImage *)imageNamed:(NSString *)name {

    if (SPKNameIsGenAISearchIcon(name) &&
        SPKSearchIconRemapActive()) {

        NSString *plain = SPKPlainSearchIconName(name);

        UIImage *replacement =
            %orig(plain);

        if (!replacement) {
            replacement =
                [SPKAssetUtils instagramIconNamed:@"search"];
        }

        if (replacement) {
            return replacement;
        }
    }

    return %orig;
}

%end

%end


void SPKInstallSearchBarIconRemapHooksIfNeeded(void) {
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        %init(SPKSearchBarIconRemapHooks);
    });
}
