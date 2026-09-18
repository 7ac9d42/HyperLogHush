#!/system/bin/sh

# 此脚本由 KernelSU 安装器加载；安装阶段只准备文件，不改变运行中的属性。
[ "$KSU" = true ] || abort 'HyperLogHush 当前只支持 KernelSU 管理器安装。'
case "$(getprop ro.mi.os.version.name)" in
    OS*) ;;
    *) abort '当前仅支持 HyperOS。' ;;
esac

HUSH_OLD_MODULE=/data/adb/modules/luna_log_filter
# 升级保留用户选择的诊断模式，不迁移只对旧开机有效的属性所有权。
if [ -f "$HUSH_OLD_MODULE/diagnostic_mode" ]; then
    : > "$MODPATH/diagnostic_mode" || abort '无法保留诊断模式。'
    set_perm "$MODPATH/diagnostic_mode" 0 0 0600
fi
for HUSH_SCRIPT in action.sh control.sh boot-completed.sh uninstall.sh; do
    set_perm "$MODPATH/$HUSH_SCRIPT" 0 0 0755
done
set_perm "$MODPATH/common.sh" 0 0 0644
ui_print 'HyperLogHush 2.1.2：18 个标签，默认过滤 WARN 以下日志。'
ui_print 'WebUI 支持逐项临时控制；重启后恢复默认策略。'
ui_print '安装或升级后请重启；安装过程不会即时改变日志属性。'
ui_print '操作按钮切换过滤/诊断模式；已有外部属性不会被覆盖或删除。'
