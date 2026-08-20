TARGET := iphone:clang:16.2:15.0
INSTALL_TARGET_PROCESSES = Instagram
ARCHS = arm64

ifneq ($(DEV),1)
DEBUG = 0
FINALPACKAGE = 1
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Sparkle

$(TWEAK_NAME)_FILES = $(shell find src -type f \( -iname \*.x -o -iname \*.xm -o -iname \*.m -o -iname \*.swift \)) modules/SPKSideloadFix/fishhook/fishhook.c
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation CoreGraphics Photos CoreServices SystemConfiguration SafariServices Security QuartzCore AVFoundation AVKit CoreData LocalAuthentication ImageIO UniformTypeIdentifiers Accelerate VisionKit UserNotifications
$(TWEAK_NAME)_PRIVATE_FRAMEWORKS = Preferences
$(TWEAK_NAME)_LIBRARIES = sqlite3
$(TWEAK_NAME)_CFLAGS = -fobjc-arc -Wno-unsupported-availability-guard -Wno-unused-value -Wno-deprecated-declarations -Wno-nullability-completeness -Wno-unused-function -Wno-incompatible-pointer-types

$(TWEAK_NAME)_LOGOSFLAGS = --c warnings=none

STARTUP_PROFILING ?= 0
$(TWEAK_NAME)_CFLAGS += -DSTARTUP_PROFILING=$(STARTUP_PROFILING)

ifeq ($(SIDELOAD),1)
$(TWEAK_NAME)_CFLAGS += -DSPK_SIDELOAD=1
endif

ifneq ($(DEV),1)
$(TWEAK_NAME)_CFLAGS += -O2 -DNDEBUG
$(TWEAK_NAME)_LDFLAGS += -Wl,-S
else
$(TWEAK_NAME)_CFLAGS += -DSPK_DEV=1
endif

$(TWEAK_NAME)_CXXFLAGS += -std=c++11

include $(THEOS_MAKE_PATH)/tweak.mk

after-stage::
	@mkdir -p $(THEOS_STAGING_DIR)/Library/Application\ Support/Sparkle.bundle/FFmpegKit
	@cp -a modules/ffmpegkit/*.framework $(THEOS_STAGING_DIR)/Library/Application\ Support/Sparkle.bundle/FFmpegKit/
	@for fw in $(THEOS_STAGING_DIR)/Library/Application\ Support/Sparkle.bundle/FFmpegKit/*.framework; do \
		name=$$(basename "$$fw" .framework); \
		install_name_tool -id "@loader_path/../$$name.framework/$$name" "$$fw/$$name"; \
		for dep in libavcodec libavdevice libavfilter libavformat libavutil libswresample libswscale; do \
			install_name_tool -change "@rpath/$$dep.framework/$$dep" "@loader_path/../$$dep.framework/$$dep" "$$fw/$$name" 2>/dev/null || true; \
		done; \
		ldid -S "$$fw/$$name"; \
	done
