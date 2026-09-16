#!/system/bin/sh

MODDIR=${0%/*}
. "$MODDIR/common.sh" || exit 1
# 启动完成后只执行一次；不轮询、不启动常驻进程。
hush_main boot
