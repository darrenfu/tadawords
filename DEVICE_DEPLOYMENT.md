<!-- TADA_BILINGUAL_DOC: English is the default reading language. The original source text is preserved for verification. -->
<a id="english-default"></a>

> **Languages / 语言：** **English (default) / 英文（默认）** · [简体中文](#简体中文版)

# Device Deployment

Tada Words has three deliberately separate delivery milestones. A successful Simulator build is useful evidence, but it is not a physical-device release.

## 1. Developer Preview

**When:** the current Read/Write vertical slice builds and launches on both target Simulators.

**Form:** Xcode installs a development-signed `.app` directly onto one connected iPhone or iPad. The device does not receive a standalone download link, and this build is intended only for local testing. Use the **TadaWordsLocalQA** scheme: it installs as **Tada Words QA**, uses bundle ID `com.tadawords.app.localqa`, and cannot contact iCloud Family Sync.

1. Connect the device to the Mac and trust the connection.
2. Run `make generate` after any `project.yml` change.
3. Open `TadaWords.xcodeproj` in Xcode. This is the canonical project generated
   from `project.yml`; do not use numbered copies such as
   `TadaWords 2.xcodeproj` or `TadaWords 3.xcodeproj`.
4. Select the **TadaWordsLocalQA** scheme in the Xcode toolbar.
5. In **Signing & Capabilities**, choose the owner's Personal Team or paid Apple development team.
6. On the device, enable Developer Mode if iOS requests it.
7. Select the physical device as the run destination and press **Run**.

For repeat command-line installs, build the exact committed LocalQA candidate and
use the repository wrapper instead of calling `devicectl install` directly:

```sh
./Scripts/install-localqa-device.sh DEVICE_ID '/path/to/Tada Words QA.app'
```

The wrapper first copies only `Library/Application Support/TadaWords` into a
private temporary directory, compares every saved `schemaVersion` with the
reader policy bundled inside the target app, and removes the temporary copy.
It refuses a downgrade before installation if any target reader is too old or
if the device is locked/unavailable. It never edits or resets device data.

The first direct install can use Xcode-managed personal-team signing for testing on
the owner's devices. TestFlight requires an active paid Apple Developer Program team.
The generated project pins only the normal Debug/Release app and UI tests to
PawGoo LLC Team `7R78Q4HP86`. LocalQA and its device/UI tests intentionally
remain team-flexible; Xcode may remember that local choice, or a command-line
LocalQA build can pass `DEVELOPMENT_TEAM=<your-team-id>` without editing the
committed project.

LocalQA data is stored under its own app identity, separate from a normal Tada Words
Release install. It stays on that device: reinstalling another device does not copy it,
and it cannot be used to test cross-device sync.

The normal PawGoo app uses bundle `app.tadawords.app`. That identity creates a
new sandbox, OS-permission state, and default Keychain group; it cannot read or
replace Personal-Team normal-app data or LocalQA data. Issue #68 may build and
verify the signed PawGoo Development artifact, but must not install it. Issue
#60 owns pre-install inventory and the first explicitly accepted normal-app
installation on the approved iPhone and M4 iPad.

Before that handoff, verify v0.7.12 without installing it:

```sh
./Scripts/verify-pawgoo-development-app.py \
  '/path/to/Tada Words.app' \
  0.7.12 2026072012 "$(git rev-parse HEAD)" \
  --device-udid 'APPROVED_IPHONE_HARDWARE_UDID' \
  --device-udid 'APPROVED_IPAD_HARDWARE_UDID'
```

Use the hardware UDIDs encoded under the profile's `ProvisionedDevices`; do
not pass the CoreDevice UUIDs printed by `devicectl`. Retain the verifier's app
tree SHA-256 with the handoff and recheck it immediately before installation.

Xcode may ask the owner to sign in to their Apple Account or approve a macOS/iOS security prompt. Credentials must be entered by the owner; they are never needed by the source code or stored in this repository.

## 2. Device Alpha

**When:** real speech, handwriting, retry, permission, and local-persistence flows pass on the target child profile and physical devices.

**Form:** the same direct Xcode installation, used for repeated family testing. This milestone validates microphone routes, on-device speech availability, child handwriting recognition, both child-landscape orientations, parent rotation, landscape restoration after leaving Parents, interruptions, and offline recovery.

Device Alpha is not complete merely because recognition works once. Thresholds must be calibrated against real samples, and technical/uncertain recognition results must never be counted as wrong learning evidence.

## 3. V1 Beta

**When:** the complete V1 scope, privacy boundaries, Kid-Fun Visual Pass, device QA, and release checks are complete.

**Form:** an archived Release build uploaded to App Store Connect and distributed through TestFlight. Testers install Apple's TestFlight app and accept an invitation or approved public link.

TestFlight distribution requires an active Apple Developer Program membership and App Store Connect setup. It is the preferred handoff for installing V1 on multiple devices without keeping them tethered to this Mac. Archive the normal **TadaWords** scheme in Release; do not upload the LocalQA app.

Before archiving, confirm the final 1024 x 1024 App Icon, select the paid
distribution team, and run **Product > Archive** with **Any iOS Device (arm64)**
selected. Validate the archive in Organizer before uploading it to App Store
Connect. Increment the build number before every replacement upload.

The current binary declares that it does not use non-exempt encryption. Reassess
that declaration if custom cryptography is added later.

## Privacy and capability checklist

- The current app requests microphone and speech-recognition permission only after
  an explicit action; both usage descriptions are present in `Info.plist`.
- Speech recognition is configured to require on-device recognition. Audio is not
  saved by the app.
- Handwriting recognition uses Vision on device. Camera and photo-library access are
  requested only when a parent chooses that profile-photo action; both usage
  descriptions are present.
- `PrivacyInfo.xcprivacy` declares the app-container file metadata access and
  monotonic timer APIs used by persistence and quest timing. The app declares no
  tracking or collected data in the current implementation.
- The LocalQA entitlement file is intentionally empty and its Info declares
  `CKSharingSupported=false`. The normal Release target has the CloudKit entitlement
  for `iCloud.com.tadawords.app`.
- Release Family Sync is persisted and off by default. Onboarding consent does not
  enable it; a parent must explicitly turn it on in Guardian settings. Turning it
  off stops future sync on that device and, by design, does not erase records already
  uploaded to CloudKit.
- Profile deletion writes a privacy-minimal ledger before local purge and the v0.7.0
  source implements restartable owner erasure of Profile records, assets, share, and
  zone plus stale-device non-resurrection. Production schema deployment and an
  explicitly authorized destructive test-only physical-device proof remain release
  blockers; LocalQA cannot supply that evidence.
- The normal Release target exposes Apple's existing-share management UI only after
  Parent Gate and sensitive-action authorization. Owner removal, participant Leave,
  revocation, and post-dismissal reconciliation must be accepted on signed iPhone and
  iPad builds; LocalQA intentionally omits this CloudKit-only entry point.

Before external TestFlight or App Store review, the owner must also complete the
App Store privacy answers, age rating, export-compliance answers, and a public
privacy-policy URL. Those are App Store Connect records, not source-code files.

## Automated local check

`project.yml` is the source of truth for generated Xcode settings. Run the generator after changing orientations, capabilities, targets, or build settings:

```sh
make generate
```

The global Info envelope includes Portrait and both Landscape orientations on iPhone, plus Portrait Upside Down on iPad. Runtime route policy narrows every child route to both Landscape orientations. `Parents`, Parent Gate, Guardian management, and first-run parent setup use all-but-upside-down on iPhone and all orientations on iPad; leaving them requests a landscape geometry update before returning to child UI.

Run:

```sh
./Scripts/verify-device-readiness.sh
```

The script checks static Release and LocalQA configuration, verifies that no personal
Team ID is committed, builds Release for the iPhone 17 Pro Max and iPad Pro 13-inch
simulators, and builds an isolated LocalQA iPhone app. It inspects the LocalQA product
name, bundle ID, CloudKit-sharing declaration, scheme actions, and empty iCloud
entitlements. It separately reports whether a physical device and signing identity
are available; those two items require the owner's device and Apple Account.

## Current verified local environment

- Xcode 26.6
- iOS 26.5 Simulator runtime
- iPhone 17 Pro Max Simulator
- iPad Pro 13-inch Simulator

These versions describe the current development machine and are not product requirements. The app deployment target remains iOS 18.0.

## Apple references

- [Run an app on simulated or physical devices](https://developer.apple.com/documentation/Xcode/running-your-app-on-simulated-or-physical-devices)
- [Enable Developer Mode](https://developer.apple.com/documentation/Xcode/enabling-developer-mode-on-a-device)
- [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)
<!-- TADA_BILINGUAL_ZH_START -->

---

<a id="简体中文版"></a>

> **翻译说明：** 英文为默认阅读语言；本文同时保留原始语言文本。如中英文内容存在差异，请以原始语言文本为准。

# 设备部署

Tada Words有三个故意分开的交付里程碑。成功的模拟器构建是有用的证据，但它不是物理设备的发布。

## 1. 开发者预览

**何时：**当前的Read/Write垂直切片在两个目标模拟器上构建和启动。

**形式：** Xcode将开发签名的`.app`直接安装到一个连接的iPhone或iPad上。设备不会收到独立的下载链接，此构建仅用于本地测试。使用**TadaWordsLocalQA**方案：它以**Tada Words QA**安装，使用捆绑ID`com.tadawords.app.localqa`，并且无法联系iCloud家庭同步。

1. 将设备连接到 Mac，并信任连接。
2. 在任何`project.yml`更改后运行`make generate`。
3. 打开Xcode中的`TadaWords.xcodeproj`。这是生成的规范项目
来自`project.yml`；不要使用编号副本，如`TadaWords 2.xcodeproj`或`TadaWords 3.xcodeproj`。
4. 在Xcode工具栏中选择**TadaWordsLocalQA**方案。
5. 在“签名与能力”中，选择所有者的个人团队或付费 Apple 开发团队。
6. 在设备上，如果iOS要求，请启用开发者模式。
7. 选择物理设备作为运行目标，然后按**运行**。

对于重复命令行安装，构建确切的已提交的LocalQA候选版本，并使用存储库包装器，而不是直接调用`devicectl install`：

```sh
./Scripts/install-localqa-device.sh DEVICE_ID '/path/to/Tada Words QA.app'
```

包装程序首先只将`Library/Application Support/TadaWords`复制到一个私人的临时目录中，将每个保存的`schemaVersion`与目标应用程序内捆绑的读者策略进行比较，并删除临时副本。如果任何目标读者过时或设备被锁定/不可用，则在安装前拒绝降级。它从不编辑或重置设备数据。

第一个直接安装可以使用Xcode-管理的个人团队签名，在所有者的设备上进行测试。TestFlight需要一个活跃的付费Apple开发者计划团队。生成的项目仅将正常的调试/发布应用程序和UI测试绑定到PawGoo LLC团队`7R78Q4HP86`。LocalQA及其设备/UI测试故意保持团队灵活；Xcode可能会记住本地选择，或者命令行LocalQA构建可以在不编辑已提交的项目的情况下通过`DEVELOPMENT_TEAM=<your-team-id>`。

LocalQA数据以自己的应用程序身份存储，与正常的Tada Words版本安装分开。它留在该设备上：重新安装其他设备不会复制它，也不能用于测试跨设备同步。

正常的PawGoo应用程序使用捆绑包`app.tadawords.app`。该身份创建了一个新的沙盒、操作系统权限状态和默认密钥串组；它无法读取或替换个人团队普通应用程序数据或LocalQA数据。Issue #68可以构建和验证已签名的PawGoo开发工件，但不得安装它。Issue #60拥有预安装库存和在批准的iPhone和M4 iPad上首次明确接受的普通应用程序安装。

在完成交接之前，请在不安装v0.7.12的情况下验证它：

```sh
./Scripts/verify-pawgoo-development-app.py \
  '/path/to/Tada Words.app' \
  0.7.12 2026072012 "$(git rev-parse HEAD)" \
  --device-udid 'APPROVED_IPHONE_HARDWARE_UDID' \
  --device-udid 'APPROVED_IPAD_HARDWARE_UDID'
```

使用配置文件`ProvisionedDevices`下编码的硬件UDID；不要传递`devicectl`打印的CoreDevice UUID。保留验证器的应用程序树SHA-256，并在安装前立即重新检查。

Xcode可能会要求所有者登录他们的Apple Account或批准macOS/iOS安全提示。凭据必须由所有者输入；源代码从未需要这些凭据，也不会存储在该存储库中。

## 2.设备Alpha

**何时：**真实语音、手写、重试、许可和本地持久性流量传递到目标儿童配置文件和物理设备上。

**表格：**相同的直接Xcode安装，用于重复家庭测试。此里程碑验证了麦克风路由、设备上的语音可用性、儿童手写识别、儿童景观方向和家长旋转、离开Parents后景观恢复、中断和离线恢复。

设备Alpha仅仅因为识别一次就完成，并不意味着它已经完整。阈值必须根据真实样本进行校准，技术/不确定的识别结果绝不能被视为错误的学习证据。

## 3. V1 Beta版

**何时：**完整的V1范围、隐私边界、Kid-Fun Visual Pass、设备QA和发布检查完成。

**表格：**一个存档的发布构建上传到App Store Connect并通过TestFlight分发。测试人员安装Apple的TestFlight应用程序并接受邀请或已批准的公共链接。

TestFlight分发需要积极的Apple Developer Program会员资格和App Store Connect设置。这是在多个设备上安装V1而不将其与此Mac保持连接的首选手交方式。在发布中存档正常的**TadaWords**方案；不要上传LocalQA应用程序。

在存档之前，请确认最终的1024 x 1024应用程序图标，选择付费分发团队，并选择**任何iOS设备（arm64）**运行**产品>存档**。在上传到App Store Connect之前，请在Organizer中验证存档。每次替换上传之前，请增加构建编号。

当前的二进制文件声明它不使用非豁免的加密。如果稍后添加自定义密码学，请重新评估该声明。

## 隐私和能力清单

- 当前的应用程序只在以下情况下才会请求麦克风和语音识别权限
明确的动作；两个用法描述都出现在`Info.plist`中。
- 语音识别已配置为需要设备上的识别。音频不是
由应用程序保存。
- 手写识别使用设备上的Vision。摄像头和照片库访问是
只有在家长选择个人资料照片操作时才会被请求；两个使用说明都存在。
- `PrivacyInfo.xcprivacy`声明应用程序容器文件元数据访问和
由持久性和任务计时使用的单调计时器API。该应用程序在当前实现中不声明跟踪或收集的数据。
- LocalQA权利文件故意是空的，其信息声明
`CKSharingSupported=false`。正常的释放目标有CloudKit对`iCloud.com.tadawords.app`的权利。
- 默认情况下，释放家庭同步是持久化的，并且关闭的。入职同意不
启用它；家长必须在Guardian设置中明确打开它。关闭它将停止该设备的未来同步，并且根据设计，不会擦除已上传到CloudKit的记录。
- Profile在本地清除和v0.7.0之前，删除写入一个最小隐私账簿
源代码实现了可重启的所有者擦除Profile记录、资产、股票和区域，以及过期的设备非复活。生产模式部署和明确授权的仅限破坏性测试的物理设备证明仍然是发布障碍；LocalQA无法提供这些证据。
- 在以下情况下，正常发布目标才会显示 Apple 现有的“现有库存”管理 UI。
Parent Gate和敏感操作授权。所有者移除、参与者休假、撤销和解雇后核对必须在签署的iPhone和iPad版本上接受；LocalQA故意省略了仅此CloudKit的入口点。

在进行外部TestFlight或App Store审查之前，所有者还必须填写App Store隐私答案、年龄评分、出口合规性答案和公共隐私政策URL。这些是App Store Connect记录，不是源代码文件。

## 自动本地检查

`project.yml`是生成的Xcode设置的真实来源。更改方向、功能、目标或构建设置后，运行生成器：

```sh
make generate
```

全局 Info 方向范围包括 iPhone 上的竖屏和两个横屏方向，以及 iPad 上额外的倒置竖屏。运行时路由策略会把每个儿童端路由限制为两个横屏方向。`Parents`、Parent Gate、Guardian 管理和首次运行的家长设置在 iPhone 上支持除倒置竖屏以外的方向，在 iPad 上支持全部方向；返回儿童端 UI 前必须更新为横屏几何方向。

Run:

```sh
./Scripts/verify-device-readiness.sh
```

该脚本检查静态发布和LocalQA配置，验证没有提交个人团队ID，为iPhone 17 Pro Max和iPad Pro 13英寸模拟器构建发布，并构建一个隔离的LocalQA iPhone应用程序。它检查LocalQA产品名称、捆绑ID、CloudKit共享声明、方案操作和空iCloud权限。它单独报告是否可用物理设备和签名身份；这两个项目需要所有者的设备和Apple Account。

## 当前已验证的本地环境

- Xcode 26.6
- iOS 26.5 模拟器运行时间
- iPhone 17 Pro Max模拟器
- iPad Pro 13英寸模拟器

这些版本描述了当前的开发机器，不是产品要求。应用程序部署目标仍然是iOS 18.0。

## Apple 参考

- [在模拟设备或物理设备上运行应用程序](https://developer.apple.com/documentation/Xcode/running-your-app-on-simulated-or-physical-devices)
- [启用开发者模式](https://developer.apple.com/documentation/Xcode/enabling-developer-mode-on-a-device)
- [TestFlight概述](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)
