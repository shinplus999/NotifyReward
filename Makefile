export THEOS = /home/shinaov/theos
ARCHS := arm64 arm64e
TARGET := iphone:clang:latest:14.0

THEOS_PACKAGE_SCHEME = roothide

INSTALL_TARGET_PROCESSES := SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := NotifyReward

$(TWEAK_NAME)_FILES += Tweak.xm
$(TWEAK_NAME)_CFLAGS += -fobjc-arc -Wno-unused-function -Wno-deprecated-declarations -Wno-incomplete-implementation

$(TWEAK_NAME)_FRAMEWORKS += Foundation UIKit CFNetwork Security
$(TWEAK_NAME)_PRIVATE_FRAMEWORKS += SpringBoardServices UserNotifications

include $(THEOS_MAKE_PATH)/tweak.mk