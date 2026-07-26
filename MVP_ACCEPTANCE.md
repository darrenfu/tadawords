<!-- TADA_BILINGUAL_DOC: English is the default reading language. The original source text is preserved for verification. -->
<a id="english-default"></a>

> **Languages / 语言：** **English (default) / 英文（默认）** · [简体中文](#简体中文版)

---
title: How to Accept Tada Words V1
navLabel: V1 acceptance
contentType: How-to
category: Delivery
---

# How to Accept Tada Words V1

Use this checklist to accept the current V1. First run the automated checks and both simulators; then use real iPhone and iPad devices to accept microphone behavior, child speech, handwriting, accessibility, audio, CloudKit, and notifications.

## Understand the acceptance states

Each item uses one of the following states:

- **Code complete**: the production path and automated tests exist.
- **Simulator checked**: navigation, layout, state, and local persistence can be verified.
- **Physical-device acceptance required**: the item depends on real hardware, child samples, Apple accounts, or human listening.

Passing code or simulator checks does not prove child-recognition accuracy, mix quality, or CloudKit family-sharing acceptance.

## Run automated checks

Run from the repository root:

```sh
cd /path/to/tadawords
make generate
make check
./Scripts/verify-device-readiness.sh
```

Pass criteria: formatting, unit and integration tests, the iPhone 17 Pro Max LocalQA simulator build, and the iPad Pro 13-inch (M5) LocalQA simulator build all pass. The device-readiness script may report a signing blocker when no Team is configured.

PR #2 v0.3 has been merged into `main` in merge commit `cc42e17`. The current v0.3.1 repair evidence on 2026-07-14 is as follows. 367 tests of V1, 480 tests of v0.2 and 548 tests of v0.3 are retained as historical baselines; the full v0.3.1 is 595/595:

| Inspection | Results |
|---|---|
| Swift formatter strictly checks | passes |
| Swift unit and integration tests | v0.3.1 full suite passed 595/595 with 0 failures; the focused actual-Vision handwriting-recognition suite passed 15/15, and the focused World-layout suite passed 5/5 |
| Critical XCUITest | iPhone 17 Pro Max simulator 7/7 Passed: Read/Write Continuous feedback, two deletions/Undo, Delete All/Full recovery, Preset Only added after clear approval, Photos sorted after exiting, OCR Review → Add All → Pool → Sort |
| iPhone 17 Pro Max production Vision physical device test | iOS 26.5.1 Above 2/2 XCTest passed: `of/go` Six uppercase and lowercase positive examples 6/6, wrong words and literal `90` Negative examples 4/4; use anonymous synthetic vector and real production service, no mock/demo |
| iPad Air 13-inch (M4) production Vision physical device test | iPadOS 26.5 above 2/2 DeviceTests passed: wrong-word rejection and `of/go` case variants; use real production service and anonymous synthetic vector |
| iPad Air 13-inch (M4) Critical XCUITest | LocalQA Configuration below 7/7 Passed: OCR Add All, Delete All/Full Recovery, Preset Clearly Approved, Continuous Delete/Sort, Photo picker/Sort, Read With Write Complete feedback disappearance |
| iPhone 17 Pro Max LocalQA simulator build | v0.3.1 fresh build passed |
| iPad Pro 13-inch (M5) LocalQA simulator build | v0.3.1 fresh build passed |
| iPhone 17 Pro Max physical device Installation | `Tada Words QA` v0.3.1 (`2026071402`) signed build has been covered for installation and launch; children's real writing and pronunciation listening quality and accessibility still need manual acceptance |
| iPad Air 13-inch (M4) physical device Installation | Darren iPad, iPadOS 26.5; Team `6S245NCUPQ` signing's `Tada Words QA` v0.3.1 (`2026071403`) has been installed and started; children's real writing, pronunciation listening quality, layout, rotation and accessibility still need manual acceptance |
| Direction statements for two built products | v0.2 baseline: iPhone for Portrait + two Landscapes; iPad for four directions; `UIRequiresFullScreen` for true; runtime Parents can be rotated, and child route is only allowed for landscape screen |
| simulator Direction evidence | v0.2 Baseline: iPad's Parent and child window morphology conforms to the routing strategy; iPhone raw framebuffer screenshot direction is unreliable, and physical device rotation confirmation is still required |
| Release CloudKit Share statement | v0.2 Baseline: iPhone and `CKSharingSupported` of iPad Release built product are true |
| LocalQA Isolation statement | v0.2 Baseline: `Tada Words QA` Use an independent bundle ID, empty iCloud entitlement, and `CKSharingSupported` is false |
| Child voice fixture | v0.2 Baseline: SHA-256 passed, Apple transcribed as `Bye.`, App policy judged the target `bye` as matching |

### Current v0.7.0 Family Sync evidence

The table above retains the historical delivery records of v0.3.1. The current v0.7.0 (`2026071806`) has the following additional evidence:

| Inspection | Results |
|---|---|
| Swift formatter strictly checks | passes |
| Swift unit and integration tests | 814/814 passed with 0 failures; Issue Agent passed 14/14 |
| Family Sync XCUITest | source batch: iPhone 17 Pro Max 6/6, iPad Pro 13-inch (M5) 6/6, iOS 26.5; before merge, exact committed HEAD must be rerun |
| Critical XCUITest | source batch: iPhone 17 Pro Max 10/10, iPad Pro 13-inch (M5) 10/10, iOS 26.5; exact committed HEAD Retesting is the delivery threshold |
| Production CloudKit | Source contract has been completed; schema, signingphysical device private/share, background push, owner/participant access management, remote deletion and manual recovery copywriting are still pending acceptance |

`CKSharingSupported` is a build statement and does not represent that simulator is running CloudKit. simulator deliberately uses local/device-only transport; real CloudKit transport can only be used on the signingphysical device of the configuration Team, container and iCloud.

The DeviceTests and Critical XCUITest of iPad prove that the production identification link and seven key interactions can run in physical device. They do not replace the child's real handwriting, standard pronunciation listening quality, layout in all directions Apple Pencil, VoiceOver or Dynamic Type manual acceptance.

The copy of `.xcodeproj` numbered has been deleted. Only open `TadaWords.xcodeproj`, and do not use Derived Data before the direction or ability change.

## Check the key requirements

| Demand | Current Status | manual acceptance Key Points |
|---|---|---|
| Read Two independent routes | Code completed | Two Today Quest buttons are not merged, and data and settings do not overlap |
| Parent Word Manager | v0.2 The foundation has been merged; v0.3/v0.3.1 enhancement has been completed, waiting for physical device to return | Word Return is added immediately; multiple photos Camera/Photo OCR; word numbering; single picture 500 word limit; added/A-Z/most practiced sorting; frequency; type-ahead search; Hear/Delete; single deletion/batch deletion/empty whole group; deletion confirmation and Undo button Profile isolation; two independent groups of deduplication |
| Only use the parent-approved words | v0.3.1 code to complete | No automatic smart fill / Grade addition; typing, OCR or Preset must be clearly submitted by the parent, and words will not be added when the pool is insufficient |
| Preset Words by age/grade | v0.3.1 code and content audit completed, waiting for physical device layout to return | 3-8 years old / Pre-K–Grade 3; 34 groups, 40-45 words per group; up to 6 groups recommended, then browse by level; search, word by word/full selection, Read/Write/Both; opening or recommending will never be automatically added |
| The order of New and Review can be exchanged | The code has been completed | Each route is saved in an independent order |
| Ebbinghaus Review and strengthen | Code completed | Expiration, errors, relative slowness, replay and Help affect sorting and memory parameters |
| Write No preview of the answer and one guided rewrite | v0.3 code completed, waiting for physical device to return | Only the pronunciation is broadcast at the beginning of each word, and the spelling is not displayed; only the dot `?` shows the answer; the first real wrong answer may appear specific word picture buttons |
| Read Quiet first answer and Help after two wrong answers | v0.3 code completed, waiting for physical device to return | No answer is broadcast before the first answer; only Hear it appears after two valid wrong answers; no picture prompts; technical failure does not unlock or consume times |
| True Mastered determination | Code completed | Three different local dates independently succeeded, and the recall rate is expected to meet the standard in the next 14 days |
| Score, loose three stars, strict Guardian Evidence | v0.3 Code completion | Accuracy threshold 75%; immediate recovery without assistance once; calibration Pace; 50% allowance for slow side; perfect first answer fixed 100 points/3 stars; technical Move On display Not scored |
| Eight independent theme worlds | v0.2 Code completed, waiting for physical device audiovisual return | Princess, construction vehicle, animals, dinosaurs, firefighting and rescue, original blocks, ice and snow and roller coaster scenes/rewards are not mixed |
| 20 small rewards and 5 milestones in each world | v0.2 code completed, waiting for physical device visual return | A total of 200 different icons; permanent collections are not reposted due to Practice Again |
| Double Quest the next day Theme / Icon | v0.2 code completed, waiting for physical device to return | the same day Read+Write's Today run unlocks the next day; partial/replay is not counted; My Collection can choose the items obtained |
| Multi Kid Profile, age and last Profile | v0.3.1 code completed, waiting for physical device to return | cold startup first to Picker and highlight the last Profile; the first/Kid/Parent new creation collects 3-8 years old age; each Profile data, voiceprint, settings and cosmetics isolation |
| Profile-first first process | v0.3.1 code completed, waiting for physical device layout re-examination | none Profile directly New Kid; first record nickname and age, no word input in the first process |
| Pre-K child-friendly visual hierarchy | v0.2 simulator Checked, waiting for children to interact with accessibilityacceptance | last time Profile Static highlights; iPhone Lobby icon dock retains 72 pt touch area; Read Pronouns and Result rewards are more prominent; iPad Text tool entry retains |
| Selfies, photos, animals avatar | Codes completed | physical device Check Camera and Photo Library permissions |
| Monthly punch-in Calendar | The code has been completed | Displays the accurate number of Quest attempts per day, Practice Again and counts |
| 7-day and 30-day reports | Codes completed | Check trends, word details, identify corrections and export to CSV |
| Crash-resumable Profile Delete | Code completed | Delete local data, words, history, rewards, reminders and native voiceprint |
| Local notifications and quiet hours | Code completed | Daily, Pool low, completed, synchronization failure, weekly report and time setting |
| CloudKit Synchronization and family invitation | v0.7.0 source: versioning CKSyncEngine, complete Profile data, event recomputation, crash-resistant apply and remote deletion semantics have been implemented; production acceptance is not completed | with paid Developer Team, production schema, two devices and two Apple accounts acceptance private/share, background push, offline merge and test-only remote wipe; this ability cannot be released before the previous |
| 1 minutevoiceprintRegistration and Read Matching | v0.3 Follow-up process is completed, and children's sample calibration is required | Random short sentences are played one by one, children's follow-up, and rejected samples can be repeated; voiceprint Only the local Keychain is saved, and the original recording is not saved or synchronized |
| Apple Pencil With palm touch filtering | The code has been completed, and physical-device acceptance | iPhone needs to use fingers, iPad test fingers and Pencil | separately.
| VoiceOver、Reduce Motion、Dynamic font | The code has been completed, and physical-device acceptance | complete walk check feedback broadcasting, focus, horizontal screen compact height | is needed.
| Single teacher contract and theme music | Katie/Aurora offline package has been implemented and passed bundle/transcription check; requires physical device manual listening quality approval | Does not provide Profile voice style; 500 words are canonical as Katie Read 0.90× / Write 0.82× dual versions; Aurora quality exception recorded in manifest is used, and off-package words use Apple fallback; Aurora is responsible for continuous startup of short sentences `Ta-dá↗ woooords↘!`, six correct answers to micro celebrations and Quest completion; the client does not store provider key; Moonpetal rainbow/unicorn and cheerful music |
| Eight original World | v0.2 code completed, waiting for physical device audiovisual return | New Dino, Firehouse, Brickwork, Frostlight, Coaster added; each with isolated scenes, mascots, colors, rewards and music |
| Write Pencil case and stable canvas | v0.2 The foundation of the pencil case has been merged; v0.3 Enhancement is completed, waiting for physical device handwriting to return | Pencil/Chalk/Brush Three black pens, each Profile Durability, smooth brushstroke sound effect, 4× local erasure, blank click restores the original pen, canvas width increases by 10%; root Quest transition identity maintains stability, and the coordinates do not move when cutting words/feedback |
| Specific word picture prompts | v0.3 Code completed, waiting for physical device network/offline regression | Asynchronous caching of fixed Twemoji resources after entering the Pool; Write The first real wrong answer shows that you can click the picture; `the` Abstract/functional words do not request pictures |
| Parent Gate Completed with Lock | v0.3 code, automatically judges the result after physical device returns | enters the complete number of digits; immediately resets when there is an error, but the feedback is retained until the next input; Lock of Parents directly returns to Kids page |
| Treasure icon and avatar | v0.2 code are completed, waiting for physical device to return | 8×25 related icons; locked retains the gray icon with lock; collected treasure can be optional avatar and retains the original photo |

## Understand the score and word pronunciation

The following rules are used for children's result pages. Guardian The report still shows the strict first independent answer, and the supplementary answer is not rewritten as the first answer is correct.

| Project | Rules |
|---|---|
| Completion Star | Complete all the words in the plan |
| Accuracy Star | The accuracy of the first independent answer reaches 75%, or only one word is wrong in the whole round and then answer correctly without prompts |
| Personal Pace Star | Accuracy has been achieved, and the speed falls within the personal range, is still within the valid calibration period, or the first answer of the whole round is perfect |
| Points | The correct rate is up to 80 points, and the speed is up to 20 points |
| Perfect first try | Whether there is a speed baseline or not, fixed 100 points and 3 stars |

Parents can manually enter, import photos in bulk, or select words explicitly from the local Preset Catalog. All new words are uniformly used with canonical isolated teacher pronunciation; the Parent UI does not provide context sentences or multiple pronunciation editing interfaces. Age/grade recommendations are only sorted and will not be automatically added. Contextual audio metadata saved in the old version can still be read to avoid data loss during the upgrade.

## acceptance Kid Profile and Guardian

1. Start after clearing LocalQA data; the first screen must be `New Kid`, and there should be no word input.
2. Read and accept the versionized privacy statement, create nickname, age 3–8 years old, animal avatar, Grade and starting World
3. Forced exit and restart; Profile Picker The last valid Profile must be highlighted, and the child will not enter the Lobby until they click it.
4. Create a new Profile, enter different words and settings for both, and then verify the Picker and isolation.
5. Simply click **Parents** to confirm that the random arithmetic Parent Gate will appear immediately; after entering the complete number of digits, there is no need to click Unlock to automatically judge the answer. The wrong answer will be automatically cleared, but the wrong prompt will remain visible until the parent begins to enter the next answer.
6. Let the child build a second Profile in Picker, enter nickname and age; confirm that the suggested Grade is reasonable. Then enter Parents to edit Profile, verify that parents' age changes will not silently override the clearly selected Grade, and test avatar source from Camera selfie, Photo Library and animal icons each time.
7. From the Parent dashboard, click **Lock** to confirm immediate locking and return to Kids Profile Picker.
8. Delete the non-unique Profile used last time; after restarting, you must return to the legitimate Picker, do not guess the identity or resurrect the data.

Pass criteria: Each Profile isolates words, settings, learning records, calendars, rewards and voiceprint. All new Profile save valid ages; old versions without age Profile can still be read. Sensitive operations require system device authentication. The App must retain at least one Profile. Onboarding does not request microphone, Speech, Camera, Photo Library or notification permissions; relevant permissions are only requested when the corresponding functions are first used.

## acceptance Parent Word Manager

1. Cut to Read Tab, enter `the` and press Return; confirm to save immediately, clear the input box and `the` will appear at the top.
2. Enter `look`, `play` in turn; confirm that it is always newest-first. Enter `the` again with the same Pool to move forward instead of copying the history.
3. Cut to Write Tab and enter `the`; confirm that the two groups Read/Write can have the same nouns.
4. Select at least two school list from Photo Library at one time; then add pictures with **Add photos** and **Take another** to merge the results into the same preview.
5. Verify that each OCR word is numbered starting with 1; edit or delete misidentified items and switch between Added order, A-Z, and Most practiced.
6. Prepare a single image with more than 500 recognition words to confirm that the image has been clearly rejected and prompt the replacement of the image; the results of other images that do not exceed the limit will not be lost.
7. Scroll through the long preview to verify that the top return/top button and the bottom button return; click **Add all N to Read/Write** to confirm that the buttons will not be blocked by the keyboard, will be submitted only once, and that the saving progress will be displayed or an error will be clearly shown.
8. In Pool, switch to Added order, A-Z, Most practiced, and check the frequency number of each line; search with type-ahead and directly click the Hear and Delete of the line.
9. The confirmation pop-up window appears when deleting for the first time; after confirmation, continue to delete individually and batch delete. After confirmation, the pop-up window for this Parent session will no longer appear repeatedly, and Undo will still be available.
10. Separately at Read and Write point `Delete all N words`: cancel once, and confirm again; check the clear quantity/mode, the other Pool remains unchanged, the learning history is not deleted, and restore it completely with Undo.
11. Switch to Profile B after deleting or clearing Profile A; confirm that B does not inherit A's initial deletion confirmation state or Undo, and that B's operation cannot restore or modify A's Pool.
12. Open Preset Words from Today; check up to 6 age/grade matching recommendations, and then browse Sight Words, Phonics, animals/dinosaurs/vehicles/cities/countries, actions and Emotions layer by layer. When opening the list, Pool remains unchanged; select words one by one or Select all, submit them to Read, Write, Both respectively, and check for duplicates.
13. Check the transaction boundaries for both imports: When normal, both pools are updated; if any pool fails to save, is partially successful, or the number of returns does not match, only the membership inserted or re-enabled this time is rolled back, and both the active word and the other Profile remain unchanged.
14. Enter text in the typing, search and OCR text editing boxes, and then click the blank space; confirm that the keyboard is closed; the pronunciation/context section does not appear in the whole process.
15. Clear or shrink the Pool, restart and prepare the Quest; confirm that there will be no catalog or smart-fill new words that have not been clicked by the parents.

Pass criteria: All new additions to the Pool can be traced back to typing, OCR or Preset selection explicitly approved by parents; the original school-list images are only recognized on the local machine and are not saved. Each image executes the 500-word limit independently. The Preset and delete operations are bound to the Profile that initiates them, and both imports will not leave a half-finished state. The keyboard, OCR sheet, sticky Add All, Preset layers, and selection toolbar are not cropped in the iPhone/iPad horizontal and vertical Parent route.

## acceptance Read Quest

1. Click the independent **Read Today's Quest**
2. Enter with the new Profile/new words; confirm that the pronunciation is not played at all when the target appears.
3. When you first click on Mic, you can allow Microphone to work with Speech Recognition; the permission waiting time is not counted as the child's speed.
4. Read out the target words, confirm the correctness, give feedback and record the results.
5. After reading it wrong for the first time, confirm that **Hear it** is hidden; after reading it wrong for the second time, confirm that only **Hear it** appears and there is no picture button.
6. Tap **Hear it** to confirm that playback is only triggered by the child's button press; the pronunciation must be clear, continuous, and without trailing consonants. After switching to the next word, help it to hide again.
7. Create silent, noise, technical failure, confirm that it does not consume valid attempts, does not deduct the accuracy rate, and does not unlock Help in advance; if there are three consecutive technical failures, you can neutralize Move On.
8. Test `a`, `I`, `go`, `look`, `bye` (including Apple punctuation transcription at the end of sentences) and 0.8-second natural pause
9. The children's near-tone `kum/cum` of the test target `come` can pass, while `some`, `home`, `came` and `cat/cap` are not mistakenly relaxed.
10. After establishing voiceprint, let the target children and another speaker test separately.
11. Continuously switch between multiple words to confirm that uppercase letters always use the same dark color as the current World; only switching between Worlds changes the color, and it is always clear and readable.
12. Complete one round, in which you deliberately answer incorrectly or use help; at the Result point Replay, confirm that you only review the tricky words of this round. The Perfect Round does not display the empty Replay button.

Pass criteria: Technical failure does not enter the learning evidence. voiceprint If it does not match, go for a technical retry, and do not record the other speaker as a child answering incorrectly. The accuracy of real family noise, automatic recording stop, echo cancellation and recognition can only be in physical-device acceptance.

## acceptance Write Quest

1. Click the independent **Write Today's Quest**
2. Confirm that only the pronunciation is played for both New and Review words, and no spelling is displayed in advance; the target word is only displayed after clicking `?`.
3. Listen to Katie Write version `of`, `at`, `cat`, `come`, `look` to confirm that the offline recording is 0.82× and still a continuous and clear pronunciation; the trailing consonants `f`, `t`, `k`, etc. are not swallowed by the background music, external audio, or audio session, and the music returns smoothly after playback. Enter another word outside the 500-word manifest to confirm that Apple fallback is available.
4. Write the entire word independently in the expanded horizontal line area, then press **Done**; confirm that the app will not submit automatically due to stopping typing.
5. Write the dots of `i`, the last letter of the three-letter word, and the connected `vv`/`w` separately; confirm that the short dots, subsequent strokes and connected strokes are all left.
6. Write the same word in uppercase, all uppercase and all lowercase; confirm that the difference in capitalization does not cause failure.
7. Test **Hear**, separate **?**, **Clear** and **Done**; `?` must display the word immediately and there is no multiple choice. Clear does not pop up for confirmation.
8. For the first time, I wrote `dog` incorrectly in real life. I confirmed that there is a clickable picture button to confirm the occurrence, and the spelling will not be displayed automatically. After clicking the picture, the dog will be displayed. When `the` is written incorrectly, the picture will not be displayed, and no picture request will be initiated.
9. Manufacturing recognition uncertainty and technical failure, confirmation does not count as the child answering incorrectly, and will not trigger the picture incorrectly.
10. Write iPad and Apple Pencil separately with your fingers, and put your palms on the screen.
11. Turn on Left-handed writing and confirm that the main toolbar is switched to the other side.
12. Open the pencil case and confirm that only Pencil, Chalk, Brush and Eraser are available; there are no Crayons or color selection, and all new strokes are black.
13. Switch to a Profile select pen type, restart and switch to Profile; confirm that each Profile retains its own selection until it is modified again; the old version of Crayon/color setting safe migration is black Pencil.
14. Write each word individually and try to hear the three short writing sounds; confirm that there are no popping, stuttering or frequent restarting sounds when moving quickly and continuously, and that the pronunciation playback and Reduced Sound are not superimposed.
15. Confirm that there is no Undo on the confirmation page; use Eraser to erase the local area of each pen, and the erasing width is about 4 times the width of the current pen. After erasing, click the blank next to it to confirm that the previous pen will be automatically restored.
16. If you don't use Help, write `of`, `Of`, `OF`, `go`, `Go`, `GO` respectively, repeat each writing twice and require 12/12 to pass; then confirm that `if`, `on`, `or`, `ot`, `off`, `do`, `no` and the number `90` cannot be missed.
17. Record the screen when the error feedback appears and switch to the next word, and confirm the size, center and coordinates of the writing area do not move frame by frame; confirm that the root transition identity of the whole round of Quest does not change with the prompt; complete the feedback for at least 830 ms and no longer flash.
18. Complete one round and deliberately leave tricky words; at the Result point Replay, confirm that only this word will be retrained.

Pass criteria: Hear, `?`, the identification of waiting and technical retry time does not affect the independent response speed. The visual and sound of the three pens can be distinguished but do not cover the pronunciation. The picture only serves specific words and uses private caching. iPhone Only prompts the finger, iPad Can distinguish between Pencil and finger, and filters obvious palm touches. The production Vision of synthesized strokes physical device test only proves the repair link with known characters, and cannot replace the above child's 12 real writing.

## acceptance Review, Mastered and Today's Plan

1. Set New first and Review first separately.
2. On the New-first route, deliberately answer the new words incorrectly to confirm that it replaces the lowest priority Review and retains the Review debt.
3. Confirm that the Review will fill in the expired words, and also fill in the words that are not expired but obviously weak.
4. Repeat entering a learned word to confirm it moves forward in Review
5. Answer the same word independently on three different dates.
6. Confirm that Mastered is only displayed after the 3-day success threshold and the 14-day estimated recall threshold are met.

Pass criteria: Repeated success on the same day cannot meet the three-day condition. Help, replay, errors and relative personal slow will reduce stability or increase difficulty.

## acceptance Rewards, World and Calendar

1. Complete Read and Write Today Quest separately.
2. Complete a Quest where all words are answered correctly for the first time; confirm the result as 100 points and 3 stars, even if Profile does not yet have a speed baseline.
3. Manufacture 75% first independent correct rate, confirm that there is still an Accuracy Star; manufacture the whole round with only one wrong answer and immediately no prompt to answer correctly, confirm that children's rewards can be relaxed, and Guardian still shows the original first answer correct rate.
4. After the existing personal speed range, the verification of the slow side is limited by up to 50% of the allowance; if you are too fast or exceed the allowance, you will not receive a Pace Star.
5. The confirmation result page shows the score, stars, accuracy rate, personal speed and current world rewards.
6. Complete Practice Again, confirm the increase in the number of Calendars, but do not issue the permanent reward on the same day as the duplicate.
7. On the first day, only Read is completed, and it is confirmed that Theme/Icon will not be unlocked on both the same day and the next day.
8. Complete Read and Write Today Quest on the same local day; they will still be locked on that day, and unlock one unobtained Theme and Icon after moving to the next day or restarting with a controllable clock.
9. Complete Practice Again and repeat completion, confirming that it does not trigger or repeat unlocking; test across days from the end of the month to the next month.
10. Open My Collection, select the Theme and Icon you have obtained separately, and keep them after restarting; the locked item can only be previewed.
11. Check the 20 small rewards and 5 milestones of each World of 8; each icon is relevant and not repeated with the same World, and the original gray icon is still displayed and overlaid when locked.
12. Select a Treasure that has been collected as Profile avatar to confirm that Picker/Lobby is consistent; clicking on an uncollected Treasure will not take effect.
13. If Profile the original avatar is a photo, switch the animal Icon, Treasure avatar and the original photo in turn, and confirm that the photo data can always be retained and restored.
14. Complete multiple Quests on the same day and confirm that the child's Calendar shows the same number as Guardian Today.

Pass criteria: Each World only appears its own rewards. The unlocking and collection progress of the World are isolated according to Profile and retained after restarting.

## acceptance Guardian Reporting and correction

1. Open the **Reports** of Guardian
2. Switch between 7 days and 30 days.
3. Number of completed checks, accuracy rate, personal speed trend and word details
4. Change a recognition result from incorrect to correct, and then back to incorrect.
5. Confirm learning progress from event history reconstruction, and update reports and Needs Attention in sync.
6. Export CSV after system authentication and check fields and Profile scope

Pass criteria: Corrects the case where the summary snapshot is not directly covered. The app reconstructs the current progress using the original attempt and correction event.

## acceptanceNotice

1. Turn on daily reminders, Pool low, completion, synchronization failure and weekly reports in Practice settings.
2. Modify the start and end times of daily reminder time and quiet hours.
3. Allow system notification permissions
4. Confirm that the reminder moves to the allowed time during quiet hours.
5. Close all notifications and confirm that the pending notifications for Profile have been cleared.

Pass criteria: Notification texts do not include children's words, scores or sensitive learning details. Different Profile notifications use stable and non-overlapping identifiers.

## acceptance CloudKit Home synchronization

This section must use the Apple Developer Team configured in `iCloud.com.tadawords.app`. Prepare two devices logged in to different Apple ID.

The default of Family Sync in Release is turned off and saved persistently. The privacy confirmation in Onboarding will not activate CloudKit; only when parents explicitly activate it in Guardian, can access to CloudKit. The shutdown switch will stop future synchronization, but it will not delete the already uploaded records as designed; Profile deletion will first write to the minimum deletion ledger, and then erase Profile zone, children, assets, root and share. The source semantics cannot replace the production CloudKit evidence; this section only uses test-only Profile, and Family Sync cannot be considered as a fully functional feature until all physical device access control is passed.

1. After the first launch and completion of onboarding, confirm that **Family sync** is shown as off and there are no CloudKit requests.
2. Create Profile, words, settings, and learning records on device A
3. Open Family Sync clearly through parent authentication, and then click **Sync now**.
4. Create a family invite and send it to device B via the system Share Sheet.
5. On device B, turn it on and accept the invitation, then sync.
6. As the owner and participant respectively open the system Family access management page; the owner removes the participant, participant Leave, and then revokes it, confirming that the App returns to the terminal state and never silently creates a private fallback.
7. Confirm that Profile/avatar, two Pools, six group settings, attempt/correction, Ebbinghaus progress, daily plan, completion, Calendar, World, Badge, Collection and rewards are consistent; voiceprint of both devices are kept separately from cache.
8. Close Family Sync, confirm that subsequent launches, front-end and back-end switching, manual buttons, invitations, and access management will no longer call CloudKit, and local Quest will continue to be available.
9. After restarting, the two devices will modify different records offline and then synchronize online.
10. Delete a test-only Profile to confirm that another offline device receives the ledger first, clears the local data and cannot be revived; confirm in CloudKit Dashboard/Test Tools that records, assets, shares and zones other than the minimum ledger have been wiped.
11. Forcefully exit and restart in the middle of push, fetch or apply to confirm that the exact pending batch has been restored once, the UI is automatically refreshed and completion/reward will not be repeated.
12. Complete the Quest after the network is disconnected to confirm that local learning is not affected by synchronization failure; the Parent page still accurately displays the pending number, connection/account status, retry and last successful time after restarting.

Pass criteria: Quest submission does not wait CloudKit; the same canonical facts converge consistently and are not duplicated in different arrival orders. Synchronization failure displays the true recoverable state and retains local data. Deletion is non-recoverable. voiceprint Templates do not enter CloudKit; each device is registered separately voiceprint. Record exact commit, version/build, Team/container, schema environment, device/system, account role and evidence path.

## acceptance Voice setup

1. Open **Voice setup** in a Kid Profile, confirm that a short English sentence appears and plays automatically. The child can click Hear again.
2. Let the child read along and record; confirm the successful sample to increase the progress, and then use silence, too short and obvious noise to create rejection. Confirm that the reason for the display can be retried and that the progress has been accepted without loss.
3. Complete at least six valid clips with the minimum valid audio duration; confirm that **Finish setup** is only available when the conditions are met and can be saved and exited.
4. Return after interrupting the recording, locking the screen, or switching to the background; confirm that there will be no permanent gray Finish, zero sampling rate, or general error loop.
5. Open a new setup to confirm that the order of sentences will be shuffled; complete the second Profile independently and confirm that the two voiceprint do not overlap.
6. Check that the App sandbox is synchronized with the data and that it does not save the original recordings or sentences, but only the voiceprint template in the local Keychain.

Pass criteria: It must be completed with the real voice of a child in physical device. The local audio session should first configure and re-read the input format, and enable available voice processing and noise reduction during recording; rejected samples will not be included in the template.

## acceptanceSound and accessibility

1. Preview Lobby, Read, Write, results and Collection in each of the eight Worlds; complete at least one round for each, focusing on two rounds of Quests for five new Worlds.
2. Cold start listen to Aurora's single continuous offline short phrase `Ta-dá↗ woooords↘!` (approximately "It arrives, Walzi"): `da` Slightly lengthened upward and directly connected to the obviously lengthened and falling `wor`, no deliberate comma pause or synthetic seam; the background briefly returns without retransmission, and no dialogue is broadcast when Voice is turned off. The automatic transcription and connection timing have passed, and the pitch and listening quality still need physical device manual approval.
3. Confirm that Parent settings no longer have a voice style picker; all Profile use the same canonical teacher contract.
4. Test on devices without configured remote endpoints and without optional high-quality voice to confirm that the app chooses the installed clear-compatible fallback instead of mute; neither the client nor the logs should contain the provider API key.
5. In Write, listen to Katie's `of`, `at`, `cat`, `come`, `look` at 0.82×; after two mistakes in Read, click Hear to listen to the 0.90× version of Katie. Also listen to the `bun` Aurora quality override recorded in the manifest. Confirm that each word forms only one continuous clip, the pitch is natural, the speed is not too slow, and the trailing consonants in `f`, `t`, `k`, `n` are clear.
6. Answer at least seven words correctly in a row to confirm that there is an immediate correct sound effect for the current World every time. Aurora's six short celebrations will not repeat continuously; only the seventh time will it cycle. After completing the Quest, only one `Quest complete! Ta-da!` will be added, and any unfinished voiceovers will stop when entering the recording.
7. Check the two sides of the rainbow/unicorn in Moonpetal; check the dinosaur, fire and rescue, original blocks, ice and snow aurora and roller coaster elements in World separately when adding them; confirm that the central mission safe area is clear and that the elements do not cross theme leaks.
8. The music is lowered when the voice prompt is confirmed, Read The music and unnecessary sound effects are stopped when recording.
9. Test Voice, Music, Sound effects, Reduced Sound and Calm Rescue separately.
10. Test speakers, headphones, call interruption, background recovery, and volume changes
11. Open VoiceOver, walk through Profile, Lobby, Read, Write, results and Guardian
12. Turn on Reduce Motion with larger dynamic fonts to check the compact layout of the horizontal screen.

Pass criteria: Reduced Sound Retain necessary correct, retry and technical non-verbal prompts, but turn off decorative click, star, reward and Aurora transition voiceovers; Voice controls Katie/Aurora/Apple voiceovers separately. Calm Rescue Do not play emergency rhythm layers. Artificial approval of volume, fatigue, burst sound and female voice color.

## acceptanceDirection switching and local data

1. In iPhone 17 Pro Max and iPad's Profile, Lobby, Quest, Results and Collection tests Landscape Left and Landscape Right
2. Try rotating these child routes to Portrait and confirm that the full-screen landscape remains intact.
3. Enter Parents and set up the first parent: iPhone Verify Portrait + two Landscapes and refuse Upside Down; iPad Verify four directions
4. After holding the device vertically on the parent page, exit and confirm Profile/Lobby to immediately restore the landscape screen, without retaining the portrait screen.
5. Force exit after completing the file creation, word addition, setting and Quest.
6. Reopen and confirm that all data has been restored to the last Profile.

Historical simulator evidence recorded a tall/portrait iPad Parents page and a
landscape child Read page. The temporary screenshots were removed from source
control by the Issue #114 repository cleanup; their recorded observations
remain informational only and do not replace current device acceptance. iPhone
and iPad rotation still follow the acceptance steps above.

`Contents.json` Only describe Xcode assets. Running data is located in the Application Support directory of the App sandbox. The App does not have its own server database. `TadaWordsLocalQA` Installed as an independent **Tada Words QA**, without iCloud capabilities and data does not cross devices; normal releases will only be synchronized when parents explicitly enable it.

The specific word images use a fixed version of Twemoji 17.0.3 PNG and cache them in the App's private directory. The request only contains the Unicode asset filename of the built-in catalog, not the child's name, Profile ID, learning records, or the original words entered by parents. Words such as `the`, `come`, `kind`, etc., that are not in the specific word catalog must be returned directly without images and without network connection. The license and source records are recorded in `THIRD_PARTY_NOTICES.md`.

## Complete physical device Release acceptance

Before final release, it must pass the following items on a iPhone 17 Pro Max and a iPad:

- signingInstallation, cold start, background recovery and two horizontal screen directions
- Real children's voice, family noise, automatic recording stop, voiceprint fan fiction and non-fan fiction samples
- Finger, Apple Pencil, palm touch and four-year-old children's handwriting
- Camera and Photo Library permissions
- avatar of Camera / Photo Library and two uses of multi-picture word-sheet OCR, including a single picture 500 word limit, numbering and sticky Add All.
- VoiceOver, Reduce Motion and dynamic fonts
- Single canonical teacher voice/fallback, music for each World, ducking, volume and fatigue feeling
- Random sentence reading, refusal samples, completion of saving and voiceprint for each device independently in Voice setup
- Write's short dot/continuous stroke/follow-up stroke, 4× eraser, blank click to restore the pen, canvas fixed coordinates and no lag brush sound
- `FOLLOWUP_BUGFIXES_AND_IMPROVEMENTS.md` All device evidence in v0.3, and retain the unfinished physical device evidence that has been merged into v0.2.
- Two Apple ID CloudKit invitations, conflicts, offline recovery and deletion of broadcasts
- Family Sync is turned off by default, parental opt-in is persistent, and future synchronization is stopped after it is turned off.
- CloudKit Remote records erasure
- Local notification authorization, quiet hours and actual delivery

Only after these device items are approved can Device Alpha and the family be marked as acceptance.
<!-- TADA_BILINGUAL_ZH_START -->

---

<a id="简体中文版"></a>

> **翻译说明：** 英文为默认阅读语言；本文同时保留原始语言文本。如中英文内容存在差异，请以原始语言文本为准。

---
title: 如何验收 Tada Words V1
navLabel: V1 验收
contentType: How-to
category: Delivery
---

# 如何验收 Tada Words V1

这份清单用于验收当前 V1。先运行自动化检查和两种模拟器，再用真实 iPhone 与 iPad 验收麦克风、儿童语音、手写、辅助功能、音频、CloudKit 和通知。

## 先理解验收状态

每个项目使用以下一种状态：

- **代码已完成**：生产路径与自动化测试存在
- **模拟器已检查**：可验证导航、布局、状态和本地持久化
- **需要真机验收**：必须依赖真实硬件、儿童样本、Apple 账号或人工听感

代码或模拟器通过不代表儿童识别准确率、混音质量或 CloudKit 家庭共享已经通过。

## 运行自动化检查

在仓库根目录运行：

```sh
cd /path/to/tadawords
make generate
make check
./Scripts/verify-device-readiness.sh
```

通过标准：格式检查、单元与组合测试、iPhone 17 Pro Max LocalQA 模拟器构建、iPad Pro 13-inch (M5) LocalQA 模拟器构建全部通过。设备准备脚本可以在未配置签名 Team 时报告签名阻塞。

PR #2 已在 merge commit `cc42e17` 把 v0.3 合入 `main`。2026-07-14 的当前 v0.3.1 修复证据如下。V1 的 367 项、v0.2 的 480 项和 v0.3 的 548 项测试保留为历史基线；v0.3.1 全量为 595/595：

| 检查 | 结果 |
|---|---|
| Swift formatter 严格检查 | 通过 |
| Swift 单元与组合测试 | v0.3.1 全量 595/595 通过，0 failure；其中 actual-Vision 手写识别 focused suite 为 15/15，World 布局 focused suite 为 5/5 |
| Critical XCUITest | iPhone 17 Pro Max 模拟器 7/7 通过：Read/Write 连续反馈、两次删除/Undo、Delete All/完整恢复、Preset 明确批准后才加入、Photos 退出后排序、OCR Review → Add All → Pool → Sort |
| iPhone 17 Pro Max production Vision 真机测试 | iOS 26.5.1 上 2/2 XCTest 通过：`of/go` 六种大小写正例 6/6，错词与 literal `90` 负例 4/4；使用匿名合成 vector 和真实 production service，不使用 mock/demo |
| iPad Air 13-inch (M4) production Vision 真机测试 | iPadOS 26.5 上 2/2 DeviceTests 通过：wrong-word rejection 与 `of/go` case variants；使用真实 production service 与匿名合成 vector |
| iPad Air 13-inch (M4) Critical XCUITest | LocalQA 配置下 7/7 通过：OCR Add All、Delete All/完整恢复、Preset 明确批准、连续删除/排序、Photo picker/排序、Read 与 Write 完成反馈消失 |
| iPhone 17 Pro Max LocalQA 模拟器构建 | v0.3.1 fresh build 通过 |
| iPad Pro 13-inch (M5) LocalQA 模拟器构建 | v0.3.1 fresh build 通过 |
| iPhone 17 Pro Max 真机安装 | `Tada Words QA` v0.3.1 (`2026071402`) 签名构建已覆盖安装并启动；儿童真实书写、发音听感和辅助功能仍需人工验收 |
| iPad Air 13-inch (M4) 真机安装 | Darren iPad、iPadOS 26.5；Team `6S245NCUPQ` 签名的 `Tada Words QA` v0.3.1 (`2026071403`) 已安装并启动；儿童真实书写、发音听感、布局、旋转和辅助功能仍需人工验收 |
| 两个 built product 的方向声明 | v0.2 基线：iPhone 为 Portrait + 两个 Landscape；iPad 为四向；`UIRequiresFullScreen` 为 true；运行时 Parents 可旋转，child route 只允许横屏 |
| 模拟器方向证据 | v0.2 基线：iPad 的 Parent 与 child 窗口形态符合路由策略；iPhone raw framebuffer 截图方向不可靠，仍需真机旋转确认 |
| Release CloudKit 分享声明 | v0.2 基线：iPhone 与 iPad Release built product 的 `CKSharingSupported` 为 true |
| LocalQA 隔离声明 | v0.2 基线：`Tada Words QA` 使用独立 bundle ID、空 iCloud entitlement，且 `CKSharingSupported` 为 false |
| 儿童语音 fixture | v0.2 基线：SHA-256 通过，Apple 转写为 `Bye.`，App policy 对目标 `bye` 判定为匹配 |

### 当前 v0.7.0 Family Sync 证据

上表保留 v0.3.1 的历史交付记录。当前 v0.7.0 (`2026071806`) 另有以下证据：

| 检查 | 结果 |
|---|---|
| Swift formatter 严格检查 | 通过 |
| Swift 单元与组合测试 | 814/814 通过，0 failure；Issue Agent 14/14 通过 |
| Family Sync XCUITest | source batch：iPhone 17 Pro Max 6/6、iPad Pro 13-inch (M5) 6/6，iOS 26.5；merge 前必须对 exact committed HEAD 重跑 |
| Critical XCUITest | source batch：iPhone 17 Pro Max 10/10、iPad Pro 13-inch (M5) 10/10，iOS 26.5；exact committed HEAD 重跑是交付门槛 |
| Production CloudKit | Source contract 已完成；schema、签名真机 private/share、后台 push、owner/participant access management、远端删除和人工恢复文案仍待验收 |

`CKSharingSupported` 是构建声明，不代表模拟器正在运行 CloudKit。模拟器刻意使用 local/device-only transport；真实 CloudKit transport 只能在配置 Team、container 与 iCloud 的签名真机上验收。

iPad 的 DeviceTests 与 Critical XCUITest 证明 production 识别链路和七条关键交互能在真机运行。它们不替代儿童真实手写、标准发音听感、各方向布局、Apple Pencil、VoiceOver 或 Dynamic Type 的人工验收。

编号的 `.xcodeproj` 副本已经删除。只打开 `TadaWords.xcodeproj`，也不要使用方向或能力变更之前的 Derived Data。

## 核对关键需求

| 需求 | 当前状态 | 人工验收重点 |
|---|---|---|
| Read 与 Write 两条独立路线 | 代码已完成 | 两个 Today Quest 按钮不合并，数据与设置互不覆盖 |
| Parent Word Manager | v0.2 基础已合并；v0.3/v0.3.1 增强完成，待真机回归 | 单词 Return 即时加入；多照片 Camera/Photo OCR；逐词编号；单图 500 词上限；added/A-Z/most practiced 排序；频次；type-ahead 搜索；Hear/Delete；单删/批删/整组清空；删除确认与 Undo 按 Profile 隔离；两组独立去重 |
| 仅使用家长批准词 | v0.3.1 代码完成 | 无 smart fill / Grade 自动加入；typing、OCR 或 Preset 都必须由家长明确提交，Pool 不足时不补词 |
| 按年龄/年级的 Preset Words | v0.3.1 代码与内容审计完成，待真机布局回归 | 3–8 岁 / Pre-K–Grade 3；34 组、每组 40–45 词；最多 6 组推荐后按层级浏览；搜索、逐词/全选、Read/Write/Both；打开或推荐绝不自动加入 |
| New 与 Review 顺序可交换 | 代码已完成 | 每条路线独立保存顺序 |
| 艾宾浩斯复习与补弱 | 代码已完成 | 到期、错误、相对慢、重播和 Help 影响排序与记忆参数 |
| Write 不预显答案与一次引导重写 | v0.3 代码完成，待真机回归 | 每个词开始时只播发音，不显示拼写；只有点 `?` 才显示答案；第一次真实错答可出现具体词图片按钮 |
| Read 安静首答与两错后 Help | v0.3 代码完成，待真机回归 | 首答前不播答案；两次有效错答后只出现 Hear it；没有图片提示；技术失败不解锁也不耗次数 |
| 真正 Mastered 判定 | 代码已完成 | 三个不同本地日期独立成功，且未来 14 天预计回忆率达标 |
| 分数、宽松三颗星、严格 Guardian 证据 | v0.3 代码完成 | Accuracy 门槛 75%；一次无辅助立即恢复；校准 Pace；慢侧 50% 宽限；完美首答固定 100 分/3 星；技术性 Move On 显示 Not scored |
| 八个独立主题世界 | v0.2 代码完成，待真机视听回归 | 公主、工程车、动物、恐龙、消防救援、原创积木、冰雪与过山车的场景/奖励不混用 |
| 每个世界 20 个小奖励与 5 个里程碑 | v0.2 代码完成，待真机视觉回归 | 共 200 件不同图标；永久收藏品不因 Practice Again 重发 |
| Double Quest 次日 Theme / Icon | v0.2 代码完成，待真机回归 | 同日 Read+Write 的 Today run 次日解锁；partial/replay 不算；My Collection 可选择已获得项目 |
| 多 Kid Profile、年龄与上次 Profile | v0.3.1 代码完成，待真机回归 | 冷启动先到 Picker 并突出上次 Profile；首次/Kid/Parent 新建均采集 3–8 岁年龄；每个 Profile 数据、声纹、设置与 cosmetics 隔离 |
| Profile-first 首次流程 | v0.3.1 代码完成，待真机布局复验 | 无 Profile 直接 New Kid；先录昵称和年龄，首次流程无单词输入 |
| Pre-K 儿童端视觉层级 | v0.2 模拟器已检查，待儿童与辅助功能验收 | 上次 Profile 静态突出；iPhone Lobby 图标 dock 保留 72 pt 触控区；Read 主词与 Result 奖励更醒目；iPad 保留文字工具入口 |
| 自拍、照片、动物头像 | 代码已完成 | 真机检查 Camera 与 Photo Library 权限 |
| 月度打卡 Calendar | 代码已完成 | 每日显示准确 Quest 次数，Practice Again 也计数 |
| 7 日与 30 日报告 | 代码已完成 | 检查趋势、单词详情、识别纠正和 CSV 导出 |
| Crash-resumable Profile 删除 | 代码已完成 | 删除本地资料、单词、历史、奖励、提醒和本机声纹 |
| 本地通知与安静时段 | 代码已完成 | 每日、Pool low、完成、同步失败、周报与时间设置 |
| CloudKit 同步与家庭邀请 | v0.7.0 source：版本化 CKSyncEngine、完整 Profile 数据、事件重算、耐崩溃 apply 与远端删除语义已实现；生产验收未完成 | 用付费 Developer Team、production schema、两个设备与两个 Apple 账号验收 private/share、后台 push、离线合并和 test-only 远端擦除；通过前不可发布该能力 |
| 1 分钟声纹注册与 Read 匹配 | v0.3 跟读流程完成，需要儿童样本校准 | 随机短句逐句播放、儿童跟读、拒绝样本可重录；声纹只存本机 Keychain，原始录音不保存或同步 |
| Apple Pencil 与掌触过滤 | 代码已完成，需要真机验收 | iPhone 用手指，iPad 分别测试手指与 Pencil |
| VoiceOver、Reduce Motion、动态字体 | 代码已完成，需要真机验收 | 完整走查反馈播报、焦点、横屏紧凑高度 |
| 单一教师契约与主题音乐 | Katie/Aurora 离线包已实现并通过 bundle/转写检查；需要真机人工听感批准 | 不提供 Profile voice style；500 词以 Katie Read 0.90× / Write 0.82× 双版本为 canonical，`bun` 使用 manifest 记录的 Aurora 质量例外，包外词使用 Apple fallback；Aurora 负责连续启动短句 `Ta-dá↗ woooords↘!`、六条答对微庆祝和 Quest 完成；客户端不存 provider key；Moonpetal 彩虹/独角兽与欢快音乐 |
| 八个原创 World | v0.2 代码完成，待真机视听回归 | 新增 Dino、Firehouse、Brickwork、Frostlight、Coaster；每个拥有隔离场景、吉祥物、颜色、奖励与音乐 |
| Write 笔盒与稳定画布 | v0.2 笔盒基础已合并；v0.3 增强完成，待真机书写回归 | Pencil/Chalk/Brush 三种黑色笔、每 Profile 持久化、流畅笔触音效、4× 局部擦除、空白点击恢复原笔、画布加宽 10%；root Quest transition identity 保持稳定，切词/反馈时坐标不移动 |
| 具体词图片提示 | v0.3 代码完成，待真机网络/离线回归 | 入 Pool 后异步缓存固定 Twemoji 资源；Write 首次真实错答显示可点击图片；`the` 等抽象/功能词不请求图片 |
| Parent Gate 与 Lock | v0.3 代码完成，待真机回归 | 输入完整位数后自动判题；错误时立即重置但反馈保持到下一次输入；Parents 的 Lock 直接返回 Kids 页面 |
| Treasure 图标与头像 | v0.2 代码完成，待真机回归 | 8×25 个相关图标；locked 保留灰色图标加锁；collected treasure 可选为头像且保留原照片 |

## 理解分数与单词发音

儿童结果页使用以下规则。Guardian 报告仍显示严格的第一次独立作答，不把补答改写成首答正确。

| 项目 | 规则 |
|---|---|
| Completion Star | 完成计划中的全部单词 |
| Accuracy Star | 第一次独立作答正确率达到 75%，或整轮只错一个词且紧接着在无提示情况下答对 |
| Personal Pace Star | 已获得 Accuracy，且速度落在个人区间、仍处于有效校准期，或整轮完美首答 |
| Points | 正确率最多 80 分，速度最多 20 分 |
| Perfect first try | 无论是否已有速度基线，固定 100 分和 3 星 |

家长可以手输、照片批量导入，或从本地 Preset Catalog 明确选择单词。所有新词统一使用 canonical isolated teacher pronunciation；Parent UI 不提供语境句或多发音编辑入口。年龄/年级只排序推荐，不会自动加入。旧版本中已经保存的 contextual audio metadata 仍可被读取，避免升级时损坏数据。

## 验收 Kid Profile 与 Guardian

1. 清空 LocalQA 数据后启动；第一屏必须是 `New Kid`，且不出现单词输入
2. 阅读并接受版本化隐私说明，创建昵称、3–8 岁年龄、动物头像、Grade 和起始 World
3. 强制退出并重启；Profile Picker 必须突出上次有效 Profile，孩子点击后才进入 Lobby
4. 新建第二个 Profile，为两者输入不同单词与设置，再验证 Picker 和隔离
5. 普通单击 **Parents**，确认随机算术 Parent Gate 立即出现；输入完整位数后无需点 Unlock 即自动判题。错误答案自动清空，但错误提示保持可见，直到家长开始输入下一次答案
6. 让孩子在 Picker 自建第二个 Profile，输入昵称与年龄；确认建议 Grade 合理。再进入 Parents 编辑 Profile，验证家长改变年龄不会静默覆盖明确选择的 Grade，并从 Camera 自拍、Photo Library 和动物图标各测试一次头像来源
7. 从 Parent dashboard 点 **Lock**，确认立即锁定并返回 Kids Profile Picker
8. 删除上次使用的非唯一 Profile；重启后必须回到合法 Picker，不猜测身份或复活数据

通过标准：每个 Profile 隔离单词、设置、学习记录、日历、奖励和声纹。所有新 Profile 都保存有效年龄；旧版缺年龄 Profile 仍可读取。敏感操作需要系统设备认证。App 必须保留至少一个 Profile。Onboarding 不请求麦克风、Speech、Camera、Photo Library 或通知权限；相关权限只在对应功能首次使用时请求。

## 验收 Parent Word Manager

1. 切到 Read Tab，输入 `the` 并按 Return；确认立即保存、输入框清空且 `the` 出现在最顶部
2. 依次输入 `look`、`play`；确认始终 newest-first，同 Pool 再输 `the` 不复制历史而是前移
3. 切到 Write Tab 输入 `the`；确认 Read/Write 两组可以各有同名词
4. 从 Photo Library 一次选择至少两张 school list；再用 **Add photos** 和 **Take another** 追加图片，确认识别结果合并到同一预览
5. 核对每个 OCR 词从 1 开始编号；编辑或删除误识别项，并分别切换 Added order、A-Z、Most practiced
6. 准备一张超过 500 个识别词的单图，确认该图片被明确拒绝并提示更换图片；其他未超限图片的结果不丢失
7. 滚动长预览，验证顶部返回/到顶按钮与到底按钮；点 **Add all N to Read/Write**，确认按钮不会被键盘遮住、只提交一次，并显示保存进度或明确错误
8. 在 Pool 切换 Added order、A-Z、Most practiced，核对每行频次数字；用 type-ahead 搜索并直接点该行的 Hear 与 Delete
9. 第一次删除时确认弹窗出现；确认后继续单删和批删，确认本 Parent session 不再重复弹窗且 Undo 仍可用
10. 分别在 Read 和 Write 点 `Delete all N words`：取消一次，再确认一次；核对明确数量/模式、另一 Pool 不变、学习历史不删，并用 Undo 完整恢复
11. 在 Profile A 删除或清空后切换到 Profile B；确认 B 不继承 A 的首次删除确认状态或 Undo，且 B 的操作不能还原或修改 A 的 Pool
12. 从 Today 打开 Preset Words；核对最多 6 个年龄/年级匹配推荐，再逐层浏览 Sight Words、Phonics、动物/恐龙/车辆/城市/国家、动作和 Emotions。打开列表时 Pool 不变；逐词选择或 Select all，分别提交到 Read、Write、Both 并核对去重
13. 对 Both 导入核对事务边界：正常时两个 Pool 都更新；任一 Pool 保存失败、部分成功或返回数量不符时，只回滚本次插入或重新启用的 membership，既有 active word 与另一 Profile 不变
14. 在 typing、search 和 OCR 文字编辑框中输入文字，再点空白处；确认键盘收起；整个流程不出现 pronunciation/context section
15. 清空或缩小 Pool，重启并准备 Quest；确认不会出现未经家长点击 Add 的 catalog 或 smart-fill 新词

通过标准：所有 Pool 新增项均能追溯到 typing、OCR 或家长明确批准的 Preset selection；原始 school-list 图片只在本机识别且不保存。每张图片独立执行 500 词上限。Preset 与删除操作绑定发起它的 Profile，Both 导入不会留下半完成状态。键盘、OCR sheet、sticky Add All、Preset 层级和选择工具栏在 iPhone/iPad 横竖屏 Parent route 均不裁切。

## 验收 Read Quest

1. 点独立的 **Read Today's Quest**
2. 用全新 Profile/新词进入；确认目标出现时完全不播放发音
3. 首次点 Mic 时允许 Microphone 与 Speech Recognition；权限等待不算孩子速度
4. 读出目标词，确认正确反馈与结果记录
5. 第一次读错后确认 **Hear it** 隐藏；第二次有效读错后确认只出现 **Hear it**，没有图片按钮
6. 点 **Hear it**，确认只因孩子点按才播放；发音必须清晰、连贯且不吃尾音，切换到下一个词后帮助重新隐藏
7. 制造无声、噪声、技术失败，确认不耗有效尝试、不扣正确率、不提前解锁 Help；连续三次技术失败可中性 Move On
8. 测试 `a`、`I`、`go`、`look`、`bye`（包括 Apple 句末标点转写）和 0.8 秒自然停顿
9. 测试目标 `come` 的儿童近音 `kum/cum` 可通过，同时 `some`、`home`、`came`、`cat/cap` 不被误放宽
10. 建立声纹后，让目标儿童和另一位说话者分别测试
11. 连续切换多个词，确认大字始终使用当前 World 对应的同一种深色；只有切换 World 才改变颜色，并始终清晰可读
12. 完成一轮，其中故意答错或使用帮助；在 Result 点 Replay，确认只重练本轮 tricky words。完美一轮不显示空 Replay 按钮

通过标准：技术失败不进入学习证据。声纹不匹配走技术重试，不把另一位说话者记成孩子答错。真实家庭噪声、自动停录、回声消除与识别准确率只能在真机验收。

## 验收 Write Quest

1. 点独立的 **Write Today's Quest**
2. 对 New 与 Review 词都确认只播放发音，不预先显示任何拼写；只有点 `?` 后才显示目标词
3. 试听 Katie Write 版 `of`、`at`、`cat`、`come`、`look`，确认使用 0.82× 离线录音且仍是一段连续、清晰的发音；`f`、`t`、`k` 等尾音没有被背景音乐、外部音频或 audio session 吞掉，播放结束后音乐平滑恢复。再输入一个 500 词 manifest 外的词，确认 Apple fallback 可用
4. 在加宽后的横线区独立手写整个单词，再点 **Done**；确认 App 不会因停笔自动提交
5. 分别写 `i` 的点、三字母词的最后一个字母，以及连笔 `vv`/`w`；确认短点、后续笔画和连笔都留下
6. 分别用首字母大写、全大写和全小写书写同一个词；确认大小写差异不导致失败
7. 测试 **Hear**、单独的 **?**、**Clear** 与 **Done**；`?` 必须立即显示单词且没有三选一，Clear 不弹确认
8. 第一次真实写错 `dog`，确认出现可点击图片按钮且不会自动显示拼写；点图片后显示狗。对 `the` 写错时不显示图片，也不发起图片请求
9. 制造识别不确定和技术失败，确认不计成孩子答错，也不会错误触发图片
10. 在 iPad 分别用手指与 Apple Pencil 书写，并把手掌放到屏幕上
11. 开启 Left-handed writing，确认主操作栏换边
12. 打开笔盒，确认只有 Pencil、Chalk、Brush 与 Eraser；没有 Crayon 或颜色选择，所有新笔画均为黑色
13. 切换到一个 Profile 选择笔型，重启并切换 Profile；确认每个 Profile 保留自己的选择，直到再次修改；旧版 Crayon/彩色设置安全迁移为黑色 Pencil
14. 逐笔书写并试听三种短促书写音；确认快速连续移动没有爆音、卡顿或频繁重启音，发音播放和 Reduced Sound 时不叠加
15. 确认页面没有 Undo；用 Eraser 对每种笔做局部擦除，擦除宽度约为当前笔宽 4 倍。擦完后点旁边空白，确认自动恢复之前的笔
16. 不使用 Help，分别写 `of`、`Of`、`OF`、`go`、`Go`、`GO`，每种写法重复两次并要求 12/12 通过；再确认 `if`、`on`、`or`、`ot`、`off`、`do`、`no` 与数字 `90` 不能误过
17. 在错误反馈出现及切换下一个词时录屏，逐帧确认书写区域的尺寸、中心和坐标不移动；确认整轮 Quest 的 root transition identity 不随 prompt 改变；完成反馈至少停留 830 ms，不再闪过
18. 完成一轮并故意留下 tricky word；在 Result 点 Replay，确认只重练该词

通过标准：Hear、`?`、识别等待和技术重试时间不污染独立作答速度。三种笔的视觉和声音可区分但不盖住发音。图片只服务具体词并使用私有缓存。iPhone 只提示手指，iPad 可以区分 Pencil 与手指，并过滤明显掌触。合成笔画的 production Vision 真机测试只证明修复链路与已知字形，不能替代上述孩子 12 次真实书写。

## 验收 Review、Mastered 与今日计划

1. 分别设置 New first 与 Review first
2. 在 New-first 路线故意答错新词，确认它替换最低优先 Review，并保留 Review debt
3. 确认 Review 会补入到期词，也会补入未到期但明显薄弱的词
4. 重复输入一个已学词，确认它在 Review 中前移
5. 跨三个不同日期独立答对同一词
6. 确认只有达到三日成功与 14 日预计回忆率门槛后才显示 Mastered

通过标准：同一天重复成功不能凑满三日条件。Help、重播、错误与相对个人慢会降低稳定度或提高难度。

## 验收奖励、世界与 Calendar

1. 分别完成 Read 与 Write Today Quest
2. 完成一次所有词均首答正确的 Quest；确认结果为 100 分和 3 星，即使 Profile 尚无速度基线
3. 制造 75% 第一次独立正确率，确认仍有 Accuracy Star；再制造整轮仅一次错答并立即无提示答对，确认儿童奖励可获宽限，而 Guardian 仍显示原始首答正确率
4. 在已有个人速度区间后，验证慢侧最多 50% 宽限；过快或超过宽限不获得 Pace Star
5. 确认结果页显示分数、星星、正确率、个人速度和当前世界奖励
6. 完成 Practice Again，确认 Calendar 次数增加，但不重复发当天永久奖励
7. 第一天只完成 Read，确认当天和第二天均不解锁 Theme/Icon
8. 同一本地日完成 Read 与 Write Today Quest；当天仍锁定，跨到第二天或用可控时钟重启后各解锁一个未获得 Theme 与 Icon
9. 完成 Practice Again 与重复完成，确认不触发或重复解锁；测试月末到次月的跨日
10. 打开 My Collection，分别选择已获得 Theme 与 Icon，重启后保留；locked 项只可预览
11. 核对 8 个 World 各自的 20 个小奖励与 5 个里程碑；每件图标相关且同 World 不重复，locked 时仍显示灰色原图标并叠加锁
12. 选择一个已收集 Treasure 作为 Profile 头像，确认 Picker/Lobby 一致；点击未收集 Treasure 不生效
13. 若 Profile 原头像为照片，依次切换动物 Icon、Treasure 头像和原照片，确认照片数据始终保留可恢复
14. 在同一天完成多次 Quest，确认儿童 Calendar 与 Guardian Today 显示相同数量

通过标准：每个 World 只出现自己的奖励。世界解锁与收藏进度按 Profile 隔离并在重启后保留。

## 验收 Guardian 报告与纠正

1. 打开 Guardian 的 **Reports**
2. 在 7 days 与 30 days 之间切换
3. 检查完成数、正确率、个人速度趋势与单词详情
4. 把一条识别结果从错误改为正确，再改回错误
5. 确认学习进度从事件历史重建，报告与 Needs Attention 同步更新
6. 通过系统认证后导出 CSV，并检查字段和 Profile 范围

通过标准：纠正不直接覆盖汇总快照。App 使用原始 attempt 与 correction event 重建当前进度。

## 验收通知

1. 在 Practice settings 打开每日提醒、Pool low、完成、同步失败和周报
2. 修改每日提醒时间与安静时段起止
3. 允许系统通知权限
4. 确认安静时段内的提醒移动到允许时间
5. 关闭全部通知，确认该 Profile 的待发通知被清除

通过标准：通知文案不包含孩子的单词、分数或敏感学习详情。不同 Profile 的通知使用稳定且互不覆盖的标识符。

## 验收 CloudKit 家庭同步

这部分必须使用已配置 `iCloud.com.tadawords.app` 的 Apple Developer Team。准备两个登录不同 Apple ID 的设备。

Release 的 Family Sync 默认关闭并持久保存。Onboarding 的隐私确认不会开启 CloudKit；只有家长在 Guardian 中明确开启后，启动、生命周期、手动同步和邀请才可以接触 CloudKit。关闭开关会停止未来同步，但按设计不会删除已经上传的 records；Profile 删除才会先写入最小 deletion ledger，再擦除 Profile zone、children、assets、root 与 share。该 source 语义不能替代 production CloudKit 证据；本节只使用 test-only Profile，且在全部真机门禁通过前不能把 Family Sync 作为已验收功能。

1. 首次启动与完成 onboarding 后，确认 **Family sync** 显示关闭，且没有 CloudKit 请求
2. 在设备 A 创建 Profile、单词、设置与学习记录
3. 通过家长认证明确开启 Family Sync，再点 **Sync now**
4. 创建家庭邀请，并通过系统 Share Sheet 发给设备 B
5. 在设备 B 明确开启并接受邀请，然后同步
6. 作为 owner 和 participant 分别打开系统 Family access 管理页；owner 移除 participant、participant Leave、再做 revocation，确认 App 回到 terminal 状态且绝不静默建立 private fallback
7. 确认 Profile/头像、两个 Pool、六组设置、attempt/correction、Ebbinghaus 进度、日计划、完成、Calendar、World、Badge、Collection 和奖励一致；两台设备的声纹与 cache 保持各自本地
8. 关闭 Family Sync，确认后续启动、前后台切换、手动按钮、邀请与 access management 不再调用 CloudKit，本地 Quest 继续可用
9. 再开启后，两台设备离线修改不同记录，再联网同步
10. 删除一个 test-only Profile，确认另一台离线设备先收到 ledger、清除本地资料且不能复活；在 CloudKit Dashboard/测试工具中确认除最小 ledger 外的 records、asset、share 与 zone 已擦除
11. 在 push、fetch 或 apply 中途强制退出并重启，确认 exact pending batch 被恢复一次、UI 自动刷新且不会重复 completion/reward
12. 断网完成 Quest，确认本地学习不受同步失败影响；Parent 页面在重启后仍准确显示 pending 数、连接/账号状态、重试与最近成功时间

通过标准：Quest 提交不等待 CloudKit；同一 canonical facts 在不同到达顺序下收敛一致且不重复。同步失败显示真实可恢复状态并保留本地数据。删除不可复活。声纹模板不进入 CloudKit；每台设备单独注册声纹。记录 exact commit、version/build、Team/container、schema environment、设备/系统、账号角色与证据路径。

## 验收 Voice setup

1. 在一个 Kid Profile 中打开 **Voice setup**，确认出现一条短英文句子并自动播放，孩子可以再次点 Hear
2. 让孩子跟读并录制；确认成功样本增加进度，再用静音、太短和明显噪声制造拒绝，确认显示可重试原因且已接受进度不丢失
3. 完成至少六个有效片段与最低有效语音时长；确认 **Finish setup** 只在条件满足后可用，并能保存后退出
4. 中断录音、锁屏或切到后台后返回；确认不会出现永久灰色 Finish、零采样率或通用错误循环
5. 新开一次 setup，确认句子顺序会洗牌；在第二个 Profile 独立完成，确认两个声纹互不覆盖
6. 检查 App 沙盒与同步数据，确认不保存原始录音或句子，只在本机 Keychain 保存声纹模板

通过标准：必须用真实儿童声音在真机完成。本机音频 session 应先配置再读取输入格式，并在录音时启用可用的语音处理与降噪；拒绝样本不计入模板。

## 验收声音与辅助功能

1. 在八个 World 中分别预览 Lobby、Read、Write、结果与 Collection；每个至少完成一轮，重点抽查五个新增 World 的两轮 Quest
2. 冷启动试听 Aurora 的单个连续离线短句 `Ta-dá↗ woooords↘!`（近似“它达，沃尔子”）：`da` 略拉长上扬并直接连入明显拉长、下落的 `wor`，不得有刻意逗号停顿或合成接缝；后台短暂返回不重播，Voice 关闭时不播口白。自动转写与连接时序已通过，音高和听感仍需真机人工批准
3. 确认 Parent settings 不再有 voice style picker；所有 Profile 使用同一个 canonical teacher contract
4. 在未配置远端 endpoint 及缺少可选高质量 voice 的设备上测试，确认 App 选用已安装的清晰兼容 fallback 而不是静音；客户端和日志都不得包含 provider API key
5. 在 Write 试听 Katie 0.82× 的 `of`、`at`、`cat`、`come`、`look`；在 Read 两错后点按 Hear 试听 Katie 0.90× 版本。另试听 manifest 记录的 `bun` Aurora quality override。确认每个词只形成一个连续 clip、音高自然、速度不过慢，`f`、`t`、`k`、`n` 等尾音清楚
6. 连续答对至少七个词，确认每次都有当前 World 的即时正确音效，Aurora 六条短庆祝不会连续重复；第七次才循环。完成 Quest 后只追加一次 `Quest complete! Ta-da!`，进入录音时任何未结束口播都会停止
7. 在 Moonpetal 检查两侧彩虹/独角兽；在新增 World 分别检查恐龙、消防救援、原创积木、冰雪极光和过山车元素；确认中央任务安全区清晰且元素不跨主题泄漏
8. 确认语音提示时音乐降低，Read 录音时音乐和非必要音效停止
9. 分别测试 Voice、Music、Sound effects、Reduced Sound 和 Calm Rescue
10. 测试扬声器、耳机、来电打断、后台恢复和音量变化
11. 开启 VoiceOver，走完 Profile、Lobby、Read、Write、结果和 Guardian
12. 开启 Reduce Motion 与较大动态字体，检查横屏紧凑布局

通过标准：Reduced Sound 保留必要的正确、重试和技术非语言提示，但关闭装饰性 click、star、reward 与 Aurora transition 口播；Voice 单独控制 Katie/Aurora/Apple 口播。Calm Rescue 不播放紧急节奏层。人工批准响度、疲劳感、爆音和女声音色。

## 验收方向切换和本地数据

1. 在 iPhone 17 Pro Max 与 iPad 的 Profile、Lobby、Quest、结果和 Collection 测试 Landscape Left 和 Landscape Right
2. 在这些 child route 尝试旋转到 Portrait，确认仍保持横屏全屏
3. 进入 Parents 与首次家长设置：iPhone 验证 Portrait + 两个 Landscape 且拒绝 Upside Down；iPad 验证四向
4. 在家长页面竖持设备后退出，确认 Profile/Lobby 立即恢复横屏，不保留竖屏
5. 完成建档、加词、设置和 Quest 后强制退出
6. 重新打开，确认所有数据与上次 Profile 恢复

历史模拟器验收曾确认：iPad 的首次 Parents 页面使用 tall/portrait window，child Read 使用 landscape window；临时截图已由 Issue #114 仓库清理删除。iPhone raw framebuffer 的方向仍有歧义，不作为竖屏通过证据。iPhone 与 iPad 的真机旋转仍按上述步骤验收。

`Contents.json` 只描述 Xcode 资产。运行数据位于 App 沙盒的 Application Support 目录。App 没有自建服务器数据库。`TadaWordsLocalQA` 安装为独立的 **Tada Words QA**，没有 iCloud 能力且数据不跨设备；正常 Release 也只有在家长明确开启后才会同步。

具体词图片使用固定版本的 Twemoji 17.0.3 PNG，并缓存到 App 私有目录。请求只包含内置 catalog 的 Unicode asset filename，不包含孩子姓名、Profile ID、学习记录或家长输入的原词。`the`、`come`、`kind` 等不在具体词 catalog 中的词必须直接返回无图片且不联网。许可证与来源记录在 `THIRD_PARTY_NOTICES.md`。

## 完成真机发布验收

最终发布前必须在一台 iPhone 17 Pro Max 与一台 iPad 上通过以下项目：

- 签名安装、冷启动、后台恢复和两个横屏方向
- 真实儿童语音、家庭噪声、自动停录、声纹同人与异人样本
- 手指、Apple Pencil、掌触和四岁儿童字形
- Camera 与 Photo Library 权限
- Camera / Photo Library 的头像与多图片 word-sheet OCR 两种用途，包括单图 500 词上限、编号和 sticky Add All
- VoiceOver、Reduce Motion 与动态字体
- 单一 canonical teacher voice/fallback、每个 World 的音乐、ducking、响度和疲劳感
- Voice setup 的随机句跟读、拒绝样本、完成保存和每设备独立声纹
- Write 的短点/连笔/后续笔画、4× 橡皮、空白点击恢复笔、画布固定坐标和无卡顿笔触音
- `FOLLOWUP_BUGFIXES_AND_IMPROVEMENTS.md` 中 v0.3 全部 device evidence，并保留已合并 v0.2 的未完成真机证据
- 两个 Apple ID 的 CloudKit 邀请、冲突、离线恢复和删除传播
- Family Sync 默认关闭、家长 opt-in 持久化、关闭后停止未来同步
- CloudKit 远端 records 擦除
- 本地通知授权、安静时段与实际投递

只有这些设备项目通过后，才能把 Device Alpha 和家庭同步标记为已验收。
