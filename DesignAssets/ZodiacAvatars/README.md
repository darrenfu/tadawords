# Zodiac Profile Avatars

This directory preserves the source sheet and generation provenance for the
twelve starter Profile avatars shipped in Tada Words.

## Source and rights

- Generated for Pawgoo LLC with OpenAI image generation on July 20, 2026.
- The prompt requested original character designs with a warm, whimsical,
  hand-painted storybook-animation feeling.
- The prompt explicitly prohibited existing film characters, mascots, logos,
  costumes, and recognizable protected compositions.
- No third-party artwork was supplied as a reference or incorporated into the
  generation.
- The resulting sheet was visually reviewed for the requested animals, order,
  clean crop boundaries, and absence of text or recognizable third-party
  characters.

The generated source is `zodiac-avatar-master.png`, SHA-256 recorded below:

```text
2a5f98313e325f8875bd522cee7dbe9491595564db10b9e82331178b8f183168  zodiac-avatar-master.png
```

## Export contract

The source is a 1448 × 1086 PNG arranged as 4 columns × 3 rows. Every tile is
362 × 362 pixels, in canonical zodiac order:

1. Rat, Ox, Tiger, Rabbit
2. Dragon, Snake, Horse, Goat
3. Monkey, Rooster, Dog, Pig

Each tile was cropped losslessly by coordinate and stripped of ancillary PNG
metadata before being added to `Apps/TadaWordsApp/Assets.xcassets` as a
universal raster image. The app clips the square art to circles where needed;
the original square remains available for card layouts.

## Generation prompt

> Create one production-ready 4 by 3 sprite sheet of twelve ORIGINAL
> children's profile avatar illustrations for an early-learning iOS app. Exact
> grid and exact order: row 1 = rat, ox, tiger, rabbit; row 2 = Chinese dragon,
> snake, horse, goat; row 3 = monkey, rooster, dog, pig. One animal per equal
> square tile, centered bust portrait facing slightly toward the viewer, full
> head and ears/horns safely inside each tile with generous padding. Warm
> whimsical hand-painted storybook animation feeling, soft watercolor and
> gouache texture, gentle natural expressions, cozy sunlit palette, expressive
> but simple shapes for ages 3–8. Cohesive art direction across all twelve while
> each animal has a distinct accent color. ORIGINAL character designs only: do
> not depict or imitate any existing film character, mascot, logo, costume, or
> recognizable protected composition. No humans. No props crossing tile
> boundaries. No words, letters, numbers, zodiac symbols, borders, dividers,
> frames, drop shadows, or labels. Every tile has the same flat warm ivory
> background (#FFF7E8) extending cleanly to edges, with no texture at the crop
> edges. Pixel-clean equal spacing so the sheet can be mechanically cropped into
> 12 square icons.
