# DuoDesktop

DuoDesktop 是 iOS 越狱插件（SpringBoard 注入），提供**桌面顶部轮播卡片**与**左缘快捷侧栏**：时钟、媒体、日历、快捷动作四个页面，配合一套可增删排序的快捷动作系统。

工程由 `SoloRebuildFull` 重建项目改造而来，按 Axs 插件约定重新组织：所有自定义类、函数、selector、偏好域均带 `DuoDesktop` 命名空间，打包方案固定为 **Rootless**。

| 项目 | 值 |
| --- | --- |
| 显示名 | DuoDesktop |
| 包名 / 偏好域 | `com.axs.duodesktop` |
| 类前缀 | `AxsDuoDesktop` |
| 函数 / selector 前缀 | `axs_duodesktop_` |
| 配置变更通知 | `com.axs.duodesktop.preferences-changed` |
| 注入进程 | `com.apple.springboard` |
| 编译 SDK / 最低系统 | iPhoneOS 16.5 / iOS 15.0（Rootless） |
| 包架构 | `iphoneos-arm64`（Rootless 设备 dpkg 架构） |

## 功能

- **顶部轮播**：在桌面图标区上方插入毛玻璃卡片，左右滑动切换；右侧箭头展开（226pt → 最长 370pt），图标区会自动下移，卡片隐藏或插件关闭时恢复原生布局。
- **时钟页**：数字表盘或指针表盘（秒针可关），时间居中可切换；点时间进时钟，点日期进日历。
- **媒体页**：通过 MediaRemote 读取正在播放信息（封面、标题、歌手、进度），支持播放/暂停、上一首、下一首、拖动进度；点封面进音乐 App。
- **日历页**：读取今天与明天的日程（EventKit），日程行可跳到对应时间；权限受限时给出说明与设置入口。
- **快捷动作页**：最多 8（展开后 9）个动作瓦片，开关状态高亮显示，长按进入编辑器。
- **快捷侧栏**：屏幕左缘把手，轻点展开 6 个纵向动作，长按编辑。
- **动作编辑器**：添加系统工具 / 已安装应用 / URL / 快捷指令，支持改名、启用开关、拖动排序、删除，修改即时写入配置。
- **动作目录**：38 个内置系统工具（回桌面、多任务、控制中心、通知中心、锁屏、截图/复制/编辑、录屏、旋转锁、手电筒、Wi-Fi、蓝牙、飞行模式、低电量、静音、深色模式、亮度/音量、设置深链、Siri、Spotlight、资源库、摇一摇、语音控制、实时语音、智能反色、附近设备、iPad Dock/快速备忘录）。

## 目录结构

```
.
├── Makefile                     # 主工程，Sources/*.m 与 Hooks/*.xm 自动收集
├── AxsDuoDesktopBuild.mk        # 共享 ARCHS / SDK / 部署版本（唯一 TARGET 定义）
├── build.sh                     # 本地构建入口，默认 rootless
├── control                      # Debian 包信息（CI 只改写 Version）
├── AxsDuoDesktop.plist          # 注入过滤器：仅 com.apple.springboard
├── tweak.json                   # 工程元信息（doctor 读取）
├── Hooks/
│   └── AxsDuoDesktopMain.xm     # %ctor 入口：装钩子、刷新轮播与侧栏
├── Headers/
│   └── AxsDuoDesktopPrivate.h   # 已核验的私有 selector 清单（注释形式）
├── Sources/
│   ├── AxsDuoDesktopPaths.h           # Rootless / Roothide 路径宏
│   ├── AxsDuoDesktopPreferences.h     # 配置读取与唯一写入函数
│   ├── AxsDuoDesktopConfig.h/.m       # 配置快照与变更广播
│   ├── AxsDuoDesktopRuntime.h/.m      # 类型校验钩子、窗口枚举、日志、dlopen 缓存
│   ├── AxsDuoDesktopActions.h/.m      # 动作目录、记录、执行、应用与图标
│   ├── AxsDuoDesktopActionEditor.h/.m # 动作编辑器与选择器
│   ├── AxsDuoDesktopTile.h/.m         # 动作瓦片
│   ├── AxsDuoDesktopHome.h/.m         # 轮播卡片、时钟/媒体/日历/快捷页
│   └── AxsDuoDesktopRail.h/.m         # 左缘侧栏
├── AxsDuoDesktopPrefs/          # 设置面板（PreferenceBundle）
│   ├── Makefile
│   ├── AxsDuoDesktopRootListController.h/.m
│   └── Resources/AxsDuoDesktopRoot.plist
├── layout/Library/PreferenceLoader/Preferences/AxsDuoDesktopPrefs.plist
└── .github/workflows/build.yml  # macOS 构建、上传产物、创建 Release
```

## 构建

本地（Rootless，需已配置 Theos 与 iPhoneOS 16.5 SDK）：

```sh
export THEOS=/opt/theos
sh build.sh rootless
```

产物位于 `packages/`，安装前可核对：

```sh
dpkg-deb -I packages/com.axs.duodesktop_*.deb
dpkg-deb -c packages/com.axs.duodesktop_*.deb
```

`build.sh` 每次先 `make clean`，失败即停止，不会安装 deb 或注销设备。

### CI

`.github/workflows/build.yml` 沿用个人编译模板：

- 触发：推送到 `main` / `master`，或手动 `workflow_dispatch`
- Runner：`macos-15` + Xcode `16.2`
- Theos：`roothide/theos`；SDK：`iPhoneOS16.5`
- 矩阵：**仅 Rootless**（rootful / roothide 保留注释，需要时取消对应行）
- 版本：CI 统一写入 `5.2.0-${{ github.run_number }}`，Release 标题为 `DuoDesktop v<version>`
- 权限：`contents: write`，用于创建 Release

## 安装

1. 安装 deb（Sileo / Zebra / `dpkg -i`），依赖 `mobilesubstrate` 与 `preferenceloader`。
2. 注销或重启 SpringBoard。
3. 打开「设置 → DuoDesktop」，先打开**启用插件**（默认关闭，避免装完立刻改桌面）。
4. 需要重载时：重新开关任一设置项即可，插件通过 Darwin 通知即时刷新，无需注销。

## 已知限制

- **日历页**：iOS 只向声明了用途描述的应用授予日历权限，SpringBoard 没有该声明，因此插件不会在进程内弹权限框（避免崩溃）。已授权环境下可正常读取；未授权时页面显示说明并提供设置入口。
- **媒体页**：依赖私有框架 MediaRemote，接口缺失时降级为“系统媒体接口不可用”，不崩溃。
- **已移除的第三方动作**：原项目的 Myrtle / SVP / SHELLX / Open / Kayoko / StayLog / ScreenCore 等条目只有占位返回，没有可核验的实现，本次未保留；需要时按同一记录结构（`type/value/title/id/enabled`）另行适配。
- **状态不落盘**：当前页码、展开状态仅本次会话有效；配置文件只由设置面板与动作编辑器写入。

## 验证范围

- 全部 `Sources/*.m`、设置面板 `.m` 与 Logos 预处理后的 `.xm` 已用 iPhoneOS 16.5 SDK 做 `clang -fsyntax-only -target arm64-apple-ios15.0` 检查，无错误、无警告。
- `scripts/doctor.py` 静态检查通过（文件名/类/函数/selector 命名空间、plist 身份、PreferenceLoader 入口、依赖声明）。
- 未在真机安装验证；iOS 版本差异（尤其是私有 selector 与 MediaRemote）需以实机表现为准。
