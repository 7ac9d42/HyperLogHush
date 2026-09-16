#!/system/bin/sh

# 按标签管理临时日志等级，并记录本次开机的属性所有权。
# 不要加入安全审计、崩溃、图形告警等标签。
set -f
HUSH_TAGS='
RecentsTaskLoader
MiuiWallpaperSurfaceAnimation
MiuiDecorationDot
MiuiDecorationBottom
MiuiDecorationBase
JavaheapMonitor
SkJpegCodec
JpegXmCodec
MiSensorServiceImpl
libsensor-boledalgo
libsensor-parseRGB
StNfcHal
SkJpegEncoder
PassBlur-VRI[NotificationShade]
AnimInterruptController
backgroundBlur
BrightnessAlgo
DozeAutoBrightnessController[0]
'
HUSH_STATE="$MODDIR/.state"
HUSH_LEDGER="$HUSH_STATE/applied.tags"
HUSH_DEFAULTS="$HUSH_STATE/default.tags"
HUSH_DIAGNOSTIC="$MODDIR/diagnostic_mode"

hush_error()
{
    printf 'HyperLogHush: %s\n' "$*" >&2
}

hush_known_tag()
{
    local candidate
    for candidate in $HUSH_TAGS; do
        [ "$candidate" != "$1" ] || return 0
    done
    return 1
}

hush_supported()
{
    [ "$(getprop ro.product.device)" = pudding ] || return 1
    case "$(getprop ro.mi.os.version.name)" in
        OS*) return 0 ;;
        *) return 1 ;;
    esac
}

hush_boot_id()
{
    # 只用于区分本次开机，避免旧状态误认领下一次开机的外部属性。
    cat /proc/sys/kernel/random/boot_id
}

hush_global_allows_filter()
{
    local level
    level="$(getprop log.tag)" || return 2
    if [ -z "$level" ]; then
        level="$(getprop persist.log.tag)" || return 2
    fi
    case "$level" in
        ''|[Vv]*|[Dd]*|[Ii]*) return 0 ;;
        *) return 1 ;;
    esac
}

hush_owned()
{
    [ -f "$HUSH_LEDGER" ] && grep -Fxq "$1" "$HUSH_LEDGER"
}

hush_atomic_text()
{
    local target value temporary
    target="$1"
    value="$2"
    temporary="$(mktemp "$HUSH_STATE/.write.XXXXXX")" || return 1
    if printf '%s' "$value" > "$temporary" &&
            chmod 0600 "$temporary" && mv -f "$temporary" "$target"; then
        return 0
    fi
    rm -f "$temporary"
    return 1
}

hush_ledger_change()
{
    hush_list_change "$HUSH_LEDGER" "$1" "$2"
}

hush_list_change()
{
    local target operation tag entries line
    target="$1"
    operation="$2"
    tag="$3"
    entries=''
    while IFS= read -r line || [ -n "$line" ]; do
        [ "$line" = "$tag" ] && continue
        entries="$entries$line
"
    done < "$target"
    if [ "$operation" = add ]; then
        entries="$entries$tag
"
    fi
    hush_atomic_text "$target" "$entries"
}

hush_prepare_state()
{
    local boot previous tag state_file
    boot="$(hush_boot_id)" || return 1
    [ -n "$boot" ] || return 1
    previous=''
    [ ! -f "$HUSH_STATE/boot_id" ] || previous="$(cat "$HUSH_STATE/boot_id")"
    if [ "$previous" != "$boot" ]; then
        # 临时属性不会跨完整重启持久化；缺少 boot_id 时也不猜测所有权。
        hush_atomic_text "$HUSH_LEDGER" '' || return 1
        hush_atomic_text "$HUSH_DEFAULTS" '' || return 1
        hush_atomic_text "$HUSH_STATE/boot_id" "$boot" || return 1
    fi
    for state_file in "$HUSH_LEDGER" "$HUSH_DEFAULTS"; do
        [ -f "$state_file" ] || hush_atomic_text "$state_file" '' || return 1
        while IFS= read -r tag || [ -n "$tag" ]; do
            hush_known_tag "$tag" || {
                hush_error '状态文件存在非白名单标签，停止操作。'
                return 1
            }
        done < "$state_file"
    done
}

hush_default_selected()
{
    [ -f "$HUSH_DEFAULTS" ] && grep -Fxq "$1" "$HUSH_DEFAULTS"
}

hush_lock()
{
    umask 077
    mkdir -p "$HUSH_STATE" && chmod 0700 "$HUSH_STATE" || return 1
    # KernelSU BusyBox 提供 flock；进程退出自动解锁，没有陈旧 PID 锁问题。
    exec 9> "$HUSH_STATE/lock" || return 1
    flock -n 9 || {
        hush_error '另一个操作正在运行，本次立即退出。'
        exec 9>&-
        return 1
    }
}

hush_release_tag()
{
    local tag current verified
    tag="$1"
    current="$(getprop "log.tag.$tag")" || return 1
    if [ "$current" = W ]; then
        if ! resetprop -n --delete "log.tag.$tag" >/dev/null 2>&1; then
            hush_error "$tag 恢复失败，保留所有权记录以便重试。"
            return 1
        fi
        verified="$(getprop "log.tag.$tag")" || return 1
        [ -z "$verified" ] || return 1
    fi
    # 其他工具已经改过的值不回写；仅移除本模块的旧所有权。
    hush_ledger_change remove "$tag"
}

hush_apply()
{
    local tag current persistent verified applied skipped failed global_status
    applied=0
    skipped=0
    failed=0
    hush_global_allows_filter
    global_status=$?
    [ "$global_status" -ne 2 ] || {
        hush_error '读取全局日志等级失败，未修改属性。'
        return 1
    }
    # 禁用 glob，标签中的方括号必须原样传给属性服务。
    set -f
    for tag in ${1:-$HUSH_TAGS}; do
        if hush_default_selected "$tag"; then
            if hush_owned "$tag"; then
                hush_release_tag "$tag" || failed=$((failed + 1))
            fi
            skipped=$((skipped + 1))
            continue
        fi
        if ! current="$(getprop "log.tag.$tag")" ||
                ! persistent="$(getprop "persist.log.tag.$tag")"; then
            hush_error "$tag 属性读取失败，未修改该标签。"
            failed=$((failed + 1))
            continue
        fi
        if hush_owned "$tag"; then
            if [ "$current" = W ] && [ -z "$persistent" ] &&
                    [ "$global_status" -eq 0 ]; then
                applied=$((applied + 1))
                continue
            fi
            # 后续出现持久覆盖或更严格的全局等级时，撤销自己的遮蔽。
            if ! hush_release_tag "$tag"; then
                failed=$((failed + 1))
                continue
            fi
            if ! current="$(getprop "log.tag.$tag")"; then
                failed=$((failed + 1))
                continue
            fi
        fi
        if [ -n "$current" ] || [ -n "$persistent" ] ||
                [ "$global_status" -ne 0 ]; then
            skipped=$((skipped + 1))
            continue
        fi
        # 先记账再设置；即使设置过程异常，也不会出现无人负责恢复的属性。
        if ! hush_ledger_change add "$tag"; then
            hush_error "$tag 状态写入失败，未设置该标签。"
            failed=$((failed + 1))
            continue
        fi
        if resetprop -n "log.tag.$tag" W >/dev/null 2>&1 &&
                verified="$(getprop "log.tag.$tag")" && [ "$verified" = W ]; then
            applied=$((applied + 1))
        else
            # 保留记录；下一次诊断/卸载可恢复设置到一半的属性。
            hush_error "$tag 设置或验证失败，保留恢复记录。"
            failed=$((failed + 1))
        fi
    done
    printf '过滤模式：本模块管理 %d 项，尊重外部设置 %d 项，失败 %d 项。\n' \
        "$applied" "$skipped" "$failed"
    [ "$failed" -eq 0 ]
}

hush_clear()
{
    local tags tag current cleared preserved failed
    tags="$(cat "$HUSH_LEDGER")" || return 1
    cleared=0
    preserved=0
    failed=0
    for tag in $tags; do
        current="$(getprop "log.tag.$tag")"
        if hush_release_tag "$tag"; then
            if [ "$current" = W ]; then
                cleared=$((cleared + 1))
            else
                preserved=$((preserved + 1))
            fi
        else
            failed=$((failed + 1))
        fi
    done
    printf '恢复结果：已撤销 %d 项，保留外部变更 %d 项，失败 %d 项。\n' \
        "$cleared" "$preserved" "$failed"
    [ "$failed" -eq 0 ]
}

hush_status()
{
    local tag temporary persistent source boot recorded
    if [ -f "$HUSH_DIAGNOSTIC" ]; then
        printf '模式：诊断（只撤销本模块设置，不保证系统全局开启详细日志）\n'
    else
        printf '模式：过滤\n'
    fi
    printf '全局 log.tag=%s，persist.log.tag=%s\n' \
        "$(getprop log.tag)" "$(getprop persist.log.tag)"
    boot="$(hush_boot_id)"
    recorded=''
    [ ! -f "$HUSH_STATE/boot_id" ] || recorded="$(cat "$HUSH_STATE/boot_id")"
    for tag in $HUSH_TAGS; do
        temporary="$(getprop "log.tag.$tag")"
        persistent="$(getprop "persist.log.tag.$tag")"
        source=继承全局
        [ -z "$persistent" ] || source=外部持久设置
        [ -z "$temporary" ] || source=外部临时设置
        if [ -n "$boot" ] && [ "$boot" = "$recorded" ] && hush_owned "$tag"; then
            if [ "$temporary" = W ]; then source=本模块; else source=待核对恢复记录; fi
        fi
        printf '%-30s 临时=%-5s 持久=%-5s 来源=%s\n' \
            "$tag" "${temporary:--}" "${persistent:--}" "$source"
    done
}

hush_main()
{
    local operation requested result
    operation="${1:-status}"
    requested="$operation"
    case "$operation" in
        status) hush_status; return $? ;;
        json) hush_json; return $? ;;
        warn|default)
            [ "$#" -eq 2 ] && hush_known_tag "$2" || {
                hush_error '逐项操作只接受一个完整白名单标签。'; return 2;
            }
            ;;
        boot|apply|diagnostic|toggle|uninstall) ;;
        *) hush_error '用法：action.sh [status|apply|diagnostic|toggle] 或 [warn|default] 标签'; return 2 ;;
    esac
    [ "$(id -u)" = 0 ] || { hush_error '需要 root 权限。'; return 1; }
    command -v resetprop >/dev/null 2>&1 && command -v flock >/dev/null 2>&1 || {
        hush_error '缺少 KernelSU resetprop/flock，未修改属性。'
        return 1
    }
    if [ "$operation" != uninstall ] && ! hush_supported; then
        hush_error '当前仅支持小米 17 pudding HyperOS。'
        return 1
    fi
    hush_lock || return 1
    if ! hush_prepare_state; then
        hush_error '无法准备或验证恢复状态，未修改属性。'
        exec 9>&-
        return 1
    fi
    case "$operation" in
        boot)
            if [ -f "$HUSH_DIAGNOSTIC" ]; then operation=diagnostic; else operation=apply; fi
            ;;
        toggle)
            if [ -f "$HUSH_DIAGNOSTIC" ]; then operation=apply; else operation=diagnostic; fi
            ;;
    esac
    result=0
    case "$operation" in
        apply)
            if rm -f "$HUSH_DIAGNOSTIC"; then hush_apply || result=1; else result=1; fi
            ;;
        diagnostic)
            # 先保存用户的回退意图，恢复失败时下一次启动仍然进入诊断模式。
            if hush_atomic_text "$HUSH_DIAGNOSTIC" ''; then hush_clear || result=1; else result=1; fi
            ;;
        warn)
            if hush_list_change "$HUSH_DEFAULTS" remove "$2"; then
                hush_apply "$2" || result=1
                # 不把被外部属性阻止的操作报告为成功。
                if ! hush_owned "$2" || [ "$(getprop "log.tag.$2")" != W ]; then
                    hush_error '该项受外部属性或全局等级控制，未接管；请查看当前来源。'
                    result=1
                fi
            else result=1; fi
            ;;
        default)
            # 先保存本次开机的回退意图，删除属性失败时可重试。
            if hush_list_change "$HUSH_DEFAULTS" add "$2"; then
                if hush_owned "$2"; then hush_release_tag "$2" || result=1; fi
            else result=1; fi
            ;;
        uninstall) hush_clear || result=1 ;;
    esac
    exec 9>&-
    if [ "$operation" != uninstall ] && [ "$requested" != boot ] &&
            [ "$requested" != warn ] && [ "$requested" != default ]; then
        hush_status
    fi
    return "$result"
}

# JSON 仅输出固定白名单和等级枚举，不暴露日志正文或任意属性内容。
hush_level()
{
    case "$1" in
        '') printf '' ;;
        [Vv]*) printf V ;; [Dd]*) printf D ;; [Ii]*) printf I ;;
        [Ww]*) printf W ;; [Ee]*) printf E ;; [FfAa]*) printf F ;;
        [Ss]*) printf S ;; *) printf '?' ;;
    esac
}

hush_json()
{
    local boot recorded active diagnostic global persistent_global tag temporary persistent
    local source choice effective comma
    boot="$(hush_boot_id)" || return 1
    recorded=''
    [ ! -f "$HUSH_STATE/boot_id" ] || recorded="$(cat "$HUSH_STATE/boot_id")" || return 1
    active=false
    [ -z "$boot" ] || [ "$boot" != "$recorded" ] || active=true
    diagnostic=false
    [ ! -f "$HUSH_DIAGNOSTIC" ] || diagnostic=true
    global="$(getprop log.tag)" || return 1
    persistent_global="$(getprop persist.log.tag)" || return 1
    printf '{"schema":1,"diagnostic":%s,"rows":[' "$diagnostic"
    comma=''
    set -f
    for tag in $HUSH_TAGS; do
        temporary="$(getprop "log.tag.$tag")" || return 1
        persistent="$(getprop "persist.log.tag.$tag")" || return 1
        source=inherited
        effective="${global:-$persistent_global}"
        [ -z "$persistent" ] || { source=persistent; effective="$persistent"; }
        [ -z "$temporary" ] || { source=external; effective="$temporary"; }
        choice=warn
        if [ "$diagnostic" = true ] || { [ "$active" = true ] && hush_default_selected "$tag"; }; then
            choice=default
        fi
        if [ "$active" = true ] && hush_owned "$tag"; then
            source=pending
            if [ "$temporary" = W ]; then
                source=module
                # 全局诊断模式下，仍允许当前开机临时开启单项。
                hush_default_selected "$tag" || choice=warn
            fi
        fi
        printf '%s{"tag":"%s","choice":"%s","source":"%s","level":"%s"}' \
            "$comma" "$tag" "$choice" "$source" "$(hush_level "$effective")"
        comma=,
    done
    printf ']}\n'
}
