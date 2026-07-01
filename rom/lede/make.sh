#!/bin/bash

CONFDIR=`dirname $0`
test -n "$CFGS" || CFGS="`cat $CONFDIR/cfg.list`"
. $CONFDIR/buildinfo.conf
test -n "$CONFIG_VERSION_NUMBER" || CONFIG_VERSION_NUMBER="${CONFIG_VERSION_VER}_b`date +%Y%m%d%H%M`"

test -n "$IDXS" || IDXS="0"

set -x
test -f .build_x/env && source .build_x/env
set +x

echo build starting
echo "CFGS=[$CFGS]"
echo "IDXS=[$IDXS]"
echo "CONFIG_VERSION_NUMBER=$CONFIG_VERSION_NUMBER"
mkdir -p .build_x
echo "CONFIG_VERSION_NUMBER=\"$CONFIG_VERSION_NUMBER\"" >.build_x/env
sleep 5

echo modifying luci Makefile
find feeds/luci/ -type f | grep -v .git\* | while read file; do
	sed -i 's/192\.168\.1\./192\.168\.15\./g' "$file"
done

touchlist="feeds/luci/applications/luci-app-sqm/Makefile"

for i in $IDXS; do
	touch ./package/base-files/Makefile

	last_arch=
	for cfg in $CFGS; do
		test -f .build_x/$cfg && continue
		set -x
		cp feeds/x/rom/lede/$cfg .config
		if [ "x$BE12_ONLY" = "x1" ]; then
			sed -i -E \
				'/^CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_.*=y$/ { /DEVICE_tenda_be12-pro=y$/! s/^(CONFIG_[^=]+)=y$/# \1 is not set/; }' \
				.config
			sed -i '/^CONFIG_TARGET_DEVICE_PACKAGES_mediatek_filogic_DEVICE_tenda_be12-pro=/ s/luci-app-openclash/luci-app-homeproxy luci-app-mosdns/' .config
			for package in libruby libyaml ruby ruby-bigdecimal ruby-date ruby-digest ruby-enc ruby-pstore ruby-psych ruby-stringio ruby-yaml unzip; do
				sed -i "/^CONFIG_TARGET_DEVICE_PACKAGES_mediatek_filogic_DEVICE_tenda_be12-pro=/ s/ $package / /g" .config
			done
			be12_packages="$(sed -n 's/^CONFIG_TARGET_DEVICE_PACKAGES_mediatek_filogic_DEVICE_tenda_be12-pro="\([^"]*\)"/\1/p' .config)"
			be12_packages="$be12_packages mosdns v2dat v2ray-geoip v2ray-geosite"
			for package in $be12_packages; do
				sed -i "/^CONFIG_PACKAGE_${package}=/d; /^# CONFIG_PACKAGE_${package} is not set$/d" .config
				echo "CONFIG_PACKAGE_${package}=y" >>.config
			done
			make defconfig
			for package in $(sed -n 's/^CONFIG_PACKAGE_\(.*\)=m$/\1/p' .config); do
				case " $be12_packages " in
					*" $package "*) ;;
					*) sed -i "/^CONFIG_PACKAGE_${package}=m$/s//# CONFIG_PACKAGE_${package} is not set/" .config ;;
				esac
			done
			make defconfig
		fi
		sed -i "s/CONFIG_VERSION_NUMBER=\".*\"/CONFIG_VERSION_NUMBER=\"$CONFIG_VERSION_NUMBER\"/" ./.config
		[ "x$i" != "x0" ] && \
		sed -i "s/CONFIG_VERSION_DIST=\".*\"/CONFIG_VERSION_DIST=\"$CONFIG_VERSION_DIST\"/" ./.config
		sed -i "s/CONFIG_VERSION_CODE=\".*\"/CONFIG_VERSION_CODE=\"$CONFIG_VERSION_CODE\"/" ./.config
		sed -i "s%CONFIG_VERSION_HOME_URL=\".*\"%CONFIG_VERSION_HOME_URL=\"$CONFIG_VERSION_HOME_URL\"%" ./.config
		sed -i "s%CONFIG_VERSION_BUG_URL=\".*\"%CONFIG_VERSION_BUG_URL=\"$CONFIG_VERSION_BUG_URL\"%" ./.config
		sed -i "s%CONFIG_VERSION_SUPPORT_URL=\".*\"%CONFIG_VERSION_SUPPORT_URL=\"$CONFIG_VERSION_SUPPORT_URL\"%" ./.config
		sed -i "s%CONFIG_VERSION_MANUFACTURER_URL=\".*\"%CONFIG_VERSION_MANUFACTURER_URL=\"$CONFIG_VERSION_MANUFACTURER_URL\"%" ./.config
		sleep 2
		new_arch=$(cat .config | grep CONFIG_TARGET_ARCH_PACKAGES | cut -d\" -f2)
		new_subarch=$(cat .config | grep -o  "CONFIG_TARGET_[a-z0-9]*_[a-z0-9]*=y" | sed 's/=y//' | cut -d_ -f3,4)
		test -n "$last_arch" || last_arch=$new_arch
		test -n "$last_subarch" || last_subarch=$new_subarch
		set +x
		[ "x$WORKFLOW" = x1 ] || {
			# skip touch if WORKFLOW == 1
			touch ./package/feeds/x/natflow/Makefile
			touch ./package/feeds/x/natcap/Makefile
			touch ./package/feeds/x/base-config-setting/Makefile
			touch ./package/base-files/files/etc/openwrt_release
			touch ./feeds/packages/libs/libgpg-error/Makefile
			find package -type f -name Makefile -exec touch {} \;
			#touch Makefile contains LINUX_[0-9].*
			find feeds/packages/ package/ feeds/luci/ feeds/routing/ feeds/telephony/ feeds/x/ -type f -name Makefile | while read f; do
				grep -q 'LINUX_[0-9].*' $f && touch $f && echo touch $f
			done
			#touch contains '@lt\|@le\|@gt\|@ge'
			find feeds/packages/ package/ feeds/luci/ feeds/routing/ feeds/telephony/ feeds/x/ -type f -name '*.mk' -o -name Makefile | while read f; do
				grep -q 'autoreconf\|@lt\|@le\|@gt\|@ge\|+.*:' $f && touch $f && echo touch $f
			done
			for f in touchlist; do
				touch $f && echo touch $f
			done
		}
		rm -rf build_dir/target-*/linux-*
		rm -rf build_dir/target-*/u-boot-*
		rm -rf build_dir/toolchain-*
		[ "x$TMPFS" = x1 ] && {
			if [ "$last_arch" != "$new_arch" ]; then
				rm -rf build_dir/target-*
				last_arch=$new_arch
				last_subarch=$new_subarch
			elif [ "$last_subarch" != "$new_subarch" ]; then
				rm -rf build_dir/target-*/*$last_subarch* build_dir/target-*/u-boot-* build_dir/target-*/linux-firmware-* build_dir/target-*/*-sdk-*
				last_subarch=$new_subarch
			fi
		}
		test -n "$1" || exit 255
		$* || {
			rm -rf build_dir/toolchain-*
			make package/utils/util-linux/clean
			make package/libs/wolfssl/clean
			make package/feeds/packages/glib2/clean
			make package/feeds/packages/i2c-tools/clean
			make package/feeds/packages/kmod/clean
			touch ./feeds/packages/libs/libgpg-error/Makefile
			$* || exit 255
		}
		cp .config .build_x/$cfg
	done
done

build_in=$(cd feeds/x/rom/lede/ && cat $CFGS | grep TARGET_DEVICE_.*=y | sed 's/CONFIG_//;s/=y//' | wc -l)
build_out=$(find bin/targets/ | grep -- '\(-squashfs\|-factory\|-sysupgrade\)' | grep -v factory | grep "natcap\|x-wrt" | grep -v root | grep -v kernel | sort | wc -l)
echo in=$build_in out=$build_out
echo
