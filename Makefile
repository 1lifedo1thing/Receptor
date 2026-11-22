ARCHS = armv7
ifeq ($(RECEPTOR_LEGACY32),1)
ifneq ($(shell sed -n '1p' control),Package: com.receptor.downloadmanager.ios32)
$(error Use RECEPTOR_LEGACY32=1 scripts/build-wsl.sh so the 3.2 control, app metadata and daemon-free layout are staged together)
endif
TARGET = iphone:clang:5.0:3.2
RC_TLS_LIBDIR = $(THEOS_PROJECT_DIR)/vendor/tls32/lib
ADDITIONAL_CFLAGS += -DRC_LEGACY32=1 -include $(THEOS_PROJECT_DIR)/RCCompatibility32.h
else
TARGET = iphone:clang:5.0:4.0
RC_TLS_LIBDIR = $(THEOS_PROJECT_DIR)/vendor/tls/lib
endif
INSTALL_TARGET_PROCESSES = MobileSafari ReceptorApp

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Receptor
Receptor_FILES = Tweak.x ReceptorPolicyProxy.m RCWKNavigationProxy.m RCSystemContent.c ReceptorUI.m ReceptorPaths.m DownloadManager.m RCCurlTransfer.m
Receptor_FRAMEWORKS = UIKit Foundation QuickLook MobileCoreServices
ifeq ($(RECEPTOR_LEGACY32),1)
Receptor_FRAMEWORKS = UIKit Foundation MobileCoreServices
Receptor_FILES += RCCompatibility32.m
endif
# Modern Theos stubs point at the newer CydiaSubstrate.framework location.
# Link the legacy install name used by Substrate on iOS 4 through 6.
Receptor_LIBRARIES = LegacySubstrate curl mbedtls mbedx509 mbedcrypto
Receptor_LDFLAGS = -L$(THEOS_PROJECT_DIR)/lib -L$(RC_TLS_LIBDIR)
Receptor_CFLAGS = -DRC_UI_COMPAT=1 -fno-objc-arc -fblocks -Wall -Wextra -I$(THEOS_PROJECT_DIR)/vendor/tls/include

include $(THEOS_MAKE_PATH)/tweak.mk

APPLICATION_NAME = ReceptorApp
ReceptorApp_FILES = App/main.m App/RCAppDelegate.m ReceptorUI.m ReceptorPaths.m DownloadManager.m RCCurlTransfer.m FileBrowserViewController.m RCFileArtwork.m RCFileSharing.m RCIPAInstaller.m RCIPAArchive.c RCDEBInstaller.m RCRespring.m RCBackgroundViewController.m RCRemoteCrypto.m RCPackageManager.m RCPackagesViewController.m RCCompanionClient.m RCCompanionViewController.m RCSendFileViewController.m RCFilesystemViewController.m RCPairingCrypto.c
ReceptorApp_FRAMEWORKS = UIKit Foundation QuickLook MobileCoreServices Security ImageIO CoreGraphics AssetsLibrary
ifeq ($(RECEPTOR_LEGACY32),1)
ReceptorApp_FILES := $(filter-out RCBackgroundViewController.m,$(ReceptorApp_FILES)) RCCompatibility32.m
ReceptorApp_FRAMEWORKS = UIKit Foundation MobileCoreServices Security CoreGraphics
endif
ReceptorApp_LIBRARIES = curl mbedtls mbedx509 mbedcrypto z
ReceptorApp_LDFLAGS = -L$(RC_TLS_LIBDIR)
ReceptorApp_CFLAGS = -DRC_UI_COMPAT=1 -DMBEDTLS_PLATFORM_MS_TIME_ALT -DMBEDTLS_THREADING_C -DMBEDTLS_THREADING_PTHREAD -fno-objc-arc -fblocks -Wall -Wextra -I$(THEOS_PROJECT_DIR)/vendor/tls/include
ReceptorApp_BUNDLE_NAME = Receptor
ReceptorApp_RESOURCE_FILES = App/Info.plist
ReceptorApp_RESOURCE_DIRS = App/Resources
ReceptorApp_CODESIGN_FLAGS = -SApp/Entitlements.plist
include $(THEOS_MAKE_PATH)/application.mk

TOOL_NAME = receptor-deb-helper receptor-package-helper receptor-file-helper receptor-remote-agent
ifeq ($(RECEPTOR_LEGACY32),1)
TOOL_NAME = receptor-deb-helper receptor-package-helper
endif
receptor-deb-helper_FILES = Tools/receptor-deb-helper.c
receptor-deb-helper_INSTALL_PATH = /usr/libexec
receptor-deb-helper_CFLAGS = -std=gnu99 -Wall -Wextra
receptor-package-helper_FILES = Tools/receptor-package-helper.m RCRemoteCrypto.m RCRemoteSupport.m
receptor-package-helper_INSTALL_PATH = /usr/libexec
receptor-package-helper_FRAMEWORKS = Foundation CoreFoundation
receptor-package-helper_LIBRARIES = mbedtls mbedx509 mbedcrypto
receptor-package-helper_LDFLAGS = -L$(RC_TLS_LIBDIR)
ifeq ($(RECEPTOR_LEGACY32),1)
receptor-package-helper_FILES += RCCompatibility32.m
endif
receptor-package-helper_CFLAGS = -fno-objc-arc -Wall -Wextra -Wno-unused-function -I$(THEOS_PROJECT_DIR)/vendor/tls/include -DMBEDTLS_PLATFORM_MS_TIME_ALT -DMBEDTLS_THREADING_C -DMBEDTLS_THREADING_PTHREAD
receptor-file-helper_FILES = Tools/receptor-file-helper.m RCRemoteCrypto.m
receptor-file-helper_INSTALL_PATH = /usr/libexec
receptor-file-helper_FRAMEWORKS = Foundation
receptor-file-helper_LIBRARIES = mbedtls mbedx509 mbedcrypto
receptor-file-helper_LDFLAGS = -L$(THEOS_PROJECT_DIR)/vendor/tls/lib
receptor-file-helper_CFLAGS = -fno-objc-arc -Wall -Wextra -I$(THEOS_PROJECT_DIR)/vendor/tls/include -DMBEDTLS_PLATFORM_MS_TIME_ALT -DMBEDTLS_THREADING_C -DMBEDTLS_THREADING_PTHREAD
receptor-remote-agent_FILES = Tools/receptor-remote-agent.m RCRemoteCrypto.m RCRemoteSupport.m
receptor-remote-agent_INSTALL_PATH = /usr/libexec
receptor-remote-agent_FRAMEWORKS = Foundation CoreFoundation
receptor-remote-agent_LIBRARIES = curl mbedtls mbedx509 mbedcrypto
receptor-remote-agent_LDFLAGS = -L$(THEOS_PROJECT_DIR)/vendor/tls/lib
receptor-remote-agent_CFLAGS = -fno-objc-arc -Wall -Wextra -I$(THEOS_PROJECT_DIR)/vendor/tls/include -DMBEDTLS_PLATFORM_MS_TIME_ALT -DMBEDTLS_THREADING_C -DMBEDTLS_THREADING_PTHREAD
include $(THEOS_MAKE_PATH)/tool.mk

after-stage::
	chmod 4755 "$(THEOS_STAGING_DIR)/usr/libexec/receptor-deb-helper"
	chmod 4755 "$(THEOS_STAGING_DIR)/usr/libexec/receptor-package-helper"
ifneq ($(RECEPTOR_LEGACY32),1)
	chmod 0755 "$(THEOS_STAGING_DIR)/usr/libexec/receptor-file-helper" "$(THEOS_STAGING_DIR)/usr/libexec/receptor-remote-agent"
	chmod 0644 "$(THEOS_STAGING_DIR)/Library/LaunchDaemons/com.receptor.remote.plist"
endif
