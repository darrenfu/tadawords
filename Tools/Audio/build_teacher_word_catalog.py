#!/usr/bin/env python3
"""Build the reviewed 2,000-offline / 4,000-online teacher-word catalog."""

from __future__ import annotations

import hashlib
import json
import re
import sys
from importlib.metadata import version
from pathlib import Path

from wordfreq import top_n_list


EXPECTED_WORDFREQ_VERSION = "3.1.1"
EXPECTED_DICTIONARY_SHA256 = (
    "be41ad97963bf8dabedd5871d5d691596175269d540956b0f9965a885c2bbab9"
)
WORD_PATTERN = re.compile(r"^[a-z]+(?:['-][a-z]+)*$")
BLOCKED_BELLA_WORDS = {
    "ass",
    "asshole",
    "bitch",
    "bitches",
    "bullshit",
    "cock",
    "cocks",
    "condom",
    "cunt",
    "dick",
    "fuck",
    "fucked",
    "fucker",
    "fucking",
    "motherfucker",
    "nigga",
    "nigger",
    "porn",
    "porno",
    "pornography",
    "prostitute",
    "prostitution",
    "pussy",
    "rape",
    "raped",
    "rapist",
    "shit",
    "shitty",
    "slut",
    "sex",
    "sexual",
    "sexy",
    "suicide",
    "vagina",
    "penis",
    "whore",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def nested_words(value: object) -> list[str]:
    words: list[str] = []
    if isinstance(value, dict):
        raw_words = value.get("words")
        if isinstance(raw_words, list):
            words.extend(word for word in raw_words if isinstance(word, str))
        for child in value.values():
            words.extend(nested_words(child))
    elif isinstance(value, list):
        for child in value:
            words.extend(nested_words(child))
    return words


def normalized(words: list[str]) -> set[str]:
    result = {word.strip().lower() for word in words}
    invalid = sorted(
        word for word in result if len(word) > 32 or not WORD_PATTERN.fullmatch(word)
    )
    if invalid:
        raise ValueError(f"invalid isolated words: {invalid[:10]}")
    return result


def append_until(
    destination: list[str],
    candidates: list[str],
    target_count: int | None = None,
) -> None:
    seen = set(destination)
    for word in candidates:
        if target_count is not None and len(destination) >= target_count:
            return
        if word not in seen:
            destination.append(word)
            seen.add(word)


def main() -> int:
    if version("wordfreq") != EXPECTED_WORDFREQ_VERSION:
        raise RuntimeError(
            f"install wordfreq=={EXPECTED_WORDFREQ_VERSION} before building"
        )

    repository_root = Path(__file__).resolve().parents[2]
    existing_manifest_path = repository_root / (
        "Sources/TadaWordsApplePlatform/Resources/Audio/TeacherWords/"
        "ElevenLabs-Teacher-500-v1/manifest.json"
    )
    presets_path = repository_root / (
        "Sources/TadaWordsContent/Resources/PresetWords.json"
    )
    dictionary_path = Path("/usr/share/dict/web2")
    output_path = repository_root / (
        "Tools/Audio/Catalogs/TeacherWordCatalog-4000-v1.json"
    )

    if sha256(dictionary_path) != EXPECTED_DICTIONARY_SHA256:
        raise RuntimeError("the pinned lowercase-lexicon filter changed")

    existing_manifest = json.loads(existing_manifest_path.read_text())
    presets = json.loads(presets_path.read_text())
    bundled = normalized(existing_manifest["words"])
    preset_words = normalized(nested_words(presets))
    if len(bundled) != 500 or len(preset_words) != 1_166:
        raise RuntimeError("the frozen 500-word pack or 1,166-word preset changed")

    dictionary_words = {
        word
        for raw_word in dictionary_path.read_text(errors="ignore").splitlines()
        if (word := raw_word.strip()) == word.lower()
    }
    ranked = []
    ranked_seen: set[str] = set()
    for raw_word in top_n_list("en", 50_000, ascii_only=True):
        word = raw_word.lower()
        if (
            word not in ranked_seen
            and word in dictionary_words
            and word not in BLOCKED_BELLA_WORDS
            and (len(word) >= 3 or word in bundled or word in preset_words)
            and len(word) <= 32
            and WORD_PATTERN.fullmatch(word)
        ):
            ranked.append(word)
            ranked_seen.add(word)

    offline: list[str] = []
    append_until(offline, [word for word in ranked if word in bundled])
    append_until(offline, sorted(bundled))
    append_until(offline, ranked, target_count=2_000)

    online = list(offline)
    append_until(online, [word for word in ranked if word in preset_words])
    append_until(online, sorted(preset_words))
    append_until(online, ranked, target_count=4_000)

    if len(offline) != 2_000 or len(online) != 4_000:
        raise RuntimeError("catalog did not reach the frozen tier sizes")
    if not bundled.issubset(offline) or not preset_words.issubset(online):
        raise RuntimeError("catalog lost a shipping or preset word")
    if BLOCKED_BELLA_WORDS.intersection(online):
        raise RuntimeError("blocked Bella words entered the online catalog")

    two_variant_characters = 2 * sum(map(len, online))
    existing_characters = 2 * sum(map(len, bundled))
    payload = {
        "schemaVersion": 1,
        "contractVersion": "elevenlabs-teacher-v1",
        "locale": "en-US",
        "selection": {
            "wordfreqVersion": EXPECTED_WORDFREQ_VERSION,
            "wordfreqLicense": "CC-BY-SA-4.0 data; Apache-2.0 code",
            "wordfreqURL": "https://github.com/rspeer/wordfreq",
            "dictionaryPath": str(dictionary_path),
            "dictionarySHA256": EXPECTED_DICTIONARY_SHA256,
            "policy": (
                "Preserve the existing 500 bundled words and all 1,166 preset "
                "words, then fill by wordfreq rank after lowercase dictionary "
                "membership and the reviewed Bella blocklist."
            ),
        },
        "counts": {
            "offlineWords": len(offline),
            "onlineWords": len(online),
            "existingBundledWords": len(bundled),
            "presetWords": len(preset_words),
            "twoVariantCharacters": two_variant_characters,
            "newTwoVariantCharacters": two_variant_characters
            - existing_characters,
        },
        "offlineWords": offline,
        "onlineWords": online,
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(payload, indent=2, ensure_ascii=True) + "\n",
        encoding="utf-8",
    )
    print(
        f"wrote {len(offline)} offline / {len(online)} online words; "
        f"{two_variant_characters - existing_characters} new credits"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
