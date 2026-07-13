# Tada Words 儿童声纹 Device Alpha 结论

日期：2026-07-12

## 结论

目前可以安全交付“设备端 Alpha 基础”，但**不能把儿童声纹标记为生产完成，也不能把 speaker mismatch 接成孩子答错**。

原因不是 iOS 跑不动模型，而是公开方案缺少针对 4 岁儿童、家庭噪声和单个 sight word 短语音的可信验证。现阶段正确产品语义是：声纹只提供一个非阻塞 confidence signal；不可用或疑似不匹配都只能触发技术重试或完全忽略。

## Apple 能力边界

- Apple [Speech framework](https://developer.apple.com/documentation/speech/) 负责语音转文字，不提供说话人身份验证。`supportsOnDeviceRecognition` 只表示 ASR 能否离线运行。
- `AVAudioEngine` 的 [`setVoiceProcessingEnabled`](https://developer.apple.com/documentation/avfaudio/avaudioionode/setvoiceprocessingenabled%28_%3A%29) 和 [`voiceChat`](https://developer.apple.com/documentation/avfaudio/avaudiosession/mode-swift.struct/voicechat) 能提供回声消除、自动增益等语音处理，但不能保证“只留下孩子的声音”。
- [Core ML](https://developer.apple.com/documentation/coreml) 可以完全本地推理；因此不需要服务器数据库或上传录音。
- 最终 embedding 适合存入 Keychain，并使用 [`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly)，从而不迁移到新设备、不参与 iCloud Keychain 同步。
- Apple 要求麦克风采集必须有明确同意和可见/可听提示；Kids Category 还要求谨慎处理儿童数据，见 [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)。

## 候选方案评估

| 方案 | License / 大小 | iOS 本地推理 | 4 岁儿童适用性 | 结论 |
|---|---|---|---|---|
| Apple Speech + Voice Processing | 系统框架，无额外模型 | 是 | 没有 speaker verification | 保留做 ASR 和降噪，不能声称声纹 |
| [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) + [3D-Speaker CAM++ 中英模型](https://modelscope.cn/models/iic/speech_campplus_sv_zh_en_16k-common_advanced) | Apache-2.0；模型 28,281,164 bytes；官方 iOS no-TTS 包 41,692,409 bytes | 官方支持 iOS arm64、Swift/C API、CPU/Core ML provider | 成人/通用语料，没有 4 岁验证 | **Device Alpha 首选**，不进生产判分 |
| [WeSpeaker](https://github.com/wenet-e2e/wespeaker) | Apache-2.0；ONNX 约 26–114 MB | 可经 sherpa-onnx 部署 | 主要 VoxCeleb/CNCeleb 成人数据 | 可作对照模型，不优先集成 |
| [SpeechBrain ECAPA-TDNN](https://github.com/speechbrain/speechbrain) | Apache-2.0；[预训练包约 89.1 MB](https://huggingface.co/speechbrain/spkrec-ecapa-voxceleb/tree/main) | PyTorch 方案，无一等原生 iOS 包 | VoxCeleb 成人数据 | 不选 |
| [NVIDIA TitaNet-Large](https://huggingface.co/nvidia/speakerverification_en_titanet_large) | CC-BY-4.0；23M 参数 | 可自行转换或用 ONNX | 模型卡明确提示跨域需微调，训练集以成人语音为主 | 不选首版 |
| `Otosaku/NeMoSpeaker-iOS` | README 称 MIT、7/14/27 MB | Core ML Swift API | 无儿童验证 | 不采用：仓库没有 LICENSE 文件，转换模型来自 Google Drive，checkout 中声明了不存在的 Tests 资源，无法作为可信依赖 |

## 本地烟测

本地无管理员权限、Apple ID 或密码需求。下载均来自 sherpa-onnx 官方 GitHub Release：

- `sherpa-onnx` Python 1.13.4（本机 arm64）
- `3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx`
  - SHA-256：`aa3cfc16963a10586a9393f5035d6d6b57e98d358b347f80c2a30bf4f00ceba2`
- `sherpa-onnx-v1.13.4-ios-no-tts.tar.bz2`
  - SHA-256：`dcc5f1748144e88bdb17dfb7b9e5d06d194f478cdb6047adc133f9480c473b1a`
  - 解压后 iOS device slice：sherpa 静态库约 16 MB，ONNX Runtime framework 约 42 MB；加模型约 28 MB。真实 App Store 下载/安装增量仍需在最终链接后测量。

官方成人样本的 192 维 embedding 结果：

| 比较 | cosine similarity |
|---|---:|
| Fangjun，同一说话人两个片段 | 0.8095 |
| Leijun，同一说话人两个片段 | 0.7776 |
| Fangjun vs Leijun | 0.2476 |

在本机 M4、Core ML provider 上，2.3–5.2 秒片段单次 embedding 约 18–22 ms。这只证明模型和本地执行链可运行，**不证明 iPhone 真机性能或儿童准确率**。

短片段烟测暴露了 sight-word 场景的核心风险。同一成人说话人的另一段音频与 enrollment 比较，截取 0.5 秒时 similarity 只有 `0.5061`，1.0 秒为 `0.7402`；官方示例阈值是 `0.6`。孩子只读一个词时经常不足一秒，因此不能逐词硬判 speaker。更安全的 Alpha 是累计本次 quest 的多个 utterance 后形成 session-level 信号。

## 为什么暂不生产启用

- 研究显示儿童与成人的有效频谱区域不同，且年龄越小表现越差：[Speaker recognition for children's speech](https://www.isca-archive.org/interspeech_2012/safavi12_interspeech.html)。
- 2025 年儿童声纹研究再次指出成人语音训练的系统在儿童场景中性能下降，需要儿童域适配：[G-IFT](https://www.isca-archive.org/wocci_2025/shetty25_wocci.html)。
- enrollment 前存在“先有鸡还是先有蛋”：尚未建立孩子模板时，系统无法可靠判断录音中谁是孩子。首轮注册只能依靠家长引导、VAD、安静环境和单说话人质量检查。
- speaker embedding 是识别，不是 source separation。成人与孩子重叠说话时，不能承诺只保留孩子声道。
- 单个 sight word 太短，不能直接照搬成人长语音的固定阈值。

## 最小 Device Alpha 实验

1. 家长门后明确说明：完全本地、原始录音不落盘、不上传，可随时删除声纹。
2. 约 1 分钟注册：6–8 个有趣提示，每段 1.5–5 秒；至少 6 段且累计有效语音至少 15 秒。每段 PCM 只在内存中存在，产出 embedding 后立即释放；只保存归一化 centroid 和模型版本。
3. 不做逐词 speaker gate。一个 quest 中累计多个 read utterance，只有信号稳定时标记 `likelyMatch`；短音频、噪声、多说话人和模型错误全部为 `unavailable`。
4. 跨 3 天做真机 Alpha：孩子在安静/电视背景/正常家庭噪声下各读若干词；家长或其他儿童也读同样内容。只保存 similarity、时长、场景标签和人工 speaker label，不保存音频。
5. 在至少一个 iPhone 和一个 iPad 上测延迟、内存、发热和安装体积。
6. 发布门槛需要用设备数据确定，不能沿用成人默认 `0.6`。任何阈值下 speaker signal 都不得改变正确率、星星、艾宾浩斯进度或 mastery。

## 已落码的安全基础

- `VoiceprintEmbedding`：有限值校验、L2 归一化、模型/维度隔离。
- `VoiceprintEnrollmentSession`：多段注册状态机；默认至少 6 段、15 秒有效语音；拒绝短、长、跨模型和跨维度片段。
- `DeviceVoiceprintRepository`：明确规定为 device-only，禁止 CloudKit/server adapter 冒充。
- `KeychainDeviceVoiceprintRepository`：只持久化 embedding 模板，`ThisDeviceOnly` 且不同步。
- `SpeakerConfidenceSignal.canBlockLearning` 永远为 `false`。
- 没有把任何占位模型接入 Read/Write，也没有把 profile 的 `voiceprintStatus` 伪装成已注册。

验证：2026-07-12 最近一次运行 `swift test` 为 0 失败；声纹测试 5 项通过。最终交付以当次完整测试输出记录总数。
