include ../AxsDuoDesktopBuild.mk
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AxsDuoDesktopPrefs
AxsDuoDesktopPrefs_FILES = $(wildcard *.m)
AxsDuoDesktopPrefs_CFLAGS = -fobjc-arc -I../Sources
AxsDuoDesktopPrefs_FRAMEWORKS = UIKit Foundation CoreFoundation
AxsDuoDesktopPrefs_PRIVATE_FRAMEWORKS = Preferences
AxsDuoDesktopPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
