# Tada Words — Design Review

> Review status: v0.2 device-feedback revision in progress; physical regression pending
>
> Scope reviewed: product, child UX, Guardian UX, learning design, accessibility, audio, architecture, and delivery risk

## Overall assessment

The core idea is strong: Read and Write are separate skills, practice requires real recall, technical failures do not punish the child, and rewards remain predictable. The current document is a solid product and interaction specification, but it is not yet a complete visual design and its original V1 scope combines three products:

1. a preschool word-learning app;
2. a cross-account biometric key-management system;
3. an eight-world content and reward platform.

The first executable milestone must validate the learning loop before the other two systems can delay or distort it.

## Phase 1 — Critical

### Learning evidence

- `Map the Word` may be used only for Write study. Read begins with a visible word and silence; no target audio plays before the child's first independent response.
- Record `studyExposed`, `firstIndependentAttempt`, `unaidedRetry`, `feedbackExposed`, `guidedRetry`, `helped`, `technicalRetry`, and `recognitionUncertain` separately.
- Only the first valid attempt before feedback contributes strong mastery evidence and strict Guardian accuracy. The child-facing Accuracy Star may additionally allow one first-answer miss followed immediately by one valid, unaided correct retry; that reward grace never rewrites mastery evidence.
- After one independent retry, provide the correct model before a guided retry; do not reinforce the same wrong response three times.
- A guided success earns completion feedback but not independent mastery.

### Review capacity

- Treat New counts as daily maximums, not guaranteed quotas.
- Due Review cannot be displaced by New.
- Same-session problem words may replace only not-yet-due Review items.
- Reduce New automatically when Review debt exceeds the attention budget.

### Ambiguous prompts

- An isolated sound is not always a unique spelling prompt (`right/write`, `one/won`, `sea/see`).
- Ambiguous Write words require a short spoken context or must be rejected in V1.
- Heteronyms (`read`, `lead`, `wind`) require an explicit pronunciation choice or must be rejected; the app must not silently select one pronunciation.

### Timing and stars

- Read timing begins when the word becomes visible and the recorder is ready; it ends at detected speech onset.
- Write timing begins after the first prompt, pauses during replay, and never resets.
- Persist first-stroke latency, active-stroke time, and idle time separately.
- Build separate pace baselines by mode, device class, input method, and word length.
- Pace is a comfortable personal band, not “faster is always better.” Accuracy must pass first.
- Calibration attempts with valid timing can earn Pace; after calibration, only the slow side receives 25% grace. The too-fast side remains strict.
- A technical retry never affects accuracy, pace, stars, or the scheduler.

### Child-facing hierarchy

- The World Lobby has two dominant actions only: `Read` and `Write`.
- Read uses a word + mouth/microphone visual; Write uses a speaker + handwriting-line/pencil visual.
- Quest backgrounds become visually quiet behind the task surface.
- Live numeric points are removed from the question screen; the final score is revealed at the end.
- Results reveal in one sequence: completion, stars, score, collectible, then optional world unlock.
- `Parents` uses a normal tap to open the math Parent Gate. Results Replay is a real button that starts same-mode Practice Again.

### Blocking and recovery states

Design explicit flows for:

- empty New Pool;
- no Review due;
- microphone permission denied;
- unavailable recognition model;
- excessive noise or wrong speaker;
- voice-template mismatch;
- muted audio;
- interrupted quest;
- sync pending or failed.

Technical states must always have a finite escape path; voice matching cannot create an infinite retry loop.

## Phase 2 — Refinement

- Produce independent iPhone 17 Pro Max landscape layouts; do not shrink the iPad layout.
- On Write, the canvas owns the center, audio and one-tap `?` use the prompt rail, Done uses the action edge, and a compact tool box selects four pens plus 12 colors. Undo is replaced by a 2.5× local eraser; Clear is immediate because the child explicitly chose a whole-canvas action.
- Reduce Guardian Today to profile switch, Read/Write cards, Manage Words, and one Needs Attention summary.
- Manage Words uses one-word Return-to-add, local Camera/Photo OCR review, a newest-first queue, and single/bulk delete with Undo. V1 never auto-adds Grade or smart-fill words.
- Unify terms: `Guardian`, `Read`, `Write`, and one public memory-state vocabulary.
- Define a complete token table: values for color, spacing, typography, radii, shadows, motion, layout, audio, and states.
- Define a World Pack contract: task-safe zone, motion budget, emergency variant, audio palette, and contrast thresholds.
- Use a neutral sonic logo on Profile Picker, then a short world sting after profile selection.

## Phase 3 — Polish

- Keep frequent correct feedback under one second and reserve longer animation for quest completion.
- Add haptic semantics for Done, correct, technical retry, star reveal, and world unlock.
- Test audio fatigue by playing two complete quests per world on real iPhone and iPad speakers.
- Do not automatically invert Kid Worlds in Dark Mode; Guardian Dark Mode needs its own semantic tokens.
- Complete nonblocking empty states for Collection, locked worlds, avatar permission, and claimed rewards.

## Architecture review

### Keep in the Learning Core

- local multi-profile data separation;
- Parent Words and independent Read/Write Pools;
- New/Review scheduling;
- neutral technical retry;
- score, stars, and deterministic rewards;
- local-first storage;
- UUID attempts and a current `WordProgress` snapshot;
- theme tokens and swappable world skins.

### Build later in the final V1 sequence

- same-Apple-ID iCloud sync;
- cross-Apple-ID Guardian sharing;
- encrypted voice-template sync and key rotation;
- full 7/30-day reports;
- the full 60 small rewards and 15 milestones.

### First vertical slice

- one sample Kid Profile;
- three thin, selectable world skins;
- two unmistakable Read/Write entry cards;
- mockable speech and handwriting recognition protocols;
- one Read quest and one Write quest;
- first-attempt event semantics;
- simple due-review prioritization;
- attainable three-star results and one collectible per world;
- local persistence boundary with in-memory implementation for previews and tests.

## Required technical spikes

1. Child ASR under Mandarin-L1 pronunciation and home noise.
2. Child/adult voice-template filtering without blocking the child.
3. Conservative three-state handwriting recognition.
4. iPhone 17 Pro Max landscape writing ergonomics.
5. CloudKit sharing and encrypted key lifecycle threat model.

## Kill criteria

- Incorrect word false acceptance above 2% disables automatic Read scoring.
- Incorrect spelling false acceptance above 2% disables automatic Write scoring.
- Voice filtering rejects the enrolled child above 10% of valid attempts, so it cannot be a gate.
- Any duplicate reward or lost attempt in offline merge testing blocks cloud sync release.
- Cross-account voice-template sync cannot ship without a written threat model, recovery drill, revocation test, and independent security review.
- World asset production must be reduced if it delays the first real-child usability test by more than two weeks.

## What “design complete” means next

Current requirements are versioned in `FOLLOWUP_BUGFIXES_AND_IMPROVEMENTS.md`. Visual design is complete only after the v0.2 physical build proves that:

- the target child distinguishes Read from Write without explanation;
- iPhone handwriting is comfortable for short, medium, and long words;
- listening, checking, valid retry, and technical retry are distinguishable;
- the relaxed recovery and Pace rules reward effort without changing strict Guardian evidence;
- emergency mode does not cause rushing;
- a Guardian can type, scan, review, and delete a list without layout clipping;
- Read help remains hidden until two valid errors, then places a reliable picture beside the word;
- the next-day Theme/Icon unlock is understandable and My Collection lets the child select only earned cosmetics;
- all three worlds preserve task contrast and component placement.
