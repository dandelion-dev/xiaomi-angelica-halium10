#!/bin/bash
set -ex

TMPDOWN=$(realpath $1)
KERNEL_OBJ=$(realpath $2)
RAMDISK=$(realpath $3)
OUT=$(realpath $4)

HERE=$(pwd)
source "${HERE}/deviceinfo"

case "$deviceinfo_arch" in
    aarch64*) ARCH="arm64" ;;
    arm*) ARCH="arm" ;;
    x86_64) ARCH="x86_64" ;;
    x86) ARCH="x86" ;;
esac

[ -f "$HERE/ramdisk-recovery.img" ] && RECOVERY_RAMDISK="$HERE/ramdisk-recovery.img"
[ -f "$HERE/ramdisk-overlay/ramdisk-recovery.img" ] && RECOVERY_RAMDISK="$HERE/ramdisk-overlay/ramdisk-recovery.img"

if [ -d "$HERE/ramdisk-recovery-overlay" ] && [ -e "$RECOVERY_RAMDISK" ]; then
    mkdir -p "$HERE/ramdisk-recovery"

    cd "$HERE/ramdisk-recovery"
    gzip -dc "$RECOVERY_RAMDISK" | cpio -i
    cp -r "$HERE/ramdisk-recovery-overlay"/* "$HERE/ramdisk-recovery"

    find . | cpio -o -H newc | gzip > "$RECOVERY_RAMDISK"
fi

if [ -d "$HERE/ramdisk-overlay" ]; then
    cp "$RAMDISK" "${RAMDISK}-merged"
    RAMDISK="${RAMDISK}-merged"
    cd "$HERE/ramdisk-overlay"
    find . | cpio -o -H newc | gzip >> "$RAMDISK"
fi

if [ "$deviceinfo_bootimg_header_version" -eq 2 ]; then
    mkbootimg --kernel "$KERNEL_OBJ/arch/$ARCH/boot/Image.gz-dtb" --ramdisk "$RAMDISK" --dtb "$HERE/$deviceinfo_bootimg_prebuilt_dtb" --base $deviceinfo_flash_offset_base --kernel_offset $deviceinfo_flash_offset_kernel --ramdisk_offset $deviceinfo_flash_offset_ramdisk --second_offset $deviceinfo_flash_offset_second --tags_offset $deviceinfo_flash_offset_tags --dtb_offset $deviceinfo_flash_offset_dtb --pagesize $deviceinfo_flash_pagesize --cmdline "$deviceinfo_kernel_cmdline" -o "$OUT" --header_version $deviceinfo_bootimg_header_version --os_version $deviceinfo_bootimg_os_version --os_patch_level $deviceinfo_bootimg_os_patch_level
else
    mkbootimg --kernel "$KERNEL_OBJ/arch/$ARCH/boot/Image.gz-dtb" --ramdisk "$RAMDISK" --base $deviceinfo_flash_offset_base --kernel_offset $deviceinfo_flash_offset_kernel --ramdisk_offset $deviceinfo_flash_offset_ramdisk --second_offset $deviceinfo_flash_offset_second --tags_offset $deviceinfo_flash_offset_tags --pagesize $deviceinfo_flash_pagesize --cmdline "$deviceinfo_kernel_cmdline" -o "$OUT"
fi

if [ -n "$deviceinfo_bootimg_append_vbmeta" ] && $deviceinfo_bootimg_append_vbmeta; then
    python2 "$TMPDOWN/avb/avbtool" append_vbmeta_image --image "$OUT" --partition_size "$deviceinfo_bootimg_partition_size" --vbmeta_image "$TMPDOWN/vbmeta.img"
fi

if [ -n "$deviceinfo_bootimg_prebuilt_dtb" ]; then
    DTB="$HERE/$deviceinfo_bootimg_prebuilt_dtb"
elif [ -n "$deviceinfo_dtb" ]; then
    DTB="$KERNEL_OBJ/../$deviceinfo_codename.dtb"
    PREFIX=$KERNEL_OBJ/arch/$ARCH/boot/dts/
    DTBS="$PREFIX${deviceinfo_dtb// / $PREFIX}"
    cat $DTBS > $DTB
fi

if [ -n "$deviceinfo_prebuilt_dtbo" ]; then
    DTBO="$HERE/$deviceinfo_prebuilt_dtbo"
elif [ -n "$deviceinfo_dtbo" ]; then
    DTBO="$(dirname "$OUT")/dtbo.img"
fi

if [ -n "$deviceinfo_has_recovery_partition" ] && $deviceinfo_has_recovery_partition; then
    RECOVERY="$(dirname "$OUT")/recovery.img"
    RECOVERY_RAMDISK="$HERE/ramdisk-recovery.img"
    EXTRA_ARGS=""

if [ -n "$deviceinfo_recovery_partition_size" ]; then
        python2 "$TMPDOWN/avb/avbtool" add_hash_footer --image "$RECOVERY" --partition_name recovery --partition_size $deviceinfo_recovery_partition_size
    fi


    if [ "$deviceinfo_bootimg_header_version" -eq 2 ]; then
        EXTRA_ARGS+=" --header_version $deviceinfo_bootimg_header_version --dtb $DTB --dtb_offset $deviceinfo_flash_offset_dtb"
    fi

    if [ -n "$DTBO" ]; then
        EXTRA_ARGS+=" --recovery_dtbo $DTBO"
    fi

    mkbootimg --kernel "$KERNEL" --ramdisk "$RECOVERY_RAMDISK" --base $deviceinfo_flash_offset_base --kernel_offset $deviceinfo_flash_offset_kernel --ramdisk_offset $deviceinfo_flash_offset_ramdisk --second_offset $deviceinfo_flash_offset_second --tags_offset $deviceinfo_flash_offset_tags --pagesize $deviceinfo_flash_pagesize --cmdline "$deviceinfo_kernel_cmdline" -o "$RECOVERY" --os_version $deviceinfo_bootimg_os_version --os_patch_level $deviceinfo_bootimg_os_patch_level $EXTRA_ARGS
fi
