#!/system/bin/sh

# WebUI 专用窄接口；绝不解释任意 shell 命令或加载可编辑配置。
MODDIR=${0%/*}
. "$MODDIR/common.sh" || exit 1
set -f
case "$1:$#" in
    status:1) hush_main json ;;
    warn:2|default:2)
        hush_main "$1" "$2" >&2
        HUSH_RESULT=$?
        hush_main json || exit 1
        exit "$HUSH_RESULT"
        ;;
    *) hush_error '仅支持 status 或 warn/default 加白名单标签。'; exit 2 ;;
esac
