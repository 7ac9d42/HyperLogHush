# HyperLogHush

适用于 HyperOS 的 KernelSU 日志降噪模块，不限制设备型号。主要目标是让 logcat 更容易阅读，同时减少低价值日志进入缓冲区的开销；不承诺续航或性能提升。

## 工作方式

启动完成后运行一次，将 18 个标签的最低记录等级设置为 `WARN`（遇到外部设置则不接管）。仅过滤 `VERBOSE / DEBUG / INFO`，保留 `WARN / ERROR / FATAL`。不运行常驻进程或采样循环，不读取日志正文，不调整日志缓冲区、内核 printk、SELinux、安全审计或崩溃处理。

使用非持久的 `log.tag.<标签>=W`。完整重启后，由系统和模块重新建立属性；不写入 `persist.*`，不替换系统文件。

安装及运行时仅检查 HyperOS，不检查设备型号。不同设备与系统版本使用的日志标签可能不同，实际降噪效果以设备输出为准。

## WebUI 逐项临时控制

从 KernelSU 管理器打开模块 WebUI，每项有「开降噪」和「恢复默认」两个选项，展示英文原名、中文用途、实际属性等级及来源。按诊断价值从高到低分组，组内也由高到低作定性排列：较高 7 项、中等 5 项、较低 6 项。

每项显示设置成功、已恢复默认、受外部设置保护、未完成或结果未知。操作后核对返回值与属性读回；刷新显示当前设置状态。设置成功不代表该设备存在此标签，也不等于已经实测减少日志输出。

- 开降噪：尝试让该标签由模块设置为 WARN，不改变其他标签或全局诊断模式。不接管已有外部属性；受保护而未设置时明确报错，刷新后可查看外部来源。
- 恢复默认：移除该标签属于模块的临时 WARN，并记录本次开机不再自动应用该项。不会把等级强制设为 DEBUG，也不会删除外部临时、持久或全局设置。外部 W 仍可能继续降噪。
- 选项高亮表示本次选择；实际等级和来源显示在旁边。计数只统计当前由本模块设置为 W 的项目，不等于已实测停止输出的项目数。
- 完整重启后逐项选择清空，默认重新应用 18 项；如果全局诊断模式已开启，则继续尊重该模式。在该模式下也能临时开启单项，重启后仍回到诊断模式。
- 操作按钮和 CLI 的 `apply` 尊重本次开机的逐项「恢复默认」选择；`diagnostic` 撤销模块全部属性。二者均不需要常驻服务。
- 首次打开只读；无轮询、无网络请求、无第三方在线资源。只有点击逐项按钮才可能写入属性；固定入口、精确白名单、非阻塞锁、15 秒设备命令超时、20 秒桥响应超时。失败后锁定写操作，必须先成功刷新。

## 尊重外部设置与恢复

- 任一标签已有临时或持久等级时都跳过，包括用户明确设置的 D/V，以及已有的 W/E/S。
- 全局等级已经是 W 或更严格时，不用单标签 W 放宽它；未知全局取值也保守跳过。
- 本模块原来设置了 W，但后来增加了持久单标签覆盖或更严格的全局设置时，下一次应用会撤销自己的临时覆盖。
- 先写入恢复记录，再设置属性；设置失败或验证失败不会丢失记录。
- 每次属性设置和删除都读回验证；失败返回非零，恢复失败的条目可重试。
- 用本次开机 ID 标记所有权，完整重启后不沿用旧账本认领外部属性。
- 只撤销白名单内、本模块记录且当前仍等于 W 的临时属性。外部改成其他值的属性不覆盖。
- 非阻塞 `flock` 防止模块按钮与启动脚本并发修改；进程退出即释放锁。

Android 属性没有可用的写入者身份或原子比较交换接口：如果其他工具在同一开机中把模块的 W 再写成相同 W，无法分辨写入者。请避免让多个模块共同管理同一标签；锁只协调本模块的操作。

诊断模式只撤销本模块自己的过滤，不会清除其他工具或系统设置的 W，也不会强制把全局日志打开到 DEBUG。状态输出会展示每个标签的临时值、持久值与来源，避免把“诊断模式”误读成“全部详细日志已恢复”。

## 操作

KernelSU 的操作按钮在过滤与诊断模式之间切换，同时显示状态。模块已安装后，也可以在具有 root 权限的 Android shell 中使用：

```sh
# 只读查看，不创建状态文件或修改属性。
sh /data/adb/modules/luna_log_filter/action.sh status

# 以下两条会修改模块状态与属于本模块的临时日志属性。
sh /data/adb/modules/luna_log_filter/action.sh diagnostic
sh /data/adb/modules/luna_log_filter/action.sh apply

# 逐项临时控制；包含方括号的标签必须完整引用。
sh /data/adb/modules/luna_log_filter/action.sh default 'DozeAutoBrightnessController[0]'
sh /data/adb/modules/luna_log_filter/action.sh warn 'DozeAutoBrightnessController[0]'
```

手动运行需要能找到 KernelSU 的 `resetprop` 与 BusyBox `flock`；管理器自动提供所需环境。诊断回退部分失败时，诊断模式标记仍保留，下一次运行或启动会重试恢复。

## 许可证与来源

本项目采用 [MIT License](LICENSE)，KernelSU 等外部接口说明见 [NOTICE](NOTICE)。外部工具与代码仍适用其各自许可证。

## 参考

- [KernelSU 模块指南](https://kernelsu.org/guide/module.html)：模块 ID、安装器、启动阶段及 BusyBox 执行环境。
- [Android logcat 文档](https://developer.android.com/tools/logcat)：标签属性与日志优先级过滤。
- [Magisk resetprop 说明](https://topjohnwu.github.io/Magisk/details.html#resetprop)：非持久属性操作与绕过属性触发的行为。
- [KernelSU WebUI 指南](https://kernelsu.org/guide/module-webui.html)及[官方桥接口实现](https://github.com/tiann/KernelSU/blob/main/js/index.js)：目录要求、安装器权限管理及原生 `ksu.exec` 回调参数。
