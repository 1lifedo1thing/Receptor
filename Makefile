ARCHS = armv7
TARGET = iphone:clang:5.0:4.0
INSTALL_TARGET_PROCESSES = MobileSafari

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Receptor
Receptor_FILES = Tweak.x ReceptorPolicyProxy.m ReceptorUI.m ReceptorPaths.m DownloadManager.m FileBrowserViewController.m
Receptor_FRAMEWORKS = UIKit Foundation QuickLook MobileCoreServices
# Modern Theos stubs point at the newer CydiaSubstrate.framework location.
# Link the legacy install name used by Substrate on iOS 4 through 6.
Receptor_LIBRARIES = LegacySubstrate
Receptor_LDFLAGS = -L$(THEOS_PROJECT_DIR)/lib
Receptor_CFLAGS = -fno-objc-arc -fblocks -Wall -Wextra

include $(THEOS_MAKE_PATH)/tweak.mk
