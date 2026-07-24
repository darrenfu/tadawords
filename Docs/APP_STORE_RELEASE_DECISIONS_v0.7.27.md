# App Store 1.0 distribution decisions — v0.7.27

> **Decision record only.** This document does not enter values in App Store
> Connect, submit a build, or authorize public release.

## Owner decision

The release owner approved the distribution values on 2026-07-21 and updated
the public product age range to **3–8** on 2026-07-23 for the first public
Tada Words 1.0 release:

| Field | Approved value | Operational constraint |
| --- | --- | --- |
| Kids positioning | **Made for Kids** | This selection and the age band cannot be changed after App Review approval. All later updates must continue to satisfy the Kids Category rules. |
| Product age range | **3–8** | Product copy and every profile creation/edit surface must use this complete range. |
| Apple Kids Category band | **Owner selection required before approval: `5 and under` or `6–8`** | Apple Kids Category supports one primary band, not a combined 3–8 value. Do not misrepresent the product as an unsupported App Store Connect value. |
| Price | **Free** | Do not configure a paid price. |
| Monetization | **No IAP, subscription, advertising, or paid unlock in 1.0** | A later monetization change requires a fresh Kids, privacy, metadata, and review audit. |
| Initial availability | **United States only** | Do not select all countries or regions, any EU storefront, or a pre-order. Expansion is a later reviewed change. |
| EU launch | **Excluded from 1.0** | Issue #23 still owns the account-level DSA trader-status declaration; this record does not invent a trader classification. |
| Release method | **Manually release this version** | After approval, keep the version in Pending Developer Release until the separately authorized #26 release step. Do not select automatic or scheduled automatic release. |

The age-rating questionnaire, metadata, screenshots, privacy plan, pricing and
availability fields, and release checklist must describe product ages 3–8.
The release owner must choose the closest single Apple Kids Category band
before the irreversible post-approval lock. Issue #65 owns entry and
exact-release reconciliation in App Store Connect. Issue #26 continues to own
Add for Review, Submit for Review, and the final manual release.

## Evidence boundary

- This decision is durable product evidence, not proof that App Store Connect
  currently contains the values.
- United States-only availability narrows the launch-jurisdiction review, but
  it does not itself resolve COPPA or state age-assurance questions. Issues #61
  and #76 own those decisions.
- The Kids Category parental gate is not treated as verified parental consent
  under children's privacy law.
- Any storefront expansion, monetization, SDK, advertising, analytics, privacy,
  or child-data-flow change reopens the affected review before release.

## Apple sources checked 2026-07-21

- [Set an app age rating](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating)
  documents Made for Kids and states that the selection cannot be changed after
  App Review approval.
- [Categories and Discoverability](https://developer.apple.com/app-store/categories/)
  defines the Kids Category primary-audience bands as 5 and under, 6–8, and
  9–11.
- [Manage availability for your app](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store)
  permits a specific country or region set instead of all storefronts.
- [Select an App Store version release option](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option)
  documents manual release and Pending Developer Release.
- [Manage EU DSA trader requirements](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/)
  distinguishes the account-level declaration from app distribution in EU
  territories.

## Rollback

Before App Review approval, the owner can replace this record with a new
explicit decision and repeat every dependent audit. After approval, the Made
for Kids selection and age band are not treated as reversible. Storefront and
pricing expansion remain later App Store Connect changes, but require their own
legal, privacy, metadata, and release review.
