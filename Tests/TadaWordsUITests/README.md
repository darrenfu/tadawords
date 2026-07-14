# Critical UI smoke tests

`TadaWordsCriticalFlowUITests` uses the app's existing Debug-only demo
composition. It covers five device-level regressions without microphone,
handwriting-recognition, network, or persistent-data dependencies:

- two consecutive Write words advance after the transient completion card;
- two consecutive Read words advance after the transient `You got it!` card;
- two consecutive parent deletions retain Undo, skip the second confirmation,
  and leave the pool sort menu interactive;
- dismissing the same system Photos picker used by bulk import does not leave
  an invisible modal layer over the pool sort control;
- a Debug-only OCR fixture exercises Review -> Add All -> visible pool rows ->
  sorting with ordinary and pronunciation-sensitive words.

Generate the Xcode project after changing `project.yml`, then run:

```sh
xcodegen generate
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
