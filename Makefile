DEBUG = 0
FINALPACKAGE = 1

ARCHS = arm64 arm64e

# Share the SDK and deployment targets with the PreferenceBundle.
include AxsDuoDesktopBuild.mk
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AxsDuoDesktop
AxsDuoDesktop_FILES = $(wildcard Hooks/*.xm Sources/*.m)
AxsDuoDesktop_CFLAGS = -fobjc-arc -I./Headers -I./Sources
AxsDuoDesktop_FRAMEWORKS = UIKit Foundation CoreFoundation QuartzCore EventKit

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += AxsDuoDesktopPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk
