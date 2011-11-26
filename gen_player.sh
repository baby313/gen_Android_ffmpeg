#!/bin/bash
# Author: Guo Mingyu from Software Institute of PKU

# get ndk path and ffmpeg path
if [ $# -ne 3 ]; then
	echo "Usage: ./gen_player SDK_PATH NDK_PATH FFMPEG_PATH"
	exit 1
fi

sdk_dir=$1
ndk_dir=$2
ffmpeg_dir=$3

# create a player project
echo "creating android_player..."
if [ -d android_player ]; then
	echo "android_player has existed."
else
	$sdk_dir/tools/android create project -n android_player -t android-8 -p android_player -k com.android.player -a Android_Player
	[ -d android_player ] || (echo "Error: create android project failed!" $$ exit 1)
fi

# copy ffmpeg into android project
echo "copying ffmpeg into android_player..."
mkdir -p android_player/jni
[ -d android_player/jni/ffmpeg ] && echo "ffmpeg in android_player has existed." || cp $ffmpeg_dir android_player/jni/ffmpeg -r
cd android_player/jni/ffmpeg || (echo "Error: copy ffmpeg directory failed!" $$ exit 1)

# create conf.sh in ffmpeg directory
PREBUILT=$ndk_dir/toolchains/arm-linux-androideabi-4.4.3/prebuilt/linux-x86
PLATFORM=$ndk_dir/platforms/android-8/arch-arm
output="conf.sh"

[ -f conf.sh ] && echo "old $output has been removed."
echo '#!/bin/bash' > $output
echo "PREBUILT=$PREBUILT" >> $output
echo "PLATFORM=$PLATFORM" >> $output
echo './configure --target-os=linux \
	--arch=arm \
	--enable-version3 \
	--enable-gpl \
	--enable-nonfree \
	--disable-stripping \
	--disable-ffmpeg \
	--disable-ffplay \
	--disable-ffserver \
	--disable-ffprobe \
	--disable-encoders \
	--disable-muxers \
	--disable-devices \
	--disable-protocols \
	--enable-protocol=file \
	--enable-avfilter \
	--disable-avdevice \
	--enable-cross-compile \
	--cc=$PREBUILT/bin/arm-linux-androideabi-gcc \
	--cross-prefix=$PREBUILT/bin/arm-linux-androideabi- \
	--nm=$PREBUILT/bin/arm-linux-androideabi-nm \
	--extra-cflags="-fPIC -DANDROID" \
	--disable-asm \
	--enable-neon \
	--enable-armv5te \
	--extra-ldflags="-Wl,-T,$PREBUILT/arm-linux-androideabi/lib/ldscripts/armelf_linux_eabi.x -Wl,-rpath-link=$PLATFORM/usr/lib -L$PLATFORM/usr/lib -nostdlib $PREBUILT/lib/gcc/arm-linux-androideabi/4.4.3/crtbegin.o $PREBUILT/lib/gcc/arm-linux-androideabi/4.4.3/crtend.o -lc -lm -ldl"' >> $output

# start configure
sudo chmod +x $output
echo "configuring..."
./$output || (echo configure failed && exit 1)

# modify the config.h
echo "modifying the config.h..."
sed -i "s/#define restrict restrict/#define restrict/g" config.h

# remove static functions in libavutil/libm.h
echo "removing static functions in libavutil/libm.h..."
sed -i "/static/,/}/d" libavutil/libm.h

# modify Makefiles
echo "modifying Makefiles..."
sed -i "/include \$(SUBDIR)..\/subdir.mak/d" libavcodec/Makefile
sed -i "/include \$(SUBDIR)..\/config.mak/d" libavcodec/Makefile
sed -i "/include \$(SUBDIR)..\/subdir.mak/d" libavfilter/Makefile
sed -i "/include \$(SUBDIR)..\/config.mak/d" libavfilter/Makefile
sed -i "/include \$(SUBDIR)..\/subdir.mak/d" libavformat/Makefile
sed -i "/include \$(SUBDIR)..\/config.mak/d" libavformat/Makefile
sed -i "/include \$(SUBDIR)..\/subdir.mak/d" libavutil/Makefile
sed -i "/include \$(SUBDIR)..\/config.mak/d" libavutil/Makefile
sed -i "/include \$(SUBDIR)..\/subdir.mak/d" libpostproc/Makefile
sed -i "/include \$(SUBDIR)..\/config.mak/d" libpostproc/Makefile
sed -i "/include \$(SUBDIR)..\/subdir.mak/d" libswscale/Makefile
sed -i "/include \$(SUBDIR)..\/config.mak/d" libswscale/Makefile

# genarate av.mk in ffmpeg
echo "genarating av.mk in ffmpeg..."
echo '# LOCAL_PATH is one of libavutil, libavcodec, libavformat, or libswscale

#include $(LOCAL_PATH)/../config-$(TARGET_ARCH).mak
include $(LOCAL_PATH)/../config.mak

OBJS :=
OBJS-yes :=
MMX-OBJS-yes :=
include $(LOCAL_PATH)/Makefile

# collect objects
OBJS-$(HAVE_MMX) += $(MMX-OBJS-yes)
OBJS += $(OBJS-yes)

FFNAME := lib$(NAME)
FFLIBS := $(foreach,NAME,$(FFLIBS),lib$(NAME))
FFCFLAGS  = -DHAVE_AV_CONFIG_H -Wno-sign-compare -Wno-switch -Wno-pointer-sign
FFCFLAGS += -DTARGET_CONFIG=\"config-$(TARGET_ARCH).h\"

ALL_S_FILES := $(wildcard $(LOCAL_PATH)/$(TARGET_ARCH)/*.S)
ALL_S_FILES := $(addprefix $(TARGET_ARCH)/, $(notdir $(ALL_S_FILES)))

ifneq ($(ALL_S_FILES),)
ALL_S_OBJS := $(patsubst %.S,%.o,$(ALL_S_FILES))
C_OBJS := $(filter-out $(ALL_S_OBJS),$(OBJS))
S_OBJS := $(filter $(ALL_S_OBJS),$(OBJS))
else
C_OBJS := $(OBJS)
S_OBJS :=
endif

C_FILES := $(patsubst %.o,%.c,$(C_OBJS))
S_FILES := $(patsubst %.o,%.S,$(S_OBJS))

FFFILES := $(sort $(S_FILES)) $(sort $(C_FILES))' > av.mk

echo 'include $(all-subdir-makefiles)' > ../Android.mk

echo 'LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
LOCAL_STATIC_LIBRARIES := libavformat libavcodec libavutil libpostproc libswscale
LOCAL_MODULE := ffmpeg
include $(BUILD_SHARED_LIBRARY)
include $(call all-makefiles-under,$(LOCAL_PATH))'> Android.mk

echo 'LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
include $(LOCAL_PATH)/../av.mk
LOCAL_SRC_FILES := $(FFFILES)
LOCAL_C_INCLUDES :=		\
	$(LOCAL_PATH)		\
	$(LOCAL_PATH)/..
LOCAL_CFLAGS += $(FFCFLAGS)
LOCAL_CFLAGS += -include "string.h" -Dipv6mr_interface=ipv6mr_ifindex
LOCAL_LDLIBS := -lz
LOCAL_STATIC_LIBRARIES := $(FFLIBS)
LOCAL_MODULE := $(FFNAME)
include $(BUILD_STATIC_LIBRARY)' > libavformat/Android.mk

echo 'LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
include $(LOCAL_PATH)/../av.mk
LOCAL_SRC_FILES := $(FFFILES)
LOCAL_C_INCLUDES :=		\
	$(LOCAL_PATH)		\
	$(LOCAL_PATH)/..
LOCAL_CFLAGS += $(FFCFLAGS)
LOCAL_LDLIBS := -lz
LOCAL_STATIC_LIBRARIES := $(FFLIBS)
LOCAL_MODULE := $(FFNAME)
include $(BUILD_STATIC_LIBRARY)' > libavcodec/Android.mk

echo 'LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
include $(LOCAL_PATH)/../av.mk
LOCAL_SRC_FILES := $(FFFILES)
LOCAL_C_INCLUDES :=		\
	$(LOCAL_PATH)		\
	$(LOCAL_PATH)/..
LOCAL_CFLAGS += $(FFCFLAGS)
LOCAL_STATIC_LIBRARIES := $(FFLIBS)
LOCAL_MODULE := $(FFNAME)
include $(BUILD_STATIC_LIBRARY)' > libavfilter/Android.mk

echo 'LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
include $(LOCAL_PATH)/../av.mk
LOCAL_SRC_FILES := $(FFFILES)
LOCAL_C_INCLUDES :=		\
	$(LOCAL_PATH)		\
	$(LOCAL_PATH)/..
LOCAL_CFLAGS += $(FFCFLAGS)
LOCAL_STATIC_LIBRARIES := $(FFLIBS)
LOCAL_MODULE := $(FFNAME)
include $(BUILD_STATIC_LIBRARY)' > libavutil/Android.mk

echo 'LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
include $(LOCAL_PATH)/../av.mk
LOCAL_SRC_FILES := $(FFFILES)
LOCAL_C_INCLUDES :=		\
	$(LOCAL_PATH)		\
	$(LOCAL_PATH)/..
LOCAL_CFLAGS += $(FFCFLAGS)
LOCAL_STATIC_LIBRARIES := $(FFLIBS)
LOCAL_MODULE := $(FFNAME)
include $(BUILD_STATIC_LIBRARY)' > libavutil/Android.mk

echo 'LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
include $(LOCAL_PATH)/../av.mk
LOCAL_SRC_FILES := $(FFFILES)
LOCAL_C_INCLUDES :=		\
	$(LOCAL_PATH)		\
	$(LOCAL_PATH)/..
LOCAL_CFLAGS += $(FFCFLAGS)
LOCAL_STATIC_LIBRARIES := $(FFLIBS)
LOCAL_MODULE := $(FFNAME)
include $(BUILD_STATIC_LIBRARY)' > libswscale/Android.mk

# start build!
echo "start ndk-building..."
cd ../..
$ndk_dir/ndk-build
