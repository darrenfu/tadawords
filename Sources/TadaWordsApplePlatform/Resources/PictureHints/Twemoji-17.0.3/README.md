# Bundled Twemoji picture hints

These 74 unmodified 72x72 PNG files are the unique assets referenced by
`WordPictureHintCatalog`. They are bundled so picture hints work on a fresh
offline install and never require a runtime CDN request.

- Source: <https://github.com/jdecked/twemoji>
- Tag: `v17.0.3`
- Commit: `b6b55fef1e8636b540a6d016a4729ca8cdf2e60b`
- Source path: `assets/72x72/<asset-code>.png`
- License: CC BY 4.0; see `LICENSE-GRAPHICS.txt`
- Modifications: none

`manifest.json` is the reviewable inventory. Tests require its unique asset
codes to equal the shipping domain catalog exactly and validate that every PNG
is present, decodable, and below the service's maximum asset size.
