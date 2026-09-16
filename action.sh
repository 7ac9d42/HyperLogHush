#!/system/bin/sh

MODDIR=${0%/*}
. "$MODDIR/common.sh" || exit 1
# 管理器按钮默认切换模式；命令行可显式查询、应用或回退。
[ "$#" -ne 0 ] || set -- toggle
hush_main "$@"
