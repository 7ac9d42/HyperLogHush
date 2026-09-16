/* 分组按被过滤信息的诊断价值排序，不代表故障严重程度或降噪收益。 */
window.HUSH_GROUPS = [
  { id: 'high', title: '较高诊断价值', note: '排查 NFC、亮度、传感器与内存时，优先恢复。' },
  { id: 'medium', title: '中等诊断价值', note: '排查图片、动画与任务切换时恢复。' },
  { id: 'low', title: '较低诊断价值', note: '主要是界面效果和装饰细节。' },
];
window.HUSH_RULES = [
  { tag: 'StNfcHal', group: 'high', description: 'NFC 通信、计时与底层收发' },
  { tag: 'DozeAutoBrightnessController[0]', group: 'high', description: '息屏显示的环境光与自动亮度' },
  { tag: 'BrightnessAlgo', group: 'high', description: '屏幕目标亮度与调节算法' },
  { tag: 'MiSensorServiceImpl', group: 'high', description: '小米传感器服务与屏幕角度' },
  { tag: 'libsensor-boledalgo', group: 'high', description: '传感器亮度与色温算法' },
  { tag: 'libsensor-parseRGB', group: 'high', description: 'RGB 传感器数据解析' },
  { tag: 'JavaheapMonitor', group: 'high', description: 'Java 堆内存的周期性监测' },
  { tag: 'SkJpegCodec', group: 'medium', description: 'JPEG 解码、尺寸与增益图信息' },
  { tag: 'JpegXmCodec', group: 'medium', description: '小米 JPEG 解码扩展' },
  { tag: 'SkJpegEncoder', group: 'medium', description: 'JPEG 编码过程与输出参数' },
  { tag: 'AnimInterruptController', group: 'medium', description: '动画中断与过渡状态' },
  { tag: 'RecentsTaskLoader', group: 'medium', description: '最近任务列表的加载' },
  { tag: 'MiuiWallpaperSurfaceAnimation', group: 'low', description: '壁纸表面的动画更新' },
  { tag: 'PassBlur-VRI[NotificationShade]', group: 'low', description: '通知栏模糊区域的同步' },
  { tag: 'backgroundBlur', group: 'low', description: '背景模糊参数的更新' },
  { tag: 'MiuiDecorationBase', group: 'low', description: '界面装饰的基础状态' },
  { tag: 'MiuiDecorationBottom', group: 'low', description: '底部装饰的布局与更新' },
  { tag: 'MiuiDecorationDot', group: 'low', description: '圆点装饰的绘制与更新' },
];
