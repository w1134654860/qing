# 构建 iOS 无签名 IPA（TrollStore / 巨魔 安装）

本文档说明如何把本仓库（wenku8_flutter 0.3.7）构建为可供 **TrollStore（巨魔）** 直接安装的
无签名 IPA。

## 为什么不能在本机（Windows）直接构建

iOS 应用必须由 **macOS + Xcode** 编译（`flutter build ios` 只在 macOS 上可用）。
本仓库所在电脑为 Windows，无法本地产出 IPA。以下三种途径任选其一，
最终得到的都是同一个 `wenku8-ios-0.3.7-unsigned.ipa`，巨魔可直接安装。

## 已完成的 iOS 适配改动（本仓库内）

| 文件 | 改动 | 目的 |
| --- | --- | --- |
| `.github/workflows/ios-unsigned.yml` | 新增 | GitHub Actions 一键构建无签名 IPA |
| `ios/Runner/Info.plist` | 新增 `UIBackgroundModes=audio` | 听书后台播放、锁屏控制 |
| `ios/Runner/Info.plist` | 新增 `NSAllowsArbitraryLoads` | 允许用户自定义的 HTTP WebDAV / TTS 端点 |
| `ios/Runner/Info.plist` | 新增 `NSLocalNetworkUsageDescription` | 局域网 WebDAV 隐私弹窗文案 |

部署目标 iOS 13.0，Bundle ID `org.mewx.wenku8Flutter`，应用图标已齐全。

---

## 途径 A：GitHub Actions（推荐，无需 Mac）

1. 在 GitHub 新建一个仓库（Public 或 Private 均可；Private 仓库 macOS 免费额度约 200 分钟/月，够用）。
2. 把本文件夹内容全部上传/推送到该仓库（若用网页上传，直接把 `wenku8-0.3.7-source` 里的内容拖入即可）。
3. 打开仓库 → **Actions** → 左侧 **iOS Unsigned IPA (TrollStore)** → **Run workflow**。
4. 等待约 10–15 分钟（macOS runner 首次会缓存 Flutter 与 CocoaPods）。
5. 构建完成后，点击本次运行 → 底部 **Artifacts** → 下载 `wenku8-ios-unsigned-ipa`。
6. 解压得到 `wenku8-ios-0.3.7-unsigned.ipa`。

> 提示：也可直接 fork 上游仓库 `mikufoxxx/Wenku8_Flutter`，把本仓库的
> `ios-unsigned.yml` 与 `Info.plist` 改动合入后推送，工作流即可随 push 自动触发。

## 途径 B：Codemagic（免费额度）

1. 在 [codemagic.app](https://codemagic.app) 用 GitHub 账号登录，添加本仓库。
2. 新建 workflow：选择 Flutter、macOS 环境，脚本执行：
   ```sh
   flutter pub get
   flutter build ios --release --no-codesign
   ```
3. 把 `build/ios/iphoneos/Runner.app` 打包为 Payload 结构的 IPA：
   ```sh
   mkdir Payload && cp -R build/ios/iphoneos/Runner.app Payload/
   zip -qry wenku8-ios-0.3.7-unsigned.ipa Payload
   ```
4. 在 artifacts 中下载 IPA。

## 途径 C：有 Mac 可用

```sh
cd 本仓库目录
flutter pub get
flutter build ios --release --no-codesign
mkdir Payload && cp -R build/ios/iphoneos/Runner.app Payload/
zip -qry wenku8-ios-0.3.7-unsigned.ipa Payload
```

---

## 用巨魔安装

1. 把 `wenku8-ios-0.3.7-unsigned.ipa` 传到手机（隔空投送 / 网盘下载均可）。
2. 在 **TrollStore** 中打开该 IPA，点 **Install**。
3. 安装完成后桌面出现 **Wenku8 Flutter** 图标，直接使用。

## 注意事项

- 本 IPA **未经 Apple 签名**，只能通过巨魔/侧载安装，不能上架 App Store。
- 项目遵循 GPL-3.0，个人自用构建无问题；请勿公开分发该 IPA 安装包。
- 若手机系统低于 iOS 14（巨魔最低支持版本）则无法安装；iOS 15–16.6.1 全系可用。
