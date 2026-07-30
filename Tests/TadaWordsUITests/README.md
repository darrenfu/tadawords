# Critical UI smoke tests

`TadaWordsCriticalFlowUITests` uses the app's existing Debug-only demo
composition. It covers child and parent device-level regressions without microphone,
handwriting-recognition, network, or persistent-data dependencies:

- two consecutive Write words advance after the transient completion card;
- the simplified Spell Mode chooser exposes Handwriting, Typing, and the
  shared circular Back control before the custom letter keyboard advances;
- two consecutive Read words advance after the transient `You got it!` card;
- Parent Home back navigation returns to Kid selection and restores the gate;
- parent-only Privacy Policy and Support remain discoverable on compact and
  regular-width layouts, with the installed app version and build visible at
  the bottom of the section;
- parent-only offline Credits expose the exact Twemoji attribution,
  pinned source, and CC BY 4.0 license behind the Parent Gate;
- two consecutive parent deletions retain Undo, skip the second confirmation,
  and leave the pool sort menu interactive;
- Delete All names the affected pool and count, then restores the complete pool
  through Undo;
- preset lists add nothing until explicit parent approval, then de-duplicate
  independently into both pools;
- dismissing the same system Photos picker used by bulk import does not leave
  an invisible modal layer over the pool sort control;
- a Debug-only OCR fixture exercises Review -> Add All -> visible pool rows ->
  sorting with ordinary and pronunciation-sensitive words.

Generate the Xcode project after changing `project.yml`, then run:

```sh
make generate
xcodebuild test \
  -project TadaWords.xcodeproj \
  -scheme TadaWords \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:TadaWordsUITests/TadaWordsCriticalFlowUITests
```

## OCR fixture boundary

The deterministic OCR fixture exists only in the Debug demo composition
launched with `--demo-mode`, `--ui-testing`, and
`--ui-testing-ocr-fixture`. Without that full set, the demo continues to use
`NoImageTextRecognitionService` and the fixture entry is not visible. Release
and LocalQA builds do not compile the fixture.

The fixture verifies app-owned parsing, review, submission, pool refresh, and
sorting. Real Photo Picker/Camera image transfer and Apple Vision OCR still
require connected-device manual verification with a known photo.
