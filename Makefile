ARCHS = armv7
TARGET = iphone:clang:5.0:4.0
INSTALL_TARGET_PROCESSES = MobileSafari ReceptorApp

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Receptor
Receptor_FILES = Tweak.x ReceptorPolicyProxy.m ReceptorUI.m ReceptorPaths.m DownloadManager.m RCCurlTransfer.m
Receptor_FRAMEWORKS = UIKit Foundation QuickLook MobileCoreServices
# Modern Theos stubs point at the newer CydiaSubstrate.framework location.
# Link the legacy install name used by Substrate on iOS 4 through 6.
Receptor_LIBRARIES = LegacySubstrate curl mbedtls mbedx509 mbedcrypto
Receptor_LDFLAGS = -L$(THEOS_PROJECT_DIR)/lib -L$(THEOS_PROJECT_DIR)/vendor/tls/lib
Receptor_CFLAGS = -fno-objc-arc -fblocks -Wall -Wextra -I$(THEOS_PROJECT_DIR)/vendor/tls/include

include $(THEOS_MAKE_PATH)/tweak.mk

APPLICATION_NAME = ReceptorApp
ReceptorApp_FILES = App/main.m App/RCAppDelegate.m ReceptorUI.m ReceptorPaths.m DownloadManager.m RCCurlTransfer.m FileBrowserViewController.m RCFileArtwork.m RCIPAInstaller.m RCDEBInstaller.m RCCompanionClient.m RCCompanionViewController.m RCPairingCrypto.c
ReceptorApp_FRAMEWORKS = UIKit Foundation QuickLook MobileCoreServices Security ImageIO CoreGraphics
ReceptorApp_LIBRARIES = curl mbedtls mbedx509 mbedcrypto
ReceptorApp_LDFLAGS = -L$(THEOS_PROJECT_DIR)/vendor/tls/lib
ReceptorApp_CFLAGS = -fno-objc-arc -fblocks -Wall -Wextra -I$(THEOS_PROJECT_DIR)/vendor/tls/include
ReceptorApp_BUNDLE_NAME = Receptor
ReceptorApp_RESOURCE_FILES = App/Info.plist
ReceptorApp_RESOURCE_DIRS = App/Resources
ReceptorApp_CODESIGN_FLAGS = -SApp/Entitlements.plist
include $(THEOS_MAKE_PATH)/application.mk

TOOL_NAME = receptor-deb-helper
receptor-deb-helper_FILES = Tools/receptor-deb-helper.c
receptor-deb-helper_INSTALL_PATH = /usr/libexec
receptor-deb-helper_CFLAGS = -std=gnu99 -Wall -Wextra
include $(THEOS_MAKE_PATH)/tool.mk

after-stage::
	chmod 4755 "$(THEOS_STAGING_DIR)/usr/libexec/receptor-deb-helper"
