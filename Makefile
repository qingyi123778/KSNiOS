export THEOS_PACKAGE_SCHEME = rootless
export ARCHS = arm64 arm64e
export TARGET = iphone:clang:16.5:15.0
export DEBUG = 0
export FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = KSNiOS

KSNiOS_FILES = Tweak.xm \
	Sources/KSNStore.m \
	Sources/KSNBridge.m \
	Sources/KSNWebInjector.m \
	Sources/KSNNotifier.m \
	Sources/KSNLifecycle.m \
	Sources/KSNBackgroundSigner.m \
	Sources/KSNPanel.m

KSNiOS_CFLAGS = -fobjc-arc -ISources -Wno-unused-function -Wno-deprecated-declarations
KSNiOS_FRAMEWORKS = UIKit Foundation WebKit UserNotifications CoreLocation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk

before-all::
	@command -v python3 >/dev/null 2>&1 && python3 scripts/embed_js.py || python scripts/embed_js.py
