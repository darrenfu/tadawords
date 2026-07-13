# Child-speech test fixture source

## Included audio

- Local file: `speechocean762-000010168-bye.wav`
- Dataset: **speechocean762**, OpenSLR resource SLR101
- Utterance ID: `000010168`
- Canonical transcript: `BYE`
- Speaker ID: `0001`
- Dataset metadata: age `6`, gender `m`
- Language context: English spoken by a native Mandarin speaker
- Audio: PCM WAV, mono, 16-bit, 16 kHz, 1.67 seconds

The dataset documentation states that half of its speakers are children, that all
speakers are native Mandarin speakers, and that age and gender metadata are
provided. The canonical training metadata maps this utterance to speaker `0001`,
age 6, gender male, with the transcript `BYE`.

## License and attribution

OpenSLR publishes SLR101 under the **Creative Commons Attribution 4.0
International (CC BY 4.0)** license. The dataset is credited to:

> Junbo Zhang, Zhiwen Zhang, Yongqing Wang, Zhiyong Yan, Qiong Song,
> Yukai Huang, Ke Li, Daniel Povey, and Yujun Wang. “speechocean762: An
> Open-Source Non-native English Speech Corpus For Pronunciation Assessment.”
> Interspeech 2021.

- Official dataset and license: https://www.openslr.org/101/
- Upstream repository recommended by OpenSLR: https://github.com/jimbozhang/speechocean762
- Direct audio source: https://raw.githubusercontent.com/jimbozhang/speechocean762/main/WAVE/SPEAKER0001/000010168.WAV

The local WAV is an unmodified copy of that source; no changes were made.
- Transcript metadata: https://raw.githubusercontent.com/jimbozhang/speechocean762/main/train/text
- Utterance-to-speaker metadata: https://raw.githubusercontent.com/jimbozhang/speechocean762/main/train/utt2spk
- Speaker-age metadata: https://raw.githubusercontent.com/jimbozhang/speechocean762/main/train/spk2age
- Speaker-gender metadata: https://raw.githubusercontent.com/jimbozhang/speechocean762/main/train/spk2gender
- License text: https://creativecommons.org/licenses/by/4.0/

The local copy is retained solely as a deterministic recognition-test fixture
and keeps this attribution beside it.

## Test limitations

- This is a real child recording according to the dataset's explicit age
  metadata, not an inference from how the voice sounds.
- The speaker is 6 years old, not the product's primary 4-year-old target.
- `BYE` is a single, short word. It is useful for testing recording ingestion,
  transcription, normalization, and pass/fail timing, but not long-phrase
  recognition.
- The fixture cannot validate microphone capture, acoustic echo cancellation,
  background-noise suppression, or audio-session behavior on a physical iPhone
  or iPad because it bypasses the device microphone.
- It cannot validate the claimed child's voiceprint. A single public recording
  from another child provides neither an enrollment sample nor a same/different
  speaker pair for the app's kid profiles.
- It must not be used to claim production accuracy. A representative test set
  across ages, accents, noise conditions, devices, and target words is required
  for that.
