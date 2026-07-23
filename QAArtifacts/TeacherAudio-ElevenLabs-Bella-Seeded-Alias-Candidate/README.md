# ElevenLabs Bella seeded pronunciation candidate

This directory is automated and human-listening evidence for issue #74, not
an approved shipping pack. It uses Bella, canonical seed `20260725`, and the
proposed aliases `a → ay`, `i → eye`, and `come → kum`. The word `bun` remains
unaltered because Bella with this seed transcribes it correctly.

The candidate becomes canonical only after explicit human listening approval,
creation of a versioned ElevenLabs pronunciation dictionary, and all
shipping-pack gates.

Automated inspection passed for all 18 clips: MP3, 44.1 kHz, 128 kbps, mono,
duration 0.743039–1.068118 seconds, and protected trailing silence
0.143605–0.449977 seconds. Apple's local English SpeechTranscriber returned
the intended word for every representative Read and Write clip; the expected
homophone normalization is `a/ay → I` and `i/eye → I`.

The Read and Write files are byte-identical by design because the child hears
the same teacher pronunciation in both contexts.
