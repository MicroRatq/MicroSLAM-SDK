/*
 * SPDX-License-Identifier:     GPL-2.0+
 *
 *
 * Copyright (c) 2021 Rockchip Electronics Co., Ltd
 */

#ifndef __CONFIG_MICROSLAM_H__
#define __CONFIG_MICROSLAM_H__

#include <configs/rk3588_common.h>

/* Remove or override few declarations from rk3588-common.h */
#undef CONFIG_BOOTCOMMAND
#undef RKIMG_DET_BOOTDEV
#undef RKIMG_BOOTCOMMAND

#define CONFIG_SYS_MMC_ENV_DEV		0
#define CONFIG_SYS_MMC_MAX_BLK_COUNT	32768

#ifndef CONFIG_SPL_BUILD

#define ROCKCHIP_DEVICE_SETTINGS \
	"stdout=serial,vidconsole\0" \
	"stderr=serial,vidconsole\0"

#define RKIMG_DET_BOOTDEV \
	"rkimg_bootdev=" \
	"if mmc dev 1 && rkimgtest mmc 1; then " \
		"setenv devtype mmc; setenv devnum 1; echo Boot from SDcard;" \
	"elif mmc dev 0; then " \
		"setenv devtype mmc; setenv devnum 0;" \
	"elif rksfc dev 1; then " \
		"setenv devtype spinor; setenv devnum 1;" \
	"fi; \0"

#define RKIMG_BOOTCOMMAND \
	"boot_fit;" \
	"bootrkp;" \
	"run distro_bootcmd;"

#define CONFIG_BOOTCOMMAND		RKIMG_BOOTCOMMAND

#endif

#endif /* __CONFIG_NANOPI6_H__ */
