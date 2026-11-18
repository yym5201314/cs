# 来源与第三方声明

## 本工程

DuoDesktop（`com.axs.duodesktop`）由 `SoloRebuildFull` 重建工程改造而来：重新划分了源码边界、替换了命名空间、重写了设置面板与布局计算，并删除了原工程中无实现的占位类与动作条目。

- 本仓库**不包含**原插件 `com.oakstheawesome.solo` 的二进制、dylib 反编译产物或原始资源文件。
- 原插件作者与本工程无关，本工程也不代表其立场或获得其背书。
- 若需在公开源分发，请自行确认与原始作品相关的授权问题；本仓库仅提供代码层面的实现。

## 运行时依赖

插件在运行时通过 `NSClassFromString` / `NSInvocation` / `dlsym` 访问系统私有接口，不静态链接也不打包任何 Apple 私有框架：

- `SpringBoard` 私有类：`SBRootFolderView`、`SBDockView`、`SBHIconManager`、`SBCoverSheetPresentationManager` 等。
- `MediaRemote.framework`：正在播放信息与播放控制。
- `AppSupport.framework`：`RadiosPreferences`（飞行模式）。
- `ReplayKit.framework`：系统录屏。
- `libsubstrate`：通过 `dlsym(RTLD_DEFAULT, "MSHookMessageEx")` 安装钩子，未静态链接。

这些接口随 iOS 版本变化，插件对每次调用都做了类型编码校验与失败兜底。

## 第三方插件

原工程中依赖 Myrtle / SVP / SHELLX / Open / Kayoko / ScreenCore 等第三方插件的动作条目没有可核验的实现，本仓库未保留，也不包含上述项目的任何代码。
