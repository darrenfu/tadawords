<!-- TADA_BILINGUAL_DOC: English is the default reading language. The original source text is preserved for verification. -->
<a id="english-default"></a>

> **Languages / 语言：** **English (default) / 英文（默认）** · [简体中文](#简体中文版)

# Tada Words — V1 Product and Interaction Design

> Status: v0.3.1 iPhone production Vision physical device testing, and iPad production/UI physical-device automation regression have been completed; children's handwriting, audio listening quality, layout and accessibility are still pending manual acceptance
>
> Project name: **Tada Words**
>
> Target version: private family beta / TestFlight V1

## 1. Product definition

Tada Words is an English sight-word learning app for preschool children. Each day, a Guardian enters or selects separate sets of words the child needs to read and write. The child practices them through two independent themed quests, with the goals of:

- **Read**: After seeing the word, you can read it independently.
- **Write**: After hearing only the canonical pronunciation, write the complete word independently.

The first target user is a 4-year-old child who is about to enter Pre-K, is a native Chinese speaker, and is learning English in an American classroom. She already knows and can write uppercase and lowercase letters and is starting phonics and sight words.

### V1 product commitments

- Read and Write are two independent learning routes, and they are not merged into one round of tasks.
- The interfaces of Kid and Guardian in V1 are only in English; this document uses Chinese only for convenience in design communication.
- Kid Quest mainly relies on graphics, sound and animation guidance, and does not provide Chinese prompts.
- Learning centers on genuine recall: Read requires speaking, and Write requires writing.
- The app can identify and schedule practice, but it can't punish a child for an uncertain identification.
- Game rewards enhance continuous practice, but do not replace learning goals.
- Data remains consistent across multiple Kid Profiles, multiple Guardians, and multiple devices.

### Out of scope for V1

- Do not automatically populate a Read or Write Pool by grade. The offline V1 Preset Catalog supports sorting, browsing, and search, but a Guardian must explicitly select and submit words. An automatic curriculum mode belongs in V2.
- Do not add extra mini-games such as Read matching or choosing a word from audio.
- No social media, children's rankings, advertisements, card draws or random treasure chests.
- Do not save or upload any original practice recordings.
- No commitment to professional phoneme-level pronunciation scoring; V1 judges whether the child can read the target words independently.
- Do not copy the melodies, sounds, character voiceovers, samples, and sound assets of Todo Math or other products.

## 2. Users and permissions

| Role | Ability |
|---|---|
| Owner Guardian | Create the family, invite Guardians, create and delete Kid Profiles, and manage all data |
| Guardian | Type, scan with OCR, or select Preset words; adjust settings; view reports; manage voiceprints and themes |
| Kid Profile | Choose an avatar, complete Quests, and view collections and Worlds |

In V1, a Kid is an in-app Profile, not a CloudKit member who needs a separate Apple ID. The child uses devices where a Guardian is signed in to iCloud; invited Guardians can share the same Kid Profile.

### Kid Profile Minimum information

- nickname
- avatar
- current grade
- Age; every new Profile must explicitly select an age from 3–8, while legacy Profiles with no age remain readable
- child voiceprint template

Do not collect real names, complete birthdays, school or teacher information.

Avatar sources:

- Selfie with front camera
- Select existing photos from the album
- built-in cute animal icons

## 3. Platform and screen orientation

V1 is Universal iOS App.

### Required acceptance devices

- iPad
- iPhone 17 Pro Max

Other iPhones receive a best-effort responsive layout but do not block the V1 release.

### Current physical-device automation evidence

On 2026-07-14, `Tada Words QA` v0.3.1 (`2026071403`), signed by Team `6S245NCUPQ`, was installed and launched on Darren's iPad Air 13-inch (M4) running iPadOS 26.5. Production DeviceTests passed 2/2, covering wrong-word rejection and `of/go` case variants. LocalQA Critical XCUITest passed 7/7, covering OCR Add All, Delete All/full restore, explicit Preset approval, repeated deletion/sorting, Photo picker/sorting, and dismissal of Read/Write completion feedback.

This evidence verifies that the production recognition path and critical interactions run on a physical iPad. It does not replace acceptance with real child handwriting, pronunciation listening quality, supported orientations, Apple Pencil, VoiceOver, or Dynamic Type.

### orientation rules

- Profile Picker, World Lobby, Kid Quest, Results, and Collection support only `Landscape Left` and `Landscape Right`.
- `Parents`, Parent Gate, Guardian management, and initial parent setup support portrait and landscape.
- iPhone parent routes support Portrait and both Landscape orientations, but not Portrait Upside Down; iPad parent routes support all four orientations.
- After leaving a parent route, the App must immediately restore landscape through a route-level geometry update; both child-route landscape orientations require acceptance.
- iPhone Kid Quest will reduce background decoration and prioritize ensuring large words, microphones and complete writing areas.
- Kid The large story decorations in Lobby are fixed to the seat belts at the bottom left and right. The coordinates of the foreground Quest cards and buttons do not move; the decoration animation can only float down from the seat belt baseline and cannot float up back to the card shadow. The Moonpetal unicorn in the iPhone most compact frame of the horizontal screen must also retain a visible background gap with the Write card, and any decorations in the World cannot be cropped at the bottom or sides.

Write supports finger input. Apple Pencil is enabled only on compatible devices and uses palm rejection. Apple's current Pencil-compatible devices are iPads, so Write uses finger input on iPhone 17 Pro Max. [Apple Pencil compatibility](https://support.apple.com/en-am/108937)

## 4. Information architecture

```text
App Launch
├── Profile Picker
│   ├── New Kid (unfold directly when Profile is not available; the child enters nickname and age)
│   ├── Last time Profile (highlighted when Profile is available, the child clicks to confirm)
│   └── World Lobby
│       ├── Read Today’s Quest
│       ├── Write Today’s Quest
│       ├── Practice Again
│       ├── Quest Calendar
│       ├── My Collection (select the Theme / Icon that has been obtained)
│       └── Treasure Collection
└── Parent Gate
    ├── Today
    ├── Words
    │   ├── Read Pool：Type / Camera / Photo / Select / Delete
    │   └── Write Pool：Type / Camera / Photo / Select / Delete
    ├── Preset Words (browse by age, grade and fine classification; only added after parents make a clear choice)
    ├── Reports
    ├── Profiles & Family
    ├── Worlds
    └── Settings
```

There are only three choices for the fixed mental model on the child's side:

1. Who am I?
2. Today Read or Write?
3. Which unlocked world adventure are you in?

The App only arranges New, Review, difficult words backflow and timing from the words that have been clearly approved to enter the Pool from Guardian. The source can be manual input, OCR, or words actively selected by parents in the built-in Preset Catalog; age and grade only change the recommended sorting, and no catalog or generation model can automatically add practice words.

## 5. First setting

The first launch must first process Profile, and no words are required to be entered first:

1. There is already Profile: display the Picker and highlight the last used valid Profile; the child enters after clicking.
2. No Profile: Display `New Kid` directly, enter nickname and age, and select avatar, grade and Starter World. V1 The new range is 3–8 years old, corresponding to Pre-K–Grade 3; the old Profile missing age can still be read.
3. Read and agree to the rules for children voiceprint, synchronization and deletion.
4. voiceprint Registration, word entry and notification can all be completed later in Parents without blocking the first entry into Kid Lobby.

### One minute voiceprint registration

- The app plays 8–10 very simple words in sequence.
- The child just needs to read along, and does not require himself to recognize these words.
- Collect multiple feature samples under quiet and slight background noise of the family.
- The original registered audio is deleted immediately after the generation of features.
- Only the encrypted voiceprint feature templates and model versions are saved.
- Guardian It can be deleted or re-registered.
- When you have a cold, grow up, or lose trust, the App reminds you to Guardian re-register, but it won't lock learning.

voiceprint is only used to filter whether "is this child speaking now" and is not used as a secure login or identity authentication.

## 6. Profile Picker

```text
┌──────────────────────────────────────────────────────────┐
│ Tada Words                                       Parents │
│                                                          │
│       ( Panda )        ( Bunny )        ( Photo )         │
│         Mia              Leo              Addy            │
│                                                          │
│                    “Who’s playing?”                       │
└──────────────────────────────────────────────────────────┘
```

- Use large avatar cards of 96 pt or more for each Profile.
- The child should click on his own avatar first; the App does not rely on voiceprint to automatically switch to Profile.
- The app remembers the last used valid Profile; next cold start highlights this Profile in the Picker, but the child still clicks to confirm. If this Profile no longer exists, the normal Picker is displayed, and no other identity is guessed.
- Last time Profile used static 1.03× size to stand out with higher stacking levels; other Profile did not reduce transparency or use continuous animation.
- Picker provides `New Kid` cards. The child enters nickname and clearly selects the age of 3-8 years old; the App gives current Grade recommendations based on age, and automatically assigns built-in animals avatar and Starter World. The complete editing is still completed by Guardian.
- Read When recording, voiceprint filtering other speakers is only used when Profile is selected.
- `Parents` The entrance is located in the stable upper right corner, and after a normal click, it immediately enters Random Arithmetic Parent Gate, not competing for attention with the main entrance of Quest.

## 7. World Lobby

```text
┌──────────────────────────────────────────────────────────┐
│ (Mia)                                 My Collection Parents│
│                                                          │
│                 [Current World Interactive Scene]│
│                                                          │
│   ┌────────────────────┐  ┌────────────────────┐         │
│   │  Read Today’s      │  │  Write Today’s     │         │
│   │      Quest         │  │       Quest        │         │
│   │   ☆  ☆  ☆          │  │    ☆  ☆  ☆         │         │
│   └────────────────────┘  └────────────────────┘         │
└──────────────────────────────────────────────────────────┘
```

Hard rules:

- Two separate large entrances must always be displayed.
- The "Comprehensive Today's Quest" that combines Read and Write is not provided.
- Currently, World is full-screen background, but the Quest card position does not change with the theme.
- Header doesn't repeat clickable World name capsules; it's easy to mistake them for buttons. The current theme is expressed by whole-page scenes and My Collection selection states.
- The completed entrance displays the score and stars for the day and provides `Practice Again`.
- Practice Again The memory model will be updated, but permanent collections issued on the same day will not be repeated, and will not be counted as the number of times the world is unlocked.
- The Replay icon on the Results page must be a clickable button; clicking it will restart `Practice Again` of the same mode, without repeating permanent rewards or Theme / Icon unlocking.
- `Quest Calendar` Displays the number of actual completed Quests per day for the current month; Read, Write, and Practice Again are counted by one-time completion records and strictly isolated according to Profile.

### v0.2 Pre-K Visual Hierarchy

- iPhone Horizontal screen Header retains the left side with text `Kids`; the right side `Worlds`, `Calendar`, `Badge` income semi-transparent icon dock. Each icon has a visual diameter of 48 pt, the actual touch box is 72 × 72 pt, and provides a complete VoiceOver label/hint.
- iPad Header continues to display `Worlds`, `Calendar`, `Badge` text, without sacrificing the readability of the large screen in pursuit of uniformity.
- The main mascot of Lobby is 72/104 pt in compact/standard layout.
- Read The main mascot is 80/104 pt; the width of the standard layout word card is 560–760 pt, and the target word is 112 pt; iPhone The compact layout retains 78 pt of target words to avoid squeezing the microphone.
- The main mascot of the Result is 68/104 pt, and the main visual of the reward/replay is 96/144 pt. The size change only enhances the sense of completion, and does not change the points, stars, rewards or Replay behavior.
- The above sizes come from centralized child-scale component tokens; different Worlds continue to use their own palettes, scenes, mascots and rewards, and do not uniformly change them to princess pink.

## 8. Word pool and daily arrangement

Guardian Enter or select words into two independent pools every day:

- `Read New Words Pool`
- `Write New Words Pool`

### Input rules

- `Type one word` Only one word is received at a time; immediately add the current Pool after pressing Return, clear the input box, and display it at the front of the queue in real time.
- `Take Photo` Use the built-in OCR to identify all English words in a photo at once with `Choose Photo`; first provide an editable duplicate removal preview, Guardian and then write it in after clicking `Add All`.
- OCR The batch is placed before the old words as a whole, and the reading order in the photo is maintained within the batch; the identified pictures are not uploaded to the server.
- Automatically remove leading and trailing spaces, unify Unicode format, and ignore case for deduplication.
- It is displayed in lowercase by default; Guardian can retain the specified capitalization for individual words.
- Read does not cross group deduplication between Write; the same word can have two sets of independent records.
- When repeating input with the same pool, no copy is created, but the existing words are moved to the front of the queue and the learning history is retained.
- `Preset Words` Sort by age and grade according to Profile, support tiered browsing, search, word-by-word selection or full selection; only click Add to write to Read, Write or Both.
- Profile of the Preset import binding initiation operation must be completed. Both must be completed in full; if any Pool fails, is partially successful or returns an inconsistent result, only the membership inserted or reactivated this time shall be revoked, and the words that were already active before the import shall not be disabled.
- Support single-item deletion, selection mode and bulk deletion; the first deletion confirmation and Undo status are isolated according to Profile.
- Read supports `Delete all N words` respectively with Write; each time the quantity and Pool are clearly confirmed, the learning history and another Pool are retained, and it can be completely Undo.
- Automatically generates standard American English pronunciation, allowing Guardian to listen to it.
- There is no multiple pronunciation selection, and Guardian does not require you to record it yourself.
- All new words must come from Guardian typing, OCR or explicitly approved Preset selection; when the Pool is insufficient, only practice existing words, and never automatically fill in words.

### Default question volume

| Route | New | Review | Emergency |
|---|---:|---:|---:|
| Read | 5 | 5 | 3 minutes |
| Write | 3 | 3 | 5 minutes |

The four quantities, New/Review order, and two time thresholds can all be configured according to Profile.

### New selection order

1. Prioritize the words just entered on the same day.
2. When insufficient, fill in missing words from the Pool that have not yet been started.
3. Words exceeding the daily limit will remain in the Pool and will be prioritized the next day.
4. When the pool itself is not enough, practice the existing number of words, and do not copy words to make up for the number.

### The relationship between New and Review

- The default `New → Review`, Guardian can be changed to `Review → New`.
- `New → Review` At this time, if you answer incorrectly just now, use Help, identify uncertain or obviously slow new words, you can replace the words with lower priority in Review; the total number of questions will not be increased.
- `Review → New` At this time, the problematic words in New enter the next Review and are not added to Retry at the end of this round.
- The completed definition is “The child has tried all the arrangements for the questions,” not “must all be correct.”

## 9. Read Today’s Quest

### Core state machine

```text
Show Word
  → Tap Mic
  → Listening
  → Speaker Check
  → Word Recognition
      ├── Correct → score + micro reward
      ├── Technical Retry → neutral retry
      └── Valid Incorrect → retry, at most 2 retries
```

### interface

```text
┌──────────────────────────────────────────────────────────┐
│  01:42          ● ● ● ○ ○ ○ ○ ○ ○ ○             Pause  │
│                                                          │
│                         because                          │
│                                                          │
│                    ┌──────────────┐                      │
│                    │      🎙      │                      │
│                    │     Read     │                      │
│                    └──────────────┘                      │
│                                                          │
│                         +100                             │
└──────────────────────────────────────────────────────────┘
```

### behaviour

- Only one large-sized word is displayed for each question.
- New Profile, new words and entering Read Quest should remain quiet; never play the target pronunciation before the first independent answer.
- Each World specifies the unique, complementary and high-contrast dark target word color by designing tokens; all Read words in the same World remain consistent, and only switching World changes the color. The color does not indicate correctness or incorrectness.
- After two consecutive incorrect readings, the only Help button will be displayed: `Hear it` Play the standard pronunciation. Read No picture prompts will be displayed; technical retries will not unlock Help.
- After using `Hear it`, subsequent attempts to record are recorded as guided evidence.
- The child clicks the microphone once, and the app automatically starts and detects when it's done.
- Perform noise reduction, echo cancellation, voice activity detection, silent cropping and voiceprint matching.
- The original audio is only processed briefly on the local machine and deleted immediately after completion.
- App identifies as Target Word but does not show the Professional Pronunciation score.
- Text matching allows tested conservative phonetic equivalents, such as the target `come` being transcribed by children ASR as `kum/cum`; `come/some`, `cat/cap`, and other different words cannot be mistakenly judged as passing using an unbounded editing distance. This equivalence layer cannot bypass valid audio, voiceprint, or confidence gates.

### Retry rules

- First successful attempt + up to two successful retries, a total of 3 times.
- No voice, too much noise, other people talking, multiple people overlapping, voiceprint insufficient or engine failure belong to `technicalRetry`.
- `technicalRetry` Does not consume the number of retries, does not enter the correct rate, and does not affect the forgetting curve or speed.
- Failed after three valid attempts: Play the standard American pronunciation, mark it as a problem word, and continue.

### Time taken

- It mainly records the effective waiting time from the appearance of words to the child's beginning to speak.
- Deduct technical retries, system interruptions, and background waits.
- It is only compared with the historical baseline of similar word length with the Profile and Read patterns.

## 10. Write Today’s Quest

### interface

```text
┌──────────────────────────────────────────────────────────┐
│  03:18          ● ● ○ ○ ○ ○                     Pause   │
│                                                          │
│                         🔊                               │
│                                                          │
│             _ _ _ _ _ _ _                               │
│             ─────────────────────────                    │
│             - - - - - - - - - - - -                    │
│             ─────────────────────────                    │
│                                                          │
│   🔊  [?]   [✏️ Pencil / Chalk / Brush] [Eraser] Clear [Done]│
└──────────────────────────────────────────────────────────┘
```

### behaviour

- At the beginning of each word, only the pronunciation is played, and the full spelling is never displayed in advance; only when the child actively clicks `?` will the answer be displayed.
- Read Use the same clear and coherent canonical teacher cadence as Write. The offline fallback uses a moderate speed, natural pitch, and a single uninterrupted utterance, and retains longer sentence-end releases in Write to ensure that the consonants at the end of short words such as `of`, `at`, and `look` can be heard.
- Do not establish a compulsory progressive route of "spelling → description → copying → dictation".
- The official title is only given to the light-colored spaces for pronunciation, the three-line handwriting practice area and the display according to the number of letters.
- The pronunciation button can be replayed indefinitely; replay is not counted as Help, but the number of times it is recorded.
- After clicking the separate `?` icon, the correct spelling will be displayed immediately, and there will be no three-choice menu; it can still be completed after use, but it will not be counted as independent success.
- Support Apple Pencil on fingers and compatible devices.
- The pencil case only provides three black pens: Pencil, Chalk, and Brush; it does not display color selection or Crayon. The pen type is saved as Profile, and the old version of color/Crayon settings are migrated to black Pencil.
- Three pens have distinguishable but low-stimulating writing tones; they only play when you actually move your pen, and do not compete for attention during pronunciation or recording.
- Undo is not available. The fixed Eraser performs local erasure, and the erased track is 4 times the current pen width; `Clear` Click to clear immediately without confirmation pop-up.
- Keep the large size `Done`, and the stop will not be submitted automatically.

### Identification results

- `confidentCorrect`: Score and trigger rewards.
- `confidentIncorrect`: Gentle prompts for rewriting; specific words can appear as clickable images, but spelling is not automatically displayed.
- `uncertain`: Do not directly judge wrong or display the answer; as a technical retake, it is allowed to submit again.
- It still cannot be confirmed the second time: marked as needing review and continuing, so that the recognition engine does not block Quest.
- Matching ignores capitalization; Vision uses the lower/Initial-cap/ALL-CAPS vocabulary, language correction, and the first five candidates of the target word. Production recognition uses at most two independent bounded grids (default 26-point and 36-point fallback), and each pass must independently obtain a complete target without cross-pass splicing or voting. Only `0` → `o` is allowed when the complete target is aligned; `9` → `g` also must be explicitly given by candidates of the same length from the same Vision fragment in the same position. Fuzzy editing distance that accepts neighbors or numbers such as `if/on/or/off/do/no/90` without using it is acceptable.
- Only the data required for stroke saving/recognition results is saved; Guardian The report does not display the child's original handwritten trajectory playback.

### Time taken

- It starts from the end of the last pronunciation playback.
- Pronunciation playback, Help display, and technical recognition are not counted in the speed.
- Corrected by word length, and compared only with the child's own Write history.

PencilKit is used for finger/Pencil capture; the low-system version can use Vision's target word constraint recognition, and the system can be upgraded to PencilKit's native handwriting recognition in the future. [PencilKit drawing policy](https://developer.apple.com/documentation/pencilkit/pkcanvasviewdrawingpolicy/anyinput) · [Vision text recognition](https://developer.apple.com/documentation/vision/recognizing-text-in-images)

## 11. Score and three stars

The child can hold the number score, stars and story rewards at the same time.

### Up to three stars per round.

1. **Completion Star**: You can get it after trying all the arrangement questions.
2. **Accuracy Star**: The strict first answer accuracy reaches the default 80%; or there is only one first answer error in the whole round, and the correct answer is immediately given in the next valid and non-assisted retry. Guardian The first answer accuracy reported still uses the strict value and is not rewarded for liberal rewriting.
3. **Personal Pace Star**: The effective median time is located in the personal comfort zone; the slow side gives 25% allowance, and the fast side does not allow allowance. The first 3 effective Quest calibration periods will also be awarded this star as long as there is an effective timer.

### Score default formula

- Total score 0-100.
- Accuracy is 80 points, and Personal Pace is 20 points.
- If you answer correctly after Help, you can get the completion score, but it is not counted as independent correctness.
- No reverse deduction, no negative scores, and no cross-child ranking.
- Technical retests and model uncertainty are completely excluded from the denominator.
- The first 3 valid Quests used to establish a personal speed baseline are displayed as `Learning your pace`; the calibration period will no longer lose the third star as a result.

Speed Star does not directly use the whole round of emergency time, but uses the personal baseline corrected word by word and by word length to avoid encouraging rushing to answer or sloppy writing.

## 12. Timer and emergency status

- Timer is a positive countdown, not a countdown.
- Complete the Quest by answering the questions, not by the end of the time.
- After exceeding the default threshold, enter the narrative emergency state of the current World.
- Only change the music, environment color and scene animation.
- No deduction of points, no countdown failure, no increase in difficulty, no increase in prompts.
- No flashing, no sudden volume increase.
- `Reduce Motion` or `Calm Emergency` When turned on, only mild colors and rhythm changes are retained.

## 13. World Pack and reward system

### Content structure

```text
Theme Category
└── World Pack
    ├── Independent art direction
    ├── Independent music and emergency status
    ├── 20 small collections
    └── 5 large-scale scene milestones
```

V1 currently implements eight complete World Packs:

| World | Category | Art Direction | Example Reward |
|---|---|---|---|
| Moonpetal Kingdom | Princess | Warm Hand-painted Forest Fairy Tale | Crown, Dress, Pet, Castle Room |
| Build-It Bay | Construction | Bright Three-dimensional Picture Book City | Construction Vehicles, Tools, Bridges, Urban Buildings |
| Paws & Pines | Animals | Natural exploration and care | Animal companions, food, toys, habitats |
| Dino Discovery | Dinosaurs | Jungle, Volcano and Fossil Exploration | Little Dinosaurs, Fossils, Exploration Equipment, Lost Valley |
| Firehouse Heroes | Rescue | Friendly Fire Station and Urban Rescue | Fire Engine, Safety Equipment, Team Badge, Rescue Route |
| Brickwork City | Building | Original colorful block building | Blocks, gears, vehicles, houses and city works |
| Frostlight World | Winter | Ice crystals, snowfields and auroras | Snowflakes, ice crowns, winter companions, crystal mountains |
| Coaster Carnival | Amusement | Roller coasters and night fairs | Tickets, rides, balloons, fireworks celebrations |

In the same category, there may be multiple World Packs with completely different styles in the future, such as watercolor forest fairy tales, crystal music theater or starry night ball. The art only borrows abstract emotions and media language, and does not reproduce the characters, costumes, scenes and iconic styles of Disney, Ghibli and Frozen.

### Reward rhythm

- Each correct answer triggers a 1–2 second theme microanimation.
- Complete one round of Today’s Quest to earn a clearly visible permanent collectible.
- Promote large-scale scenes jointly in multiple rounds.
- Points and stars advance the current World's achievement trajectory.
- Do not use random treasure chests or probability rewards.
- Only the rewards of the completed World will be obtained.

### Unlock the world

- For the first time, you can choose a Starter World from eight worlds.
- Complete Read Today Quest and Write Today Quest on the same local natural day to form a `Double Quest Day`.
- After the next local natural day, each unclaimed Double Quest Day will unlock a new World Theme and a new Profile Icon in the order of the stable catalog; it will not be unlocked in advance on the same day, and it will be reissued exponentially when you open the App again the next day.
- Practice Again, Replay, and completing only Read or Write separately will not be counted as unlocking.
- After all eight World Themes are obtained, no fictional new Themes will be created; the Icon catalog and future World Pack can be expanded.
- Guardian Starter World can be replaced or unlocked directly.
- The world is unlocked for preview, but not for entering Quest.
- Kid Independence of Lobby `My Collection` The page simultaneously displays the Theme, Icon and Treasure obtained/not obtained. Each Treasure of 25 in a World shows relevant and non-repeating icons; when not unlocked, the gray icon is retained and the lock is superimposed, instead of being replaced with a general lock.
- Children can choose the collected Treasures as Profile avatar, and the uncollected Treasures cannot be selected. Theme, animal Icon, and Treasure avatar are all preserved according to Profile, and the original photo data will not be deleted because of the selection of reward avatar.

## 14. Guardian End

### Today

Each Kid Profile shows:

- Read / Write The number of new inputs today
- New words waiting in the pool
- Current Expiration Review
- Today's Quest completion status, score and stars
- Current month Quest Calendar (number of accurate completion per day)
- Words that need to be paid attention to
- Synchronization status
- `Manage Words`
- `Choose preset words`

### Words

- Read / Write Two clear tabs.
- Top word input bar: one word at a time, Return to add it immediately.
- Local `Take Photo` / `Choose Photo` OCR, editable import preview and `Add All`.
- The newest-first queue below, single-line deletion, selection mode, batch deletion confirmation and Undo; the first deletion confirmation and Undo status are isolated by Profile.
- Read / Write Each provides `Delete all N words`; high-impact operations clearly confirm the quantity and target Pool each time, and can still be fully Undo after completion, without deleting the learning history or modifying another Pool.
- The independent Preset Words browser offers recommendations for ages 3–8 / Pre-K–Grade 3; it first displays up to 6 sets of matching content, and then allows you to browse or search in layers by "basic words/phonics/noun topics/verbs/adjectives and concepts".
- Each leaf phrase in the Preset Catalog consists of 30-50 original, arranged words; parents can select each word individually or Select all, and clearly add Read, Write or Both. Opening the list, age matching, or recommendation sorting will not automatically write to the Pool; duplicates are removed based on standardized spelling within the target Pool.
- Preset import always writes the Profile that initiates the operation. Both import handles compensation transactions; if it fails, it only undoes the insertion or re-activation of the membership, retaining the existing active word.
- The Parent horizontal and vertical screens in iPhone / iPad are all kept at a 44 pt touch target, and the keyboard does not obstruct operation.
- Status: `Queued`, `Learning`, `Review Due`, `Strong`.
- Word details: edit uppercase and lowercase, listen to it, view history, and delete.

### Reports

Overview:

- 7 / 30 Day Completion Trend
- Correct rate trend
- Trend of personal effective usage time
- Read / Write Comparison
- Progress of stars and the world

Word level report:

- Current memory state
- Independent accuracy rate and error rate
- Average / Median effective time
- Number of retries, Help and pronunciation playback times
- Recent practice time
- Expected next Review
- “Why this word is due for review now”

Guardian An obvious voice or handwritten misjudgment can be corrected once. The system corrects the AttemptEvent and recalculates the state, clearing the entire word history.

### Profiles & Family

- Create, edit, and delete Kid Profile.
- All new entrances must collect the age of 3-8 years old; when the child builds it by himself, the age will give the grade recommendation within the current support range. When setting it for the first time and editing it with the Parent, the grade will still be clearly selected by the parent. Modifying the age will not silently override the parent's selection.
- Invite or remove Guardian.
- View the synchronization status, the number of pending modifications to be synchronized, and the last successful time; each device shows whether it needs to be re-registered voiceprint separately.
- The voiceprint; voiceprint template cannot be copied across devices when re-registering or deleting the current device.
- When deleting Profile, tombstones are propagated to all devices to prevent offline old devices from uploading data again.

### Settings

- Quest: four question quantities, New/Review order, emergency threshold
- Audio & Voice: Microphone test, voiceprint re-registration, pronunciation preview
- Worlds: Starter World, manual unlocking
- Notifications: Set time and do not disturb according to Profile
- Accessibility: Reduce Motion, Calm Emergency, left-hand layout
- Family & Sync: Members, Permissions, Synchronization Status
- Privacy & Data: Export, Delete, voiceprint Instructions

## 15. Forgetting Curve and Review Scheduling

Each `Kid Profile × Word × Mode` is maintained independently:

- `difficulty`
- `stabilityDays`
- `lastIndependentSuccessAt`
- `predictedRecall`
- `nextDueAt`
- `lapseCount`

With the Ebbinghaus forgetting curve form as the core:

```text
R(t) = exp(-t / stability)
```

Correct, wrong, Help, effective response time and pronunciation replay times will change `stability` and `difficulty`; 1, 3, and 7 days will not be written as fixed calendar days.

### Review sorting

1. Words that have been passed over the expected forgetting point.
2. Words with high effective error rate
3. Words that are relatively obviously slower than the personal baseline.
4. Use Help, Try Again, or Rephrase for words that are difficult to pronounce
5. Words that have not been exposed enough times
6. Words that have just appeared in the current New stage with problems

`Mastered` is a display label, not a permanent graduation. The default requirement is at least three successful independent cross-day attempts, and the model is expected to maintain its target memory rate for the next 14 days; it will then re-enter Review based on predictions.

## 16. Events, scoring and recalculable status

Every valid or technical attempt to write to the immutable `AttemptEvent`:

```text
eventID, profileID, questID, wordID
mode: read | write
phase: new | review
result: correct | incorrect | helped | technicalRetry
technicalReason
validRetryIndex
promptAt, validInputAt, submittedAt
technicalHoldMs, scoreEligibleMs
speakerConfidence, recognitionConfidence
modelVersion, schedulerVersion, deviceID
```

Hard constant:

- `technicalRetry` No valid retries are consumed.
- Do not enter the denominator of the correct rate or speed.
- The forgetting curve is not updated.
- No points or stars will be deducted.
- Synchronization, algorithms and reports are recalculated from immutable events to avoid version upgrades from destroying history.

## 17. Offline, synchronization and family sharing

### Local priority

- Quest always writes locally first, CloudKit Do not block children from answering questions.
- All core functions can be completed offline.
- After submitting locally, mark Profile to the persistent outbox; restore the network, App to the front page, or try again after parents click `Sync now`.
- Attempt, QuestCompletion, RewardGrant use immutable UUID events.
- Profile, Pool membership and Settings use persistent logic revision to make a definitive merge with device ID, and cannot rely only on the device clock.
- After merging Attempt / Correction, WordProgress and the forgetting curve are recalculated from the event history; the progress snapshot of the competition is not authoritative data.
- Today completion, Daily Plan and Reward use the stable business key of Profile + Mode/World + LocalDay. Offline dual device completion can only count for one Today reward at a time.
- Repetitions of Word are merged by `Profile + Mode + normalized word` after synchronization; the homonyms of Read and Write are still two independent learning objects.
- Synchronization status, number of pending tasks, last successful time and recoverable errors are still visible after restarting; the synchronization blocking box does not pop up on the child's question-solving page.

v0.7.0 Keep a checkable local JSON snapshot as the running source, synchronizing `CKSyncEngine`, crash-resistant outbox/inbox persisted by private and shared libraries respectively with Profile-level apply transaction, without introducing Core Data or custom server. The complete record scope, merging rules, deletion and layering acceptance can be found in [ADR-0001](Docs/ADR-0001-CROSS-DEVICE-FAMILY-SYNC.md), [Data List](Docs/FAMILY-SYNC-DATA-MANIFEST.md) and [acceptance Matrix](Docs/FAMILY-SYNC-ACCEPTANCE-COVERAGE.md).

The Family Sync page uses Apple `UICloudSharingController` to manage existing shares in production Release. The entry is first authenticated through Parent Gate with system-sensitive operations, and then the owner is routed to the private database and the participant is routed to the shared database through persistent binding; revoked, deleted or malformed bindings always fail closed and cannot silently create a private fallback. After the system page saves or stops sharing, the App is updated through the same reconciliation/receipt/UI refresh path as the background notification. LocalQA and ordinary simulators do not inject this entry.

### The same Apple ID

- Use CloudKit private database to automatically synchronize Profile data.
- After each device is opted in separately, sync Profile/avatar, Read/Write Pool, Settings, Attempt/Correction, Calendar completion, and Reward.
- Recently used Profile, system notification instances, voiceprint, picture prompts, and teacher pronunciation caches remain local on the device.

### Different Apple ID

- Clarify invitations and acceptances through `CKShare`; Apple Family membership does not automatically grant access to App data.
- A Kid Profile corresponds to a shared object diagram.
- Owner Guardian has root Profile; others Guardian obtain read and write permissions.
- The native participant permissions of CloudKit are only read/write, so V1 does not include independent children Apple ID as writable participants. [CloudKit sharing](https://developer.apple.com/documentation/cloudkit/sharing-cloudkit-data-with-other-icloud-users)

## 18. voiceprint Isolation from devices with downloadable assets

- The original recording will not be preserved or uploaded.
- voiceprint The template is only stored in the current device's Keychain; Profile Export when synchronizing `notEnrolled`, and retain the enrollment status of the receiving device when importing.
- New iPhone/iPad needs to complete voiceprint registration separately for the same Kid Profile; voiceprint is not available and cannot block the synchronization of learning history.
- Specific word pictures and future remote audio supplements are only written into App `Caches`, not CloudKit. Katie, who has 500 words in the first release, is distributed offline with the App bundle in bilingual speech audio format; parents who use custom words outside the bundle use the built-in Apple English female voice fallback. Neither audio type enters the family synchronization data.
- The original Avatar image belongs to Profile data clearly selected by the parents, not cache; after Family Sync is turned on, it synchronizes independently with prepared JPEGs of up to 512 px and 256 KiB `CKAsset`. The general envelope only carries references and verification metadata. Damaged or mismatched assets are isolated and will not overwrite existing avatar.

## 19. notify

Guardian Can be opened according to Profile:

- Daily learning reminder
- Read / Write Pool is about to be empty
- Quest completion status for the day
- Synchronization failed
- Weekly summary of long-term problem words

Default rules:

- Do not send reminder notices to Kid.
- The lock screen does not display children's nickname, specific words, scores or voiceprint information.
- Support do-not-disturb hours and full shutdown.

## 20. Design system

### Three-layer Token

```text
Primitive → Semantic → Component
```

- Primitive: color, spacing, font size, rounded corners, shadows, animation effect time.
- Semantic: Read, Write, Success, Attention, Surface, Ink.
- Components: Quest Card, Mic Button, Writing Canvas, Timer, Star Rail, Reward Card.
- World Pack only covers theme semantic tokens and does not change the component structure and function colors.

### Core visual Token

| Token | Default purpose |
|---|---|
| `surface.canvas` | Warm light cream background |
| `ink.primary` | Dark blue gray text |
| `action.read` | Clear blue |
| `action.write` | Soft purple |
| `feedback.correct` | Light green |
| `feedback.attention` | Amber color, no use of bright red |
| `radius.child` | 24–32 pt large rounded corner |
| `touch.child` | At least 72 × 72 pt |
| `touch.guardian` | At least 44 × 44 pt |

### Font and text

- Kid UI uses clear, rounded but not overly cartoonish system fonts.
- Target words use the highest contrast and stable fonts, and do not use decorative fonts.
- iPad Read Word suggestions 96–128 pt; iPhone Landscape screen suggestions 64–88 pt.
- Guardian Support Dynamic Type.

### Dynamic effect

- Click feedback: about 120–180 ms.
- Correct answer animation: 1–2 seconds.
- Permanent collection revealed: Skip it in less than 3 seconds.
- Do not use flashing or strong screen shaking in emergency situations.
- Support Reduce Motion.

### Sound effects and background music

Todo Math is only an interactive reference for "children can understand independently, game feedback is instant, and background music can be turned off by parents"; Tada Words's melody, tone combination, voiceover, sound effects and recording must be original. [Todo Math official introduction](https://todomath.com/) · [Todo Math background music settings](https://todomath.zendesk.com/hc/en-us/articles/360022343054-I-can-t-hear-any-sound)

#### Startup sound indicator

- Play the original sonic logo for about 1.5–2 seconds every time you start the device cold, and clearly shout **`Ta-dá↗ woooords↘!`** (approximately "It's here, Wal-Mart") with a continuous short sentence recorded offline with Aurora.
- `da` It is slightly elongated and raised, and then there is no deliberate comma pause, and it is directly connected to the obviously elongated and falling `wor`; the overall excitement is energetic, and at the same time, there should be no mechanical seams of multiple queueing utterances.
- The starting finished product does not rely on punctuation to let TTS guess the intonation: the first beat must be light, short, and approximately flat `/tə/` (listening quality is close to "he", and cannot be read as the "tower" with high and low tones); the second beat uses a non-repeating continuous `/dɑː/` vowel to lengthen the upward pitch map (listening quality is close to "da~"), and no additional `a` emphasis should be produced by copying vowels; then use the 8ms crossfade, which is only used to eliminate clicks, to directly access the step-by-step descending `words`. Any silence detectable between two words is considered a failure.
- Start up normally and always use the Cartesia Aurora sound system to ensure that all devices have the same brand reading; use the definitive Apple American female voice return only when resources are damaged or missing, and cannot be muted or temporarily synthesized over the network.
- The final arrangement and environmental tailing follow the current selected World Pack; use the neutral brand version when Starter World has not been selected.
- Do not imitate the melody, rhythm, voice actor, or any real-life voice of Todo Math.
- It does not play repeatedly when returning briefly from the background to avoid frequent disturbance.
- Guardian The startup voice broadcast can be turned off.

#### background music

- Each World Pack has its own independent original music theme and instrument combination, and the reward sound colors are not mixed across World.
- When a child switches to World, the music and ambient sounds in Lobby, Read, Write, the Settlement page, and Collection immediately switch to the sound skin of that World.
- In normal use, it uses a light but low-density cycle, which does not compete for attention with TTS, children's reading or writing rhythms.
- In emergency situations, use accelerated or layered versions of the same original theme for smooth switching; do not suddenly increase the volume or add alarm sounds.
- Background music automatically ducks when playing TTS, Help, and standard pronunciation.
- Read `Hear it`, Write Automatic prompts and Parent trial listening are prioritized for the 500-word offline package: Katie is a canonical teacher, Read and Write are generated at normal speaking speed `1/1.5 ≈ 0.67×`, and 120ms of safety padding is retained at the end of the file to ensure that playback ends only after the release of trailing consonants such as `/t/` in `at`. If the dual recognition audit confirms that the canonical output of a single isolated word is unclear, it is allowed to record a word-level voice/speed override in the manifest; Aurora is only used for `bun` in the first package. Two versions of each word are not interchangeable; words that are not covered use the same Apple American female voice fallback. During playback, switch to the spoken-audio session and simultaneously mute the app music and external audio, and then restore the mix after the end.
- Read Quickly fade out the background music and unnecessary ambient sounds before starting the recording; smoothly restore them after the recording is over to avoid affecting noise reduction and recognition.

#### Function sound effects

- Click, correct, retry, stars and favorites use the same functional semantics, but the specific timbre and short melody follow the current World.
- Click: Short, soft and low-stimulating touch sound.
- Correct: First, play the original upward short sound type of the current World immediately, and then rotate five Aurora micro-celebration phrases (such as `Yes!`, `You did it!`, `Nice one!`) in order, avoiding continuous repetition of the same sentence; transition does not use exclamation words such as `Ta-da!`. Reduced Sound Only retain necessary non-verbal feedback and turn off these decorative voiceovers.
- Valid Error: Gentle "Try Again" prompt, no beeping or failure horn.
- `technicalRetry`: Neutral prompts must be clearly different from the child's incorrect responses when used.
- Three stars: three segments of revealed sounds that can be distinguished but belong to the same sound family.
- Quest settlement: The stars still use the exclusive sound effects of the current World. When completed, add Aurora's short sentences `Quest complete!`; no `Ta-da!` is added, and no random rare sound effects are made.
- After answering each non-final word, you must wait for the current World short sound type and Aurora micro-celebration phrase to end completely, and then leave a clear breathing pause of 700ms before displaying and reading the next Write word; Read uses the same timing rules as Write. The last word does not wait for the inter-item pause in addition and directly enters the Quest settlement.
- Three writing tools use original short friction/granular sounds and throttle down according to actual movement; Reduced Sound Turn off these decorative writing sounds, so that they are not superimposed when the pronunciation is played.

#### The direction of the voice of World's debut

| World | Sound Direction |
|---|---|
| Moonpetal Kingdom | A cheerful original loop of about 100 BPM; harp, bell, bass pulse, light drum, soft brush and magic flashing sound; scenes with rainbows, clouds and unicorns on both sides, and a clear learning safety zone in the center |
| Build-It Bay | Wooden blocks, light percussion, soft mechanical rhythms and safe engineering completion sounds |
| Paws & Pines | Marimba, original stringed instruments, bird calls and gentle natural environment sounds |
| Dino Discovery | Jungle steps, marimba and gentle bass at about 80 BPM, without scary screams |
| Firehouse Heroes | Cheerful parade rhythm of about 120 BPM, no use of sirens or piercing whistles |
| Brickwork City | Wooden block rhythms and soundscapes at about 120 BPM, without borrowing sounds from commercial toy brands |
| Frostlight World | Crystal clock chime waltz at about 75 BPM with light double subdivision |
| Coaster Carnival | Elevating strings at about 150 BPM with park rhythms, maintaining safe peaks and vocal space |

Standard American word pronunciations, Help narration, and necessary teaching tips do not change with the voice actor or pronunciation method of World, ensuring that children form a stable auditory reference.

#### Control and safety

- Guardian can be controlled separately `Voice`, `Music` and `Sound Effects`.
- The default volume is normalized by loudness, so there are no sudden peaks.
- Reduce Motion Does not affect necessary sound prompts; an independent Reduced Sound mode is also provided.
- All audio assets are subject to source, author, license, and version records; purchased sound effects must have a clear App commercial license.

### Accessibility

- Feedback relies on sound, graphics and movement at the same time, not just on color.
- Guardian Support VoiceOver and Dynamic Type.
- Provide a left-handed layout to avoid buttons in the main palm area.
- All control positions are fixed, and there is no layout jump when loading or feedback.

## 21. General component status

| Component | Core State |
|---|---|
| Quest Card | ready, inProgress, completed, syncPending, disabled |
| Mic Button | idle, listening, checking, technicalRetry, disabled |
| Writing Canvas | empty, drawing, checking, correct, uncertain, retry |
| Timer | normal, emergency, paused |
| Star Rail | calibrating, earned, unearned |
| Reward Card | locked, revealed, collected |

Disabling, loading, technical retries, and valid errors must have different visual and verbal feedback; they cannot be covered by the same "failure" state.

## 22. Guardian Notice and Privacy Principles

- The original audio never leaves the device.
- voiceprint Templates are sensitive device local information; registration, re-registration, and deletion are Guardian operations, but do not enter Family Sync.
- When Family Sync is enabled, Avatar photos are synced as Profile data; picture prompts are not synchronized with teacher pronunciation cache.
- Does not access advertising SDKs or third-party child behavior tracking.
- Guardian Learning data can be exported and completely deleted Profile.
- Delete operations use the smallest tombstone that does not contain nickname, photos, words or learning content, and synchronize it to all devices and shared members; the tombstone unconditionally overwrites any old data with the same Profile ID, and other CloudKit records are physically erased.

## 23. V1 acceptance Standards

### Child

- A 4-year-old child can choose Profile and enter two Quests without reading the instructions.
- Cold start first displays Profile; if there is no Profile, it is created directly, and if there is Profile, the last selection is highlighted but the child's confirmation is not skipped.
- Read The entry to Write will not be mistaken for the same task.
- Read Keep quiet before the first independent answer; the only `Hear it` Help will appear after two valid errors.
- When completing Read questions, technical noise will not be counted as a pronunciation error.
- When completing Write questions, stopping writing will not trigger automatic submission.
- The teacher of Write has clear and coherent pronunciation, and will not swallow the final consonants of short words due to excessive deceleration or too early audio recovery.
- Kids can see their score, three loose stars, and theme rewards, and choose the Theme / Icon they earned from My Collection.
- A normal click on Results Replay will actually start the mode Practice Again.
- After exceeding the threshold, it can continue to be completed, and there will be no failure countdown.

### Guardian

- You can add words to any Pool and listen to them in 30 seconds through word-by-word typing, Camera / Photo OCR, or explicitly approved Preset selection.
- New words appear immediately at the front of the queue; they can be deleted individually, selected in bulk, cleared as a whole group and Undo, and the deletion status will not cross Profile.
- New Profile Must clearly select the age of 3–8 years old; age and Grade are only sorted by Preset recommendations.
- The app does not automatically generate, add recommendations, or add words when the pool is empty or the quantity is insufficient.
- Both Preset import either updates two Pools or only rolls back this change, without affecting existing active words or other Profile.
- Automatic deduplication does not delete words with the same name on another route.
- The report can explain why a word entered Review.
- It can correct automatic recognition misjudgments.
- Multiple Kid Profile and Guardian can be managed.

### Data & Privacy

- Offline completed Quests will not be lost or duplicated when the network is restored.
- It can be synchronized with Apple ID and shared with cross Apple ID.
- Original child recordings are not written to persistent storage or the cloud.
- voiceprint The template maintains the independence of each device; new devices only synchronize learning materials and re-registervoiceprint.
- Image prompts and teacher pronunciation cache are not copied across devices, and can be safely redownloaded if necessary.
- Incorrect recognition, noise and incorrect speech do not affect the score, stars or forgetting model.
- After deleting Profile, the offline old device cannot recreate it.

### Technical Spikes before full build

1. Word recognition, voiceprint filtering and local accuracy under household noise of 4-year-old children.
2. The correct / incorrect / uncertain threshold values of three states of handwriting of 4-year-old children under the constraint of target words.
3. Different Apple ID's `CKShare`, ProfileKey distribution, revocation and key rotation.
4. 4-year-old children can write on the horizontal screen of iPhone 17 Pro Max and target iPad, listening quality, layout and accessibility usability; iPad automated links have been passed, but manual acceptance has not yet been completed.

## 24. V2

V2 Add `Grade Curriculum`:

- Guardian Choose Pre-K, Kindergarten, Grade 1 and other levels.
- The app automatically creates or recommends Read / Write Pools using authorized, traceable U.S. tiered vocabularies.
- Share deduplication, forgetting models, learning records and rewards with Parent Words.
- V1 data model reserved `source = parent | curriculum`.
- Add World Packs of the same category and different art directions.

V2 still needs to confirm the grading standards, vocabulary copyright and Read / Write classification rules separately; the generation model cannot arbitrarily create course standards.

## 25. Confirmed sensitive operation authentication rules

Use layered authentication:

- Enter Guardian area for daily use and use "Normal Click `Parents`+Random Arithmetic Questions".
- The following sensitive operations must be performed with additional authentication via Face ID, Touch ID, or device passcode; arithmetic problems cannot be used as a substitute for system authentication:
  - Invite or remove Guardian
  - Export children's data
  - Delete Kid Profile or voiceprint
  - Re-register voiceprint or rotate the encryption key

If the device does not have available system authentication set up, access to normal Guardian reports and word entry is still allowed, but the above sensitive operations are blocked, and Guardian prompts the device password to be set first.
<!-- TADA_BILINGUAL_ZH_START -->

---

<a id="简体中文版"></a>

> **翻译说明：** 英文为默认阅读语言；本文同时保留原始语言文本。如中英文内容存在差异，请以原始语言文本为准。

# Tada Words — V1 产品与交互设计

> 状态：v0.3.1 已完成 iPhone production Vision 真机测试，以及 iPad production/UI 真机自动化回归；儿童手写、音频听感、布局与辅助功能仍待人工验收
>
> 项目名称：**Tada Words**
>
> 目标版本：家庭私有测试版 / TestFlight V1

## 1. 产品定义

Tada Words 是一款面向学前儿童的英语 sight-word 学习 App。Guardian 每天分别录入或选择需要“会读”和“会写”的单词；孩子通过两个彼此独立的主题闯关，最终做到：

- **Read**：看见单词后，可以独立读出来。
- **Write**：只听见标准发音，可以独立手写完整单词。

首位目标用户是 4 岁、即将进入 Pre-K、中文母语、生活在美国英语教学环境中的孩子。她已经认识并会写大小写字母，正在开始 phonics 和 sight words。

### V1 产品承诺

- Read 和 Write 是两条独立学习路线，不合并成一轮任务。
- V1 的 Kid 与 Guardian 界面都只使用英文；本文档使用中文仅便于设计沟通。
- Kid Quest 主要依靠图形、声音和动画引导，不提供中文提示。
- 学习以真实回忆为核心：Read 必须开口，Write 必须落笔。
- App 可以识别和安排练习，但不能因为识别不确定而惩罚孩子。
- 游戏奖励增强持续练习，不替代学习目标。
- 多个 Kid Profile、多个 Guardian 和多设备数据保持一致。

### V1 不做

- 不按年级自动填充 Read 或 Write Pool。V1 的离线 Preset Catalog 只提供排序、浏览和搜索，必须由 Guardian 明确选择并提交；自动课程模式进入 V2。
- 不做 Read 配对、听音找词等额外小游戏。
- 不做社交、儿童排行榜、广告、抽卡或随机宝箱。
- 不保存或上传任何原始练习录音。
- 不承诺专业的 phoneme-level 发音评分；V1 判断的是孩子是否独立读出了目标词。
- 不复制 Todo Math 或其他产品的旋律、音效、角色口播、采样和声音资产。

## 2. 用户与权限

| 角色 | 能力 |
|---|---|
| Owner Guardian | 创建家庭、邀请 Guardian、创建和删除 Kid Profile、管理所有数据 |
| Guardian | 手输、OCR 或选择 Preset 单词，调整设置、查看报告、管理声纹与主题 |
| Kid Profile | 选择自己的头像、完成 Quest、查看收藏与世界 |

V1 的 Kid 是 App 内 Profile，而不是必须拥有独立 Apple ID 的 CloudKit 成员。孩子在 Guardian 已登录 iCloud 的设备上使用；不同 Guardian 可以通过邀请共享同一个 Kid Profile。

### Kid Profile 最小资料

- 昵称
- 头像
- 当前年级
- 年龄；新建 Profile 必须明确选择 3–8 岁，旧版缺失年龄仍可读取
- 儿童声纹模板

不收集真实姓名、完整生日、学校或老师信息。

头像来源：

- 前置摄像头自拍
- 从相册选择已有照片
- 内置的可爱动物图标

## 3. 平台与屏幕方向

V1 是 Universal iOS App。

### 必须验收

- iPad
- iPhone 17 Pro Max

其他 iPhone 使用响应式布局尽力兼容，但不作为 V1 发布阻塞项。

### 当前真机自动化证据

2026-07-14，Team `6S245NCUPQ` 签名的 `Tada Words QA` v0.3.1 (`2026071403`) 已在 Darren iPad Air 13-inch (M4)、iPadOS 26.5 安装并启动。Production DeviceTests 2/2 通过，覆盖 wrong-word rejection 与 `of/go` case variants；LocalQA Critical XCUITest 7/7 通过，覆盖 OCR Add All、Delete All/restore、明确批准 Preset、连续删除/排序、Photo picker/排序及 Read/Write 完成反馈消失。

这些证据验证 production 识别链路和关键交互可以在 iPad 真机运行，但不替代儿童真实手写、发音听感、横竖屏布局、Apple Pencil、VoiceOver 与 Dynamic Type 验收。

### 方向规则

- Profile Picker、World Lobby、Kid Quest、结果页与 Collection 只支持 `Landscape Left` 与 `Landscape Right`。
- `Parents`、Parent Gate、Guardian 管理页与首次家长设置支持横竖屏。
- iPhone 家长路线支持 Portrait 与两个 Landscape，不支持 Portrait Upside Down；iPad 家长路线支持四个方向。
- 离开家长路线后，App 必须通过 route-level geometry update 立即恢复横屏；孩子页面左右两个横屏方向都要验收。
- iPhone Kid Quest 会减少背景装饰，优先保证大单词、麦克风和完整书写区。
- Kid Lobby 的大型故事装饰固定在左右下方安全带，前景 Quest 卡片和按钮坐标不移动；装饰动画只能从安全基线向下漂浮，不能上浮回卡片阴影。Moonpetal 独角兽在 iPhone 横屏最紧凑帧也必须与 Write 卡片保留可见背景间隙，且任何 World 的装饰都不能在底部或侧边被裁切。

Write 支持手指；Apple Pencil 仅在兼容设备上启用，并使用防误触。Apple 官方当前的 Pencil 兼容设备为 iPad，因此 iPhone 17 Pro Max 的 Write 输入使用手指。[Apple Pencil compatibility](https://support.apple.com/en-am/108937)

## 4. 信息架构

```text
App Launch
├── Profile Picker
│   ├── New Kid（没有 Profile 时直接展开；孩子输入昵称与年龄）
│   ├── 上次 Profile（有 Profile 时突出显示，孩子点击确认）
│   └── World Lobby
│       ├── Read Today’s Quest
│       ├── Write Today’s Quest
│       ├── Practice Again
│       ├── Quest Calendar
│       ├── My Collection（选择已获得 Theme / Icon）
│       └── Treasure Collection
└── Parent Gate
    ├── Today
    ├── Words
    │   ├── Read Pool：Type / Camera / Photo / Select / Delete
    │   └── Write Pool：Type / Camera / Photo / Select / Delete
    ├── Preset Words（按年龄、年级与精细分类浏览；家长明确选择后才加入）
    ├── Reports
    ├── Profiles & Family
    ├── Worlds
    └── Settings
```

儿童端的固定心智模型只有三个选择：

1. 我是谁？
2. 今天 Read 还是 Write？
3. 在哪个已解锁世界冒险？

App 只从 Guardian 已明确批准进入 Pool 的词中编排 New、Review、难词回流和计时。来源可以是手输、OCR，或家长在内置 Preset Catalog 中主动选择的词；年龄和年级只改变推荐排序，任何 catalog 或生成模型都不得自动添加练习词。

## 5. 首次设置

首次启动必须先处理 Profile，不先要求输入单词：

1. 已有 Profile：显示 Picker，并突出上次使用的有效 Profile；孩子点击后进入。
2. 没有 Profile：直接显示 `New Kid`，输入昵称和年龄，并选择头像、年级和 Starter World。V1 新建范围为 3–8 岁，对应 Pre-K–Grade 3；旧 Profile 缺少年龄仍可兼容读取。
3. 阅读并同意儿童声纹、同步与删除规则。
4. 声纹注册、单词录入和通知均可稍后在 Parents 中完成，不阻塞第一次进入 Kid Lobby。

### 一分钟声纹注册

- App 依次播放 8–10 个非常简单的词。
- 孩子只需跟读，不要求自己认识这些词。
- 在安静与轻微家庭背景声下采集多个特征样本。
- 原始注册音频生成特征后立即删除。
- 只保存加密的声纹特征模板和模型版本。
- Guardian 可以删除或重新注册。
- 感冒、成长或置信度下降时，App 提醒 Guardian 重新注册，但不会锁住学习。

声纹只用于过滤“当前是不是这个孩子在说话”，不作为安全登录或身份认证。

## 6. Profile Picker

```text
┌──────────────────────────────────────────────────────────┐
│ Tada Words                                       Parents │
│                                                          │
│       ( Panda )        ( Bunny )        ( Photo )         │
│         Mia              Leo              Addy            │
│                                                          │
│                    “Who’s playing?”                       │
└──────────────────────────────────────────────────────────┘
```

- 每个 Profile 使用 96 pt 以上的大头像卡片。
- 孩子先点击自己的头像；App 不依赖声纹自动切换 Profile。
- App 记住最后使用的有效 Profile；下次冷启动在 Picker 中突出该 Profile，但仍由孩子点击确认。若该 Profile 已不存在，则显示普通 Picker，不猜测其他身份。
- 上次 Profile 使用静态 1.03× 尺寸与更高叠放层级突出；其他 Profile 不降透明度，也不使用持续动画。
- Picker 提供 `New Kid` 卡片。孩子输入昵称并明确选择 3–8 岁年龄；App 按年龄给出当前支持的 Grade 建议，并自动分配内置动物头像与 Starter World。完整编辑仍由 Guardian 完成。
- Read 录音时，才用选中 Profile 的声纹过滤其他说话人。
- `Parents` 入口放在稳定的右上角，普通单击后立即进入随机算术 Parent Gate，不与 Quest 主入口争夺注意力。

## 7. World Lobby

```text
┌──────────────────────────────────────────────────────────┐
│ (Mia)                                 My Collection Parents│
│                                                          │
│                 [ 当前世界互动场景 ]                       │
│                                                          │
│   ┌────────────────────┐  ┌────────────────────┐         │
│   │  Read Today’s      │  │  Write Today’s     │         │
│   │      Quest         │  │       Quest        │         │
│   │   ☆  ☆  ☆          │  │    ☆  ☆  ☆         │         │
│   └────────────────────┘  └────────────────────┘         │
└──────────────────────────────────────────────────────────┘
```

硬性规则：

- 必须始终显示两个独立的大入口。
- 不提供把 Read 与 Write 合并的“综合 Today’s Quest”。
- 当前 World 是全屏背景，但 Quest 卡片位置不随主题改变。
- Header 不重复放置不可点击的 World 名称胶囊；它容易被误认为按钮。当前主题由整页场景和 My Collection 选中态表达。
- 已完成的入口显示当日分数和星星，并提供 `Practice Again`。
- Practice Again 会更新记忆模型，但不重复发放当日永久收藏品，也不计入世界解锁次数。
- Results 页的 Replay 图标必须是可点击按钮；单击后重新开始同一模式的 `Practice Again`，不重复永久奖励或 Theme / Icon 解锁。
- `Quest Calendar` 展示当前月每天实际完成的 Quest 次数；Read、Write 和 Practice Again 都按一次完成记录计数，并严格按 Profile 隔离。

### v0.2 Pre-K 视觉层级

- iPhone 横屏 Header 保留左侧带字 `Kids`；右侧 `Worlds`、`Calendar`、`Badge` 收入半透明图标 dock。每个图标视觉直径 48 pt，实际触控框 72 × 72 pt，并提供完整 VoiceOver label/hint。
- iPad Header 继续显示 `Worlds`、`Calendar`、`Badge` 文字，不为追求统一而牺牲大屏可读性。
- Lobby 主 mascot 在紧凑/标准布局分别为 72/104 pt。
- Read 主 mascot 为 80/104 pt；标准布局单词卡宽度为 560–760 pt，目标词为 112 pt；iPhone 紧凑布局保留 78 pt 目标词以避免挤压麦克风。
- Result 主 mascot 为 68/104 pt，reward/replay 主视觉为 96/144 pt。尺寸变化只强化完成感，不改变积分、星星、奖励或 Replay 行为。
- 以上尺寸来自集中式 child-scale component tokens；不同 World 继续使用自己的 palette、scene、mascot 与 reward，不统一改成公主粉色。

## 8. 单词池与每日编排

Guardian 每天向两个独立 Pool 录入或选择单词：

- `Read New Words Pool`
- `Write New Words Pool`

### 输入规则

- `Type one word` 每次只接收一个词；按 Return 后立即加入当前 Pool、清空输入框，并实时显示在队列最前面。
- `Take Photo` 与 `Choose Photo` 使用本机 OCR 一次识别照片中的所有英文词；先提供可编辑的去重预览，Guardian 点击 `Add All` 后才写入。
- OCR 批次整体排在旧词之前，批次内部保持照片中的阅读顺序；识别图片不上传服务器。
- 自动去掉首尾空格、统一 Unicode 形式并忽略大小写去重。
- 默认显示为小写；Guardian 可为个别单词保留指定大小写。
- Read 与 Write 之间不跨组去重；同一个词可以拥有两套独立记录。
- 同 Pool 重复输入时不创建副本，而是把已有词移动到队列最前面并保留学习历史。
- `Preset Words` 按 Profile 的年龄与年级排序，支持分层浏览、搜索、逐词选择或全选；只有点击 Add 才写入 Read、Write 或 Both。
- Preset 导入绑定发起操作的 Profile。Both 必须全部完成；任一 Pool 失败、部分成功或返回不一致时，只撤销本次插入或重新启用的 membership，不得停用导入前已 active 的词。
- 支持单条删除、选择模式与批量删除；第一次删除确认与 Undo 状态按 Profile 隔离。
- Read 与 Write 各自支持 `Delete all N words`；每次明确确认数量与 Pool，保留学习历史和另一 Pool，并可完整 Undo。
- 自动生成标准美式英语发音，允许 Guardian 试听。
- 不提供多读音选择，也不要求 Guardian 自己录音。
- 所有新增词必须来自 Guardian typing、OCR 或明确批准的 Preset selection；Pool 不足时只练已有词，绝不自动补词。

### 默认题量

| 路线 | New | Review | 紧急状态 |
|---|---:|---:|---:|
| Read | 5 | 5 | 3 分钟 |
| Write | 3 | 3 | 5 分钟 |

四个数量、New/Review 顺序和两个时间阈值都可按 Profile 配置。

### New 选择顺序

1. 优先当天刚输入的词。
2. 不足时，从 Pool 中更早输入、尚未开始的词补足。
3. 超出当日上限的词留在 Pool，下一天优先。
4. Pool 本身不足时就练现有数量，不复制词来凑数。

### New 与 Review 关系

- 默认 `New → Review`，Guardian 可改为 `Review → New`。
- `New → Review` 时，刚才答错、使用 Help、识别不确定或明显偏慢的新词，可以替换 Review 中优先级较低的词；不增加整轮题量。
- `Review → New` 时，New 中的问题词进入下一次 Review，不在本轮末尾追加 Retry。
- 完成的定义是“孩子已经尝试所有安排题目”，不是“必须全部答对”。

## 9. Read Today’s Quest

### 核心状态机

```text
Show Word
  → Tap Mic
  → Listening
  → Speaker Check
  → Word Recognition
      ├── Correct → score + micro reward
      ├── Technical Retry → neutral retry
      └── Valid Incorrect → retry, at most 2 retries
```

### 界面

```text
┌──────────────────────────────────────────────────────────┐
│  01:42          ● ● ● ○ ○ ○ ○ ○ ○ ○             Pause  │
│                                                          │
│                         because                          │
│                                                          │
│                    ┌──────────────┐                      │
│                    │      🎙      │                      │
│                    │     Read     │                      │
│                    └──────────────┘                      │
│                                                          │
│                         +100                             │
└──────────────────────────────────────────────────────────┘
```

### 行为

- 每题只显示一个大号单词。
- 新 Profile、新词和进入 Read Quest 时都保持安静；第一次独立作答前绝不播放目标发音。
- 每个 World 通过设计 token 指定唯一、配套且高对比的深色目标词颜色；同一 World 的所有 Read 单词保持一致，只有切换 World 才改变颜色，颜色不表示正确或错误。
- 连续两次有效读错后，才显示唯一的 Help 按钮：`Hear it` 播放标准发音。Read 不显示图片提示；技术重试不解锁 Help。
- 使用 `Hear it` 后，后续尝试记录为 guided evidence。
- 孩子点击一次大麦克风，App 自动开始并检测说完。
- 进行降噪、回声消除、语音活动检测、静音裁剪和声纹匹配。
- 原始音频只在本机短暂处理，完成后立即删除。
- App 判断“识别为目标词”，不显示专业发音分数。
- 文本匹配允许经过测试的保守音近等价，例如目标 `come` 被儿童 ASR 转写为 `kum/cum`；不得用无边界编辑距离把 `come/some`、`cat/cap` 等不同词误判为通过。该等价层不能绕过有效音频、声纹或置信度门。

### 重试规则

- 首次有效尝试＋最多两次有效重试，共 3 次。
- 无语音、噪声过强、其他人说话、多人重叠、声纹不足或引擎故障属于 `technicalRetry`。
- `technicalRetry` 不消耗重试次数、不进入正确率、不影响遗忘曲线或速度。
- 三次有效尝试仍未通过：播放标准美式发音，标记为问题词，然后继续。

### 用时

- 主要记录从单词出现到孩子开始说话的有效等待时间。
- 扣除技术重试、系统中断和后台等待。
- 只与该 Profile、Read 模式、相近词长的历史基线比较。

## 10. Write Today’s Quest

### 界面

```text
┌──────────────────────────────────────────────────────────┐
│  03:18          ● ● ○ ○ ○ ○                     Pause   │
│                                                          │
│                         🔊                               │
│                                                          │
│             _ _ _ _ _ _ _                               │
│             ─────────────────────────                    │
│             - - - - - - - - - - - -                    │
│             ─────────────────────────                    │
│                                                          │
│   🔊  [?]   [✏️ Pencil / Chalk / Brush] [Eraser] Clear [Done]│
└──────────────────────────────────────────────────────────┘
```

### 行为

- 每个词开始时只播放发音，绝不预先显示完整拼写；只有孩子主动点 `?` 才显示答案。
- Read 与 Write 使用同一清晰、连贯的 canonical teacher cadence。离线 fallback 采用适中速度、自然音高、单个不中断的 utterance，并在 Write 保留更长的句尾释放，确保 `of`、`at`、`look` 等短词的末尾辅音可听见。
- 不建立“拼字 → 描写 → 抄写 → 默写”的强制渐进路线。
- 正式题目只给发音、三线练字区域和按字母数量显示的淡色空位。
- 发音按钮可以无限重播；重播不算 Help，但记录次数。
- 单独的 `?` 图标点击后立即显示正确拼写，不出现三选一菜单；使用后仍可完成，但不计独立成功。
- 支持手指和兼容设备上的 Apple Pencil。
- 笔盒只提供 Pencil、Chalk、Brush 三种黑色笔；不显示颜色选择或 Crayon。笔型按 Profile 保存，旧版彩色/Crayon 设置迁移为黑色 Pencil。
- 三种笔拥有可区分但低刺激的书写音色；只在实际移动落笔时节流播放，发音或录音期间不争夺注意力。
- 不提供 Undo。固定位置的 Eraser 进行局部擦除，擦除轨迹为当前笔宽的 4 倍；`Clear` 单击立即清空，不弹确认。
- 保留大号 `Done`，停笔不会自动提交。

### 识别结果

- `confidentCorrect`：计分并触发奖励。
- `confidentIncorrect`：温和提示重写；具体词可出现可点图片，但不自动显示拼写。
- `uncertain`：不直接判错或显示答案；作为技术重试允许再次提交。
- 第二次仍不能确认：标记为需要复习并继续，不让识别引擎阻塞 Quest。
- 匹配忽略大小写；Vision 使用目标词的 lower/Initial-cap/ALL-CAPS 词表、语言修正和前五个候选。生产识别最多使用两个彼此独立的有界栅格（默认 26-point 与 36-point fallback），每个 pass 都必须独立得到完整目标，不跨 pass 拼接或投票。只允许完整目标对齐时的 `0` → `o`；`9` → `g` 还必须由同一 Vision fragment 的同长度候选在相同位置明确给出 `g`。不使用会接受 `if/on/or/off/do/no/90` 等邻词或数字的模糊编辑距离。
- 只保存笔画/识别结果所需的数据；Guardian 报告不展示孩子原始手写轨迹回放。

### 用时

- 从最后一次发音播放结束后开始。
- 发音播放、Help 展示和技术识别等待不计入速度。
- 按单词长度校正，并只与该孩子自己的 Write 历史比较。

PencilKit 用于手指/Pencil 采集；低系统版本可使用 Vision 的目标词约束识别，未来系统可升级为 PencilKit 原生手写识别。[PencilKit drawing policy](https://developer.apple.com/documentation/pencilkit/pkcanvasviewdrawingpolicy/anyinput) · [Vision text recognition](https://developer.apple.com/documentation/vision/recognizing-text-in-images)

## 11. 分数与三颗星

孩子端同时保留数字分数、星星和故事奖励。

### 每轮最多三颗星

1. **Completion Star**：尝试完所有安排题目即可获得。
2. **Accuracy Star**：严格首答正确率达到默认 80%；或整轮只有一次首答错误，并在下一次有效、无辅助重试中立即答对。Guardian 报告的首答正确率仍使用严格值，不被奖励宽限改写。
3. **Personal Pace Star**：有效中位用时位于个人舒适区；慢侧给予 25% 宽限，过快侧不放宽。前 3 次有效 Quest 的校准期只要有有效计时也授予该星。

### 分数默认公式

- 总分 0–100。
- Accuracy 占 80 分，Personal Pace 占 20 分。
- Help 后答对可获得完成分，但不算独立正确。
- 不倒扣、不出现负分、不做跨儿童排名。
- 技术重试和模型不确定完全排除在分母之外。
- 前 3 次有效 Quest 用来建立个人速度基线，并显示为 `Learning your pace`；校准期不再因此失去第三颗星。

速度星不直接使用整轮紧急时间，而是使用逐词、按词长校正后的个人基线，避免鼓励抢答或潦草书写。

## 12. Timer 与紧急状态

- Timer 是正向计时，不是倒计时。
- Quest 按题目完成，不因时间结束。
- 超过默认阈值后，进入当前 World 的故事化紧急状态。
- 只改变音乐、环境颜色和场景动画。
- 不扣分、不倒计时失败、不提高难度、不增加提示。
- 不闪烁、不突然提高音量。
- `Reduce Motion` 或 `Calm Emergency` 开启时，只保留温和的颜色和节奏变化。

## 13. World Pack 与奖励系统

### 内容结构

```text
Theme Category
└── World Pack
    ├── 独立美术方向
    ├── 独立音乐和紧急状态
    ├── 20 个小收藏品
    └── 5 个大型场景里程碑
```

V1 当前实现八个完整 World Pack：

| World | 类别 | 美术方向 | 示例奖励 |
|---|---|---|---|
| Moonpetal Kingdom | Princess | 温暖手绘森林童话 | 皇冠、礼服、宠物、城堡房间 |
| Build-It Bay | Construction | 明快立体绘本城市 | 工程车、工具、桥梁、城市建筑 |
| Paws & Pines | Animals | 自然探索与照料 | 动物伙伴、食物、玩具、栖息地 |
| Dino Discovery | Dinosaurs | 丛林、火山与化石探索 | 小恐龙、化石、探险装备、失落山谷 |
| Firehouse Heroes | Rescue | 友善消防站与城市救援 | 消防车、安全装备、团队徽章、救援路线 |
| Brickwork City | Building | 原创彩色积木建造 | 积木、齿轮、车辆、房屋与城市作品 |
| Frostlight World | Winter | 冰晶、雪地与极光 | 雪花、冰冠、冬日伙伴、晶莹山脉 |
| Coaster Carnival | Amusement | 过山车与夜间游园会 | 车票、游乐设施、气球、烟花庆典 |

同一类别未来可以拥有多个完全不同画风的 World Pack，例如水彩森林童话、冰晶音乐剧或星空舞会。美术只借鉴抽象的情绪和媒介语言，不复刻 Disney、Ghibli、《冰雪奇缘》的角色、服装、场景和标志性造型。

### 奖励节奏

- 每个正确答案触发 1–2 秒主题微动画。
- 完成一轮 Today’s Quest 获得一个明确可见的永久收藏品。
- 多轮共同推进大型场景。
- 分数与星星推进当前 World 的成就轨道。
- 不使用随机宝箱或概率奖励。
- 在哪个 World 完成，就只获得该 World 的奖励。

### 世界解锁

- 首次从八个世界中选择一个 Starter World。
- 同一本地自然日完成 Read Today Quest 和 Write Today Quest，形成一次 `Double Quest Day`。
- 到下一个本地自然日后，每个尚未领取的 Double Quest Day 按稳定 catalog 顺序解锁一个新 World Theme 和一个新 Profile Icon；当天不提前解锁，隔天才再次打开 App 时会幂等补发。
- Practice Again、Replay、单独只完成 Read 或 Write 都不计入该解锁。
- 八个 World Theme 全部获得后不虚构新 Theme；Icon catalog 与未来 World Pack 均可扩展。
- Guardian 可以更换 Starter World 或直接解锁。
- 未解锁世界允许预览，但不允许进入 Quest。
- Kid Lobby 的独立 `My Collection` 页面同时展示已获得/未获得 Theme、Icon 和 Treasure。每个 World 的 25 件 Treasure 都显示相关且互不重复的图标；未解锁时保留灰色图标并叠加锁，而不是换成通用锁。
- 孩子可以把已收集 Treasure 选为 Profile 头像，未收集 Treasure 不能选择。Theme、动物 Icon、Treasure 头像均按 Profile 持久化，原始照片数据不会因选择奖励头像而被删除。

## 14. Guardian 端

### Today

每个 Kid Profile 显示：

- Read / Write 今天新输入的数量
- Pool 中等待的新词
- 当前到期 Review
- Today’s Quest 完成状态、分数和星星
- 当前月 Quest Calendar（每天精确完成次数）
- 需要关注的词
- 同步状态
- `Manage Words`
- `Choose preset words`

### Words

- Read / Write 两个明确 Tab。
- 顶部单词输入栏：每次一个词，Return 即时加入。
- 本机 `Take Photo` / `Choose Photo` OCR、可编辑导入预览和 `Add All`。
- 下方 newest-first 队列、单条删除、选择模式、批量删除确认与 Undo；首次删除确认和 Undo 状态按 Profile 隔离。
- Read / Write 各自提供 `Delete all N words`；高影响操作每次都明确确认数量和目标 Pool，完成后仍可完整 Undo，且不删除学习历史或修改另一 Pool。
- 独立的 Preset Words 浏览器提供 3–8 岁 / Pre-K–Grade 3 推荐；先显示最多 6 组匹配内容，再按“基础词/拼读/名词主题/动词/形容词与概念”逐层浏览或搜索。
- Preset Catalog 的每个叶子词组为 30–50 个原创编排的单词；家长可逐词选择或 Select all，并明确加入 Read、Write 或 Both。打开列表、年龄匹配或推荐排序均不会自动写入 Pool；目标 Pool 内按标准化拼写去重。
- Preset 导入始终写入发起操作的 Profile。Both 导入按补偿事务处理；失败时只撤销本次插入或重新启用的 membership，保留已有 active word。
- 布局在 iPhone / iPad 的 Parent 横竖屏均保持 44 pt 触控目标、键盘不遮挡操作。
- 状态：`Queued`、`Learning`、`Review Due`、`Strong`。
- 单词详情：编辑大小写、试听、查看历史、删除。

### Reports

概览：

- 7 / 30 日完成趋势
- 正确率趋势
- 个人有效用时趋势
- Read / Write 对比
- 星星与世界进度

词级报告：

- 当前记忆状态
- 独立正确率与错误率
- 平均 / 中位有效用时
- 重试、Help 与发音重播次数
- 最近练习时间
- 预计下次 Review
- “Why this word is due for review now”

Guardian 可以纠正一次明显的语音或手写误判。系统修正该 AttemptEvent 并重算状态，不清空整个单词历史。

### Profiles & Family

- 创建、编辑、删除 Kid Profile。
- 所有新建入口都必须采集 3–8 岁年龄；孩子自建时由年龄给出当前支持范围内的年级建议，首次设置与 Parent 编辑仍由家长明确选择年级，修改年龄不静默覆盖家长选择。
- 邀请或移除 Guardian。
- 查看同步状态、待同步修改数和最近一次成功时间；每台设备分别显示是否需要重新注册声纹。
- 在当前设备重新注册或删除声纹；声纹模板不跨设备复制。
- 删除 Profile 时向所有设备传播 tombstone，防止离线旧设备把资料重新上传。

### Settings

- Quest：四个题量、New/Review 顺序、紧急阈值
- Audio & Voice：麦克风测试、声纹重新注册、发音预览
- Worlds：Starter World、手动解锁
- Notifications：按 Profile 设置时间与免打扰
- Accessibility：Reduce Motion、Calm Emergency、左手布局
- Family & Sync：成员、权限、同步状态
- Privacy & Data：导出、删除、声纹说明

## 15. 遗忘曲线与 Review 调度

每个 `Kid Profile × Word × Mode` 独立维护：

- `difficulty`
- `stabilityDays`
- `lastIndependentSuccessAt`
- `predictedRecall`
- `nextDueAt`
- `lapseCount`

以艾宾浩斯遗忘曲线形式作为核心：

```text
R(t) = exp(-t / stability)
```

正确、错误、Help、有效反应时间和发音重播次数会改变 `stability` 与 `difficulty`；不会把 1、3、7 天写死为固定日历。

### Review 排序

1. 已越过预计遗忘点的词
2. 有效错误率高的词
3. 相对个人基线明显偏慢的词
4. 使用 Help、重试或发音重播较多的词
5. 接触次数不足的词
6. 当前 New 阶段刚出现问题的词

`Mastered` 是展示标签，不是永久毕业。默认要求至少三次跨日独立成功，并且模型预计未来 14 天仍能保持目标记忆率；之后仍会根据预测重新进入 Review。

## 16. 事件、计分与可重算状态

每次有效或技术尝试写入不可变 `AttemptEvent`：

```text
eventID, profileID, questID, wordID
mode: read | write
phase: new | review
result: correct | incorrect | helped | technicalRetry
technicalReason
validRetryIndex
promptAt, validInputAt, submittedAt
technicalHoldMs, scoreEligibleMs
speakerConfidence, recognitionConfidence
modelVersion, schedulerVersion, deviceID
```

硬性不变量：

- `technicalRetry` 不消耗有效重试。
- 不进入正确率或速度分母。
- 不更新遗忘曲线。
- 不减少分数或星星。
- 同步、算法和报告都从不可变事件重算，避免版本升级破坏历史。

## 17. 离线、同步与家庭共享

### 本地优先

- Quest 永远先写本地，CloudKit 不得阻塞孩子答题。
- 离线时可以完成全部核心功能。
- 本地提交后把 Profile 标记到持久 outbox；恢复网络、App 回到前台或家长点击 `Sync now` 后重试。
- Attempt、QuestCompletion、RewardGrant 使用不可变 UUID 事件。
- Profile、Pool membership 和 Settings 使用持久逻辑 revision 与 device ID 做确定性合并，不能只依赖设备时钟。
- Attempt / Correction 合并后从事件历史重算 WordProgress 与遗忘曲线；竞争的 progress snapshot 不是权威数据。
- Today completion、Daily Plan 与 Reward 使用 Profile + Mode/World + LocalDay 的稳定业务 key，离线双设备完成也只能计一次 Today 奖励。
- 重复 Word 在同步后由 `Profile + Mode + normalized word` 合并；Read 与 Write 的同名词仍是两个独立学习对象。
- 同步状态、待处理数量、最近成功时间和可恢复错误在重启后仍可见；孩子做题页面不弹同步阻塞框。

v0.7.0 保持可检查的本地 JSON snapshot 作为运行真源，通过私有库和共享库各自持久化的 `CKSyncEngine`、耐崩溃 outbox/inbox 与 Profile 级 apply transaction 同步，不引入 Core Data 或自建服务器。完整 record scope、合并规则、删除与分层验收见 [ADR-0001](Docs/ADR-0001-CROSS-DEVICE-FAMILY-SYNC.md)、[数据清单](Docs/FAMILY-SYNC-DATA-MANIFEST.md)和[验收矩阵](Docs/FAMILY-SYNC-ACCEPTANCE-COVERAGE.md)。

Family Sync 页面在 production Release 中使用 Apple `UICloudSharingController` 管理现有共享。入口先通过 Parent Gate 与系统敏感操作认证，再按持久化 binding 将 owner 路由到 private database、participant 路由到 shared database；revoked、deleted 或 malformed binding 一律 fail closed，不能静默新建 private fallback。系统页面保存或停止共享后，通过与 background notification 相同的幂等 reconciliation/receipt/UI refresh 路径更新 App。LocalQA 和普通 simulator 不注入该入口。

### 同一 Apple ID

- 使用 CloudKit private database 自动同步 Profile 数据。
- 家长在每台设备分别 opt in 后，同步 Profile/头像、Read/Write Pool、设置、Attempt/Correction、Calendar completion 和 Reward。
- 最近使用的 Profile、系统通知实例、声纹、图片提示和教师发音缓存保持设备本地。

### 不同 Apple ID

- 通过 `CKShare` 明确邀请和接受；属于 Apple Family 不会自动获得 App 数据。
- 一名 Kid Profile 对应一个共享对象图。
- Owner Guardian 拥有根 Profile；其他 Guardian 获得读写权限。
- CloudKit 的原生 participant 权限只有只读/读写，因此 V1 不把独立儿童 Apple ID 加入为可写 participant。[CloudKit sharing](https://developer.apple.com/documentation/cloudkit/sharing-cloudkit-data-with-other-icloud-users)

## 18. 声纹与可重下载资产的设备隔离

- 原始录音不持久化、不上传。
- 声纹模板只保存在当前设备 Keychain；Profile 同步时导出 `notEnrolled`，导入时保留接收设备自己的 enrollment 状态。
- 新 iPhone/iPad 需要为同一个 Kid Profile 单独完成一次声纹注册；声纹不可用不能阻塞学习历史同步。
- 具体词图片和未来的远端 audio 补包只写入 App `Caches`，不进入 CloudKit。首发 500 词的 Katie 双语速音频随 App bundle 离线分发；bundle 外的家长自定义词使用本机 Apple 英语女声 fallback。两类音频都不进入家庭同步数据。
- Avatar 原图属于家长明确选择的 Profile 数据，不是 cache；Family Sync 开启后以最大 512 px、256 KiB 的 prepared JPEG 独立 `CKAsset` 同步。通用 envelope 只携带引用与校验元数据，损坏或身份不匹配的 asset 被隔离且不会覆盖现有头像。

## 19. 通知

Guardian 可按 Profile 开启：

- 每日学习提醒
- Read / Write Pool 即将为空
- 当天 Quest 完成状态
- 同步失败
- 长期问题词的每周摘要

默认规则：

- 不向 Kid 发送催促通知。
- 锁屏不显示儿童昵称、具体单词、分数或声纹信息。
- 支持免打扰时段和全部关闭。

## 20. 设计系统

### 三层 Token

```text
Primitive → Semantic → Component
```

- Primitive：颜色、间距、字号、圆角、阴影、动效时间。
- Semantic：Read、Write、Success、Attention、Surface、Ink。
- Component：Quest Card、Mic Button、Writing Canvas、Timer、Star Rail、Reward Card。
- World Pack 只覆盖 theme semantic tokens，不改变组件结构和功能颜色。

### 核心视觉 Token

| Token | 默认用途 |
|---|---|
| `surface.canvas` | 温暖的浅奶油背景 |
| `ink.primary` | 深蓝灰文字 |
| `action.read` | 清晰蓝色 |
| `action.write` | 柔和紫色 |
| `feedback.correct` | 青绿色 |
| `feedback.attention` | 琥珀色，不使用刺眼红色 |
| `radius.child` | 24–32 pt 大圆角 |
| `touch.child` | 至少 72 × 72 pt |
| `touch.guardian` | 至少 44 × 44 pt |

### 字体与文字

- Kid UI 使用清晰、圆润但不过度卡通的系统字体。
- 目标单词使用最高对比度和稳定字形，不使用装饰字体。
- iPad Read 单词建议 96–128 pt；iPhone 横屏建议 64–88 pt。
- Guardian 支持 Dynamic Type。

### 动效

- 点按反馈：约 120–180 ms。
- 正确答案微动画：1–2 秒。
- 永久收藏品揭晓：不超过 3 秒，可跳过。
- 紧急状态不使用闪烁或强烈屏幕抖动。
- 支持 Reduce Motion。

### 音效与背景乐

Todo Math 仅作为“儿童可以独立理解、游戏反馈即时、背景音乐可由家长关闭”的交互参考；Tada Words 的旋律、音色组合、口播、音效与录音均须原创。[Todo Math 官方介绍](https://todomath.com/) · [Todo Math 背景音乐设置](https://todomath.zendesk.com/hc/en-us/articles/360022343054-I-can-t-hear-any-sound)

#### 启动声音标识

- 每次冷启动播放约 1.5–2 秒的原创 sonic logo，并用 Aurora 离线录制的一条连续短句清楚喊出 **`Ta-dá↗ woooords↘!`**（近似“它达，沃尔子”）。
- `da` 略拉长并上扬，随后不做刻意逗号停顿，直接连入明显拉长且下落的 `wor`；整体兴奋有朝气，同时不得出现多个排队 utterance 的机械接缝。
- 启动成品不依赖标点让 TTS 猜语调：第一拍必须是轻、短、近似平调的 `/tə/`（听感接近“他”，不得读成先高后低的“塔”）；第二拍使用一段不重复的连续 `/dɑː/` 元音，以连续 pitch map 拉长上扬（听感接近“达～”），不得通过复制元音产生额外的 `a` 重音；随后用仅供消除 click 的 8ms crossfade 直接接入逐级下落的 `words`。任何两词之间可检测的静音都视为失败。
- 正常启动固定使用 Cartesia Aurora 声线，确保所有设备的品牌读法一致；资源损坏或缺失时才使用确定性的 Apple 美式女声回退，不能静音或联网临时合成。
- 结尾配器和环境尾音跟随当前选中的 World Pack；尚未选择 Starter World 时使用中性的品牌版本。
- 不模仿 Todo Math 的旋律、节奏、声音演员或任何真人声线。
- 从后台短暂返回时不重复播放，避免频繁打扰。
- Guardian 可以关闭启动口播。

#### 背景音乐

- 每个 World Pack 拥有独立的原创音乐主题和乐器组合，奖励音色不跨 World 混用。
- 孩子切换 World 后，Lobby、Read、Write、结算页和 Collection 的音乐与环境声立即切换为该 World 的声音皮肤。
- 正常状态使用轻快但低密度的循环，不与 TTS、孩子朗读或书写节奏争夺注意力。
- 紧急状态使用同一原创主题的加速或加层版本，平滑切换；不突然增大音量、不加入警报声。
- TTS、Help 和标准发音播放时，背景乐自动 ducking。
- Read `Hear it`、Write 自动提示和 Parent 试听优先使用 500 词离线包：Katie 是 canonical teacher，Read 与 Write 均按正常语速的 `1/1.5 ≈ 0.67×` 生成，并在文件尾保留 120ms 安全 padding，确保 `at` 的 `/t/` 等尾辅音释放完成后才结束播放。若双识别审计确认某个孤立词的 canonical 输出不清楚，允许在 manifest 中记录单词级 voice/speed override；首包仅 `bun` 使用 Aurora。每词两个版本不可互换；未覆盖词使用同一条 Apple 美式女声 fallback。播放期间切到 spoken-audio session 并同时压低 App 音乐与外部音频，结束后再恢复混音。
- Read 开始录音前快速淡出背景乐和非必要环境音；录音结束后再平滑恢复，避免影响降噪和识别。

#### 功能音效

- 点击、正确、重试、星星和收藏品使用相同的功能语义，但具体音色与短旋律跟随当前 World。
- 点击：短、柔和、低刺激的触感音。
- 正确：先立即播放当前 World 的原创上行短音型，再依序轮换五条 Aurora 微庆祝语（如 `Yes!`、`You did it!`、`Nice one!`），避免连续重复同一句；transition 不使用 `Ta-da!` 一类感叹词。Reduced Sound 只保留必要非语言反馈并关闭这些装饰口播。
- 有效错误：温和的“再试一次”提示，不使用蜂鸣器或失败号角。
- `technicalRetry`：使用中性提示音，必须与孩子答错的声音明显不同。
- 三颗星：三段可区分但属于同一声音家族的揭晓音。
- Quest 结算：星星仍使用当前 World 的专属音色，完成时增加 Aurora 的短句 `Quest complete!`；不追加 `Ta-da!`，也不做随机稀有度音效。
- 每个非末尾单词答完后，必须等待当前 World 短音型和 Aurora 微庆祝语完整结束，再留出 700ms 的清晰呼吸停顿，之后才可显示并朗读下一个 Write 单词；Read 与 Write 使用同一时序规则。最后一个单词不额外等待这段 inter-item 停顿，直接进入 Quest 结算。
- 三种书写工具使用原创的短促摩擦/颗粒音色，并按实际移动节流；Reduced Sound 关闭这些装饰性书写音，提示发音播放时也不叠加。

#### 首发 World 的声音方向

| World | 声音方向 |
|---|---|
| Moonpetal Kingdom | 约 100 BPM 的欢快原创循环；竖琴、钟琴、低音脉冲、轻鼓、柔和刷奏与魔法闪光音；场景加入两侧彩虹、云朵与独角兽，中央学习安全区保持清晰 |
| Build-It Bay | 木块、轻打击乐、柔和机械节奏与安全的工程完成音 |
| Paws & Pines | 马林巴、原声拨弦、鸟鸣和温和自然环境声 |
| Dino Discovery | 约 80 BPM 的丛林踏步、马林巴与温和低音，不使用吓人的吼叫 |
| Firehouse Heroes | 约 120 BPM 的欢快巡游节奏，不使用警报器或刺耳警笛 |
| Brickwork City | 约 120 BPM 的木质积木律动与拼搭音色，不借用商业玩具品牌声音 |
| Frostlight World | 约 75 BPM 的冰晶钟琴华尔兹与轻盈双倍细分 |
| Coaster Carnival | 约 150 BPM 的升降拨弦与游园节奏，保持安全峰值和语音空间 |

标准美式单词发音、Help 口播和必要教学提示不随 World 更换声音演员或发音方式，确保孩子形成稳定的听觉参照。

#### 控制与安全

- Guardian 可分别控制 `Voice`、`Music` 和 `Sound Effects`。
- 默认音量经过响度归一化，不出现突然的峰值。
- Reduce Motion 不影响必要声音提示；另提供独立的 Reduced Sound 模式。
- 所有音频资产保留来源、作者、授权和版本记录；外购音效必须具有明确的 App 商用许可。

### 可访问性

- 反馈同时依赖声音、图形和动作，不只靠颜色。
- Guardian 支持 VoiceOver 与 Dynamic Type。
- 提供左手布局，避免按钮位于主要手掌区域。
- 所有控件位置固定，加载或反馈时不发生布局跳动。

## 21. 通用组件状态

| 组件 | 核心状态 |
|---|---|
| Quest Card | ready, inProgress, completed, syncPending, disabled |
| Mic Button | idle, listening, checking, technicalRetry, disabled |
| Writing Canvas | empty, drawing, checking, correct, uncertain, retry |
| Timer | normal, emergency, paused |
| Star Rail | calibrating, earned, unearned |
| Reward Card | locked, revealed, collected |

禁用、加载、技术重试、有效错误必须有不同的视觉与语音反馈；不能用同一个“失败”状态覆盖。

## 22. Guardian 通知与隐私原则

- 原始音频永不离开设备。
- 声纹模板属于敏感的设备本地信息；注册、重新注册和删除均是 Guardian 操作，但不进入 Family Sync。
- Family Sync 开启后 Avatar 照片作为 Profile 数据同步；图片提示与教师发音 cache 不同步。
- 不接入广告 SDK 或第三方儿童行为追踪。
- Guardian 可以导出学习数据和彻底删除 Profile。
- 删除操作使用不含昵称、照片、单词或学习内容的最小 tombstone，同步到所有设备和共享成员；tombstone 无条件压过任何同 Profile ID 的旧资料，其他 CloudKit records 物理擦除。

## 23. V1 验收标准

### Child

- 4 岁孩子不阅读说明文字也能选择 Profile 和进入两个 Quest。
- 冷启动先显示 Profile；没有 Profile 时直接创建，已有 Profile 时突出上次选择但不跳过孩子确认。
- Read 与 Write 入口不会被误认为同一个任务。
- Read 第一次独立作答前保持安静；两次有效错误后才出现唯一的 `Hear it` Help。
- 完成 Read 题时，技术噪声不会被计为发音错误。
- 完成 Write 题时，停笔不会触发自动提交。
- Write 的教师发音清晰连贯，不会因过度减速或音频恢复过早而吞掉短词尾音。
- 孩子可以看见分数、较宽松的三颗星和主题奖励，并从 My Collection 选择已获得 Theme / Icon。
- 普通单击 Results Replay 会真正开始同模式 Practice Again。
- 超过阈值后可以继续完成，不出现失败倒计时。

### Guardian

- 可在 30 秒内通过逐词 typing、Camera / Photo OCR 或明确批准的 Preset selection 向任一 Pool 加词并试听。
- 新词即时出现在队列最前；可单删、多选批量删除、整组清空并 Undo，删除状态不会跨 Profile。
- 新建 Profile 必须明确选择 3–8 岁年龄；年龄与 Grade 只排序 Preset 建议。
- App 不会在空 Pool 或数量不足时自动生成、加入推荐词或补充单词。
- Both Preset 导入要么更新两个 Pool，要么只回滚本次变更，不影响既有 active word 或其他 Profile。
- 自动去重不会删除另一路线的同名词。
- 报告能解释某词为何进入 Review。
- 可以纠正自动识别误判。
- 可以管理多个 Kid Profile 和 Guardian。

### Data & Privacy

- 离线完成的 Quest 恢复网络后不会丢失或重复计奖。
- 同 Apple ID 与跨 Apple ID 共享均能同步。
- 原始儿童录音不写入持久存储或云端。
- 声纹模板保持每台设备独立；新设备只同步学习资料并重新注册声纹。
- 图片提示与教师发音 cache 不跨设备复制，必要时可安全重下载。
- 识别不确定、噪声和错误说话人不影响分数、星星或遗忘模型。
- 删除 Profile 后，离线旧设备不能把它重新创建出来。

### Technical Spikes before full build

1. 4 岁儿童单词识别、声纹过滤和家庭噪声下的本地准确率。
2. 4 岁儿童手写在目标词约束下的正确 / 错误 / 不确定三态阈值。
3. 不同 Apple ID 的 `CKShare`、ProfileKey 分发、撤销和密钥轮换。
4. 4 岁儿童在 iPhone 17 Pro Max 与目标 iPad 上的横屏手写、听感、布局与辅助功能可用性；iPad 自动化链路已通过，人工验收仍未完成。

## 24. V2

V2 增加 `Grade Curriculum`：

- Guardian 选择 Pre-K、Kindergarten、Grade 1 等水平。
- App 使用经过授权、可追溯的美国分级词库自动建立或推荐 Read / Write Pool。
- 与 Parent Words 共用去重、遗忘模型、学习记录和奖励。
- V1 数据模型预留 `source = parent | curriculum`。
- 新增同类别、不同美术方向的 World Pack。

V2 仍需单独确认分级标准、词库版权和 Read / Write 分类规则；不能由生成模型随意创造课程标准。

## 25. 已确认的敏感操作认证规则

采用分层认证：

- 日常进入 Guardian 区使用“普通单击 `Parents`＋随机算术题”。
- 下列敏感操作必须额外通过 Face ID、Touch ID 或设备密码；算术题不能替代系统认证：
  - 邀请或移除 Guardian
  - 导出儿童数据
  - 删除 Kid Profile 或声纹
  - 重新注册声纹或轮换加密密钥

如果设备没有设置可用的系统认证，仍允许进入普通 Guardian 报告和单词录入，但阻止以上敏感操作，并引导 Guardian 先设置设备密码。
