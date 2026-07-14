#!/usr/bin/env python3
"""Render the bundled preset catalog as an Obsidian-friendly Markdown note."""

from __future__ import annotations

import argparse
import json
from datetime import date
from pathlib import Path
from typing import Any


GRADE_LABELS = {
    "preK": "Pre-K",
    "kindergarten": "Kindergarten",
    "grade1": "Grade 1",
    "grade2": "Grade 2",
    "grade3": "Grade 3",
}


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export PresetWords.json to an Obsidian Markdown note."
    )
    parser.add_argument("--catalog", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--catalog-version", default="v0.3.1")
    parser.add_argument("--generated-on", default=date.today().isoformat())
    return parser.parse_args()


def leaf_lists(category: dict[str, Any]) -> list[dict[str, Any]]:
    lists = list(category.get("lists", []))
    for child in category.get("children", []):
        lists.extend(leaf_lists(child))
    return lists


def audience_text(audience: dict[str, Any]) -> str:
    grades = [GRADE_LABELS.get(value, value) for value in audience.get("grades", [])]
    grade_text = ", ".join(grades) if grades else "All grades"
    minimum = audience.get("minimumAge")
    maximum = audience.get("maximumAge")
    if minimum is not None and maximum is not None:
        age_text = f"ages {minimum}–{maximum}"
    elif minimum is not None:
        age_text = f"age {minimum}+"
    elif maximum is not None:
        age_text = f"up to age {maximum}"
    else:
        age_text = "all ages"
    return f"{grade_text}; {age_text}"


def render_category(
    lines: list[str], category: dict[str, Any], depth: int, source_titles: dict[str, str]
) -> None:
    lines.extend([f"{'#' * depth} {category['title']}", ""])
    if category.get("summary"):
        lines.extend([category["summary"], ""])

    for preset in category.get("lists", []):
        lines.extend(
            [
                f"{'#' * (depth + 1)} {preset['title']}",
                "",
                f"> [!summary] {len(preset['words'])} words · {audience_text(preset['audience'])}",
                f"> {preset['summary']}",
            ]
        )
        source_names = [
            source_titles[source_id]
            for source_id in preset.get("sourceIDs", [])
            if source_id in source_titles
        ]
        if source_names:
            lines.append(f"> Method references: {', '.join(source_names)}")
        lines.append("")
        lines.extend(
            f"{index}. {word}"
            for index, word in enumerate(preset["words"], start=1)
        )
        lines.append("")

    for child in category.get("children", []):
        render_category(lines, child, depth + 1, source_titles)


def render_markdown(catalog: dict[str, Any], version: str, generated_on: str) -> str:
    lists = [
        preset
        for root in catalog.get("roots", [])
        for preset in leaf_lists(root)
    ]
    word_references = [word for preset in lists for word in preset["words"]]
    unique_words = {word.casefold() for word in word_references}
    sources = catalog.get("sources", [])
    source_titles = {source["id"]: source["title"] for source in sources}

    lines = [
        "---",
        "title: Tada Words Preset Word Catalog",
        "aliases:",
        "  - Tada Words word presets",
        "tags:",
        "  - tada-words",
        "  - early-literacy",
        "  - vocabulary",
        f"catalog_version: {version}",
        f"generated_on: {generated_on}",
        "---",
        "",
        "# Tada Words Preset Word Catalog",
        "",
        "> [!info] Parent-controlled presets",
        "> These lists are suggestions only. Tada Words never adds a word to a Kid's Read or Write Pool until a parent explicitly selects it and taps Add.",
        "",
        "## Catalog overview",
        "",
        f"- Root categories: {len(catalog.get('roots', []))}",
        f"- Leaf presets: {len(lists)}",
        f"- Word references: {len(word_references)}",
        f"- Unique normalized words: {len(unique_words)}",
        "- Intended range: ages 3–8, Pre-K through Grade 3",
        "- Every leaf preset contains 30–50 independently curated single words.",
        "",
        "> [!note] How recommendations work",
        "> Age and grade only rank suitable presets first. They do not measure a child, override the parent's judgment, or add words automatically. The same word may appear in more than one useful topic; Pool import de-duplicates it case-insensitively.",
        "",
    ]

    for root in catalog.get("roots", []):
        render_category(lines, root, 2, source_titles)

    lines.extend(
        [
            "## Method and sources",
            "",
            "The catalog is an original Tada Words selection and arrangement. Educational references guide age/skill scope; no branded commercial word list is copied wholesale.",
            "",
        ]
    )
    for source in sources:
        note = f" — {source['note']}" if source.get("note") else ""
        lines.append(f"- [{source['title']}]({source['url']}){note}")

    lines.extend(
        [
            "",
            "## Maintenance",
            "",
            "This note is generated from `Sources/TadaWordsContent/Resources/PresetWords.json` by `Scripts/export_preset_catalog.py`. Edit and audit the JSON source, then regenerate this note so the App and Obsidian stay aligned.",
            "",
        ]
    )
    return "\n".join(lines)


def main() -> None:
    arguments = parse_arguments()
    with arguments.catalog.open(encoding="utf-8") as catalog_file:
        catalog = json.load(catalog_file)
    markdown = render_markdown(
        catalog,
        version=arguments.catalog_version,
        generated_on=arguments.generated_on,
    )
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(markdown, encoding="utf-8")


if __name__ == "__main__":
    main()
