<!-- TADA_BILINGUAL_DOC: English is the default reading language. The original source text is preserved for verification. -->
<a id="english-default"></a>

> **Languages / 语言：** **English (default) / 英文（默认）** · [简体中文](#简体中文版)

# Tada Words Childrenvoiceprint Device Alpha Conclusion

Date: 2026-07-12

## conclusion

At present, the "Device End Alpha Basic" can be delivered safely, but **it is not possible to mark the child voiceprint as production completed, nor is it possible to connect the speaker mismatch to the child's wrong answer**.

The reason is not that the iOS model cannot run, but that the public scheme lacks credible verification for 4-year-old children, household noise and single sight word phrase sounds. At this stage, the correct semantic meaning of the product is: voiceprint only provides a non-blocking confidence signal; unavailability or suspected mismatch can only trigger technical retry or be completely ignored.

## Apple capability boundaries

- Apple [Speech framework](https://developer.apple.com/documentation/speech/) is responsible for speech-to-text, and does not provide speaker identity verification. `supportsOnDeviceRecognition` only indicates whether ASR can run offline.
- [`setVoiceProcessingEnabled`](https://developer.apple.com/documentation/avfaudio/avaudioionode/setvoiceprocessingenabled%28_%3A%29) and [`voiceChat`](https://developer.apple.com/documentation/avfaudio/avaudiosession/mode-swift.struct/voicechat) of `AVAudioEngine` can provide voice processing such as echo cancellation and automatic gain, but they cannot guarantee that "only the child's voice will be left".
- [Core ML](https://developer.apple.com/documentation/coreml) can fully localize inference; therefore, there is no need for a server database or uploading recordings.
- Finally, embedding is suitable for storing in the Keychain and using [`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly), so as not to migrate to new devices and not participate in iCloud Keychain synchronization.
- Apple requires explicit consent and visible/audible prompts for microphone collection; Kids Category also requires careful handling of child data, see [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

## Candidate plan evaluation

| Scheme | License / Size | iOS Local Reasoning | Applicability for 4-year-old children | Conclusion |
|---|---|---|---|---|
| Apple Speech + Voice Processing | System framework, no additional models | is | no speaker verification | Reserved for ASR and noise reduction, cannot claim voiceprint |
| [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) + [3D-Speaker CAM++ Chinese and English models](https://modelscope.cn/models/iic/speech_campplus_sv_zh_en_16k-common_advanced) | Apache-2.0; model 28,281,164 bytes; official iOS no-TTS package 41,692,409 bytes | official support iOS arm64, Swift/C API, CPU/Core ML provider | Adult/general corpus, no 4-year verification | **Device Alpha preferred**, not included in production scoring |
| [WeSpeaker](https://github.com/wenet-e2e/wespeaker) | Apache-2.0; ONNX about 26–114 MB | Can be deployed by sherpa-onnx | Main VoxCeleb/CNCeleb adult data | Can be used as a comparison model, not prioritized integration |
| [SpeechBrain ECAPA-TDNN](https://github.com/speechbrain/speechbrain) | Apache-2.0; [Pre-trained package about 89.1 MB](https://huggingface.co/speechbrain/spkrec-ecapa-voxceleb/tree/main) | PyTorch scheme, no first-class native iOS package | VoxCeleb adult data | Optional |
| [NVIDIA TitaNet-Large](https://huggingface.co/nvidia/speakerverification_en_titanet_large) | CC-BY-4.0; 23M parameters | Can be converted by yourself or use ONNX | Model cards clearly indicate that fine-tuning is required across domains, and the training set is mainly adult speech | Do not select the first edition |
| `Otosaku/NeMoSpeaker-iOS` | README states MIT, 7/14/27 MB | Core ML Swift API | No child verification | Does not use: repository There is no LICENSE file, and the conversion model comes from Google Drive. The non-existent Tests resource is declared in the checkout, which cannot be used as a credible dependency |

## Local smoke testing

There is no administrator permission, Apple ID or password requirement locally. The downloads come from the official GitHub Release of sherpa-onnx:

- `sherpa-onnx` Python 1.13.4 (native arm64)
- `3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx`
  - SHA-256：`aa3cfc16963a10586a9393f5035d6d6b57e98d358b347f80c2a30bf4f00ceba2`
- `sherpa-onnx-v1.13.4-ios-no-tts.tar.bz2`
  - SHA-256：`dcc5f1748144e88bdb17dfb7b9e5d06d194f478cdb6047adc133f9480c473b1a`
  - After decompression iOS device slice: sherpa static library is about 16 MB, ONNX Runtime framework is about 42 MB; plus the model is about 28 MB. The real App Store download/installation increment still needs to be measured after the final link.

192-bit embedding results of the official adult sample:

| Comparison | cosine similarity |
|---|---:|
| Fangjun, two excerpts from the same speaker | 0.8095 |
| Leijun, two excerpts from the same speaker | 0.7776 |
| Fangjun vs Leijun | 0.2476 |

On the local M4 and Core ML provider, the single embedding of 2.3-5.2-second clips takes about 18-22 ms. This only proves that the model and the local execution chain can run, **but does not prove the iPhone physical device performance or child accuracy**.

The short video smoke test exposed the core risk of sight-word scenes. Compared with the other audio segment of the same adult speaker, the similarity when extracting 0.5 seconds is only `0.5061`, and 1.0 seconds is `0.7402`; the official example threshold is `0.6`. When children read only one word, it is often less than a second, so they cannot judge the speaker word by word. A safer Alpha is to form a session-level signal after accumulating multiple utterances of this quest.

## Why it is not yet enabled in production

- Research shows that children and adults have different effective frequency spectrum areas, and the younger the age, the worse the performance: [Speaker recognition for children's speech](https://www.isca-archive.org/interspeech_2012/safavi12_interspeech.html).
- In 2025, the Children's voiceprint study once again pointed out that the performance of the system for adult voice training declines in children's scenarios and needs to be adapted to the children's domain: [G-IFT](https://www.isca-archive.org/wocci_2025/shetty25_wocci.html).
- There was a "chicken or egg first" before enrollment: when the child template was not yet established, the system could not reliably determine who was the child in the recording. The first round of registration could only rely on parental guidance, VAD, quiet environment and single speaker quality inspection.
- Speaker embedding is recognition, not source separation. When adults and children speak overlappingly, it is impossible to promise to only retain the child's channel.
- Single sight words are too short to directly copy the fixed threshold of adult long speech.

## Minimum Device Alpha Experiment

1. Parents are clearly instructed behind the door: completely local, original recordings will not be stored or uploaded, and can be deleted at any time voiceprint.
2. About 1 minute to register: 6-8 interesting tips, 1.5-5 seconds per segment; at least 6 segments and a cumulative effective voice of at least 15 seconds. Each segment of PCM only exists in memory and is released immediately after embedding is produced; only normalized centroids and model versions are saved.
3. Do not do speaker gate by word. Accumulate multiple read utterances in a quest, and only mark `likelyMatch` when the signal is stable; short audio, noise, multiple speakers and model errors are all `unavailable`.
4. Do physical device Alpha for 3 days: Children read a few words each in a quiet/TV background/normal family noise; parents or other children also read the same content. Only similarity, duration, scene labels and manual speaker labels are saved, and audio is not saved.
5. Measure latency, memory, heat, and installation volume on at least one iPhone and one iPad.
6. The release threshold needs to be determined by device data, and cannot be carried over from the adult default `0.6`. Under any threshold, the speaker signal should not change the accuracy, stars, Ebbinghaus progress or mastery.

## The security foundation that has been coded.

- `VoiceprintEmbedding`: Limited value verification, L2 normalization, model/dimension isolation.
- `VoiceprintEnrollmentSession`: Multi-segment registration state machine; default at least 6 segments, 15 seconds of valid voice; refuse short, long, cross-model and cross-dimensional segments.
- `DeviceVoiceprintRepository`: Clearly stipulate that it is device-only and prohibit CloudKit/server adapter impersonation.
- `KeychainDeviceVoiceprintRepository`: persists only embedding templates, uses `ThisDeviceOnly`, and does not sync.
- `SpeakerConfidenceSignal.canBlockLearning` Always for `false`.
- Neither any placeholder models were connected to Read/Write, nor was profile `voiceprintStatus` disguised as registered.

Verification: the latest `swift test` run on 2026-07-12 had 0 failures; all 5 voiceprint tests passed. Final delivery must record the total from the full test run at that time.
<!-- TADA_BILINGUAL_ZH_START -->

---

<a id="简体中文版"></a>

> **翻译说明：** 英文为默认阅读语言；本文同时保留原始语言文本。如中英文内容存在差异，请以原始语言文本为准。

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
