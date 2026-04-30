# ThePerch website — feedback for Claudinho

Audit of `https://whoisthisfabio.com/ThePerch/` as of 2026-04-29 evening.

The site is in good shape — strong voice, clean editorial layout, no JS, all-inline CSS, fast first paint. The brand identity (Editorial Linen palette, Fraunces italic, indigo + coral) reads consistently with the iOS app, which is rare and good. Below are concrete improvements ranked by impact.

---

## Tier 1 — ship before public flip (≤30 min total)

These are the highest-leverage. Most are 1–10 line CSS or HTML edits.

### 1. Add OpenGraph + Twitter Card meta tags

Currently the page has zero social-preview metadata. When the GitHub-public link gets shared on Twitter / Slack / iMessage, it'll render as a naked URL.

Add to `<head>`:
```html
<meta property="og:type" content="website">
<meta property="og:title" content="The Perch — your data. your machine.">
<meta property="og:description" content="A personal life dashboard for iOS, powered by small agents you run yourself.">
<meta property="og:url" content="https://whoisthisfabio.com/ThePerch/">
<meta property="og:image" content="https://whoisthisfabio.com/ThePerch/perch-hero-today-a1.jpg">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="The Perch — your data. your machine.">
<meta name="twitter:description" content="A personal life dashboard for iOS, powered by small agents you run yourself.">
<meta name="twitter:image" content="https://whoisthisfabio.com/ThePerch/perch-hero-today-a1.jpg">
<link rel="canonical" href="https://whoisthisfabio.com/ThePerch/">
<meta name="theme-color" content="#EFD8D5">
```

Note: `perch-hero-today-a1.jpg` is a portrait phone screenshot, not 1200×630. For the OG card, render a separate landscape 1200×630 social card with the headline + a phone screenshot off to one side. If that's too much work for now, the portrait will display, just letterboxed.

### 2. Fix the hero copy stack

Right now the hero shows three iterations of the same thesis stacked vertically:

```
[KICKER]   iOS dashboard, self-hosted by design
[PITCH]    A PERSONAL LIFE DASHBOARD FOR IOS, POWERED BY SMALL AGENTS YOU RUN YOURSELF.
[H1]       Your data, your machine, a dashboard that actually answers questions.
[BUTTONS]
[SUBHEAD]  The Perch surfaces sleep, weight, calendar, packages, and bookmarks…
```

Three problems:
- The kicker, the .pitch, and the h1 say similar things in different words.
- The subhead lives BELOW the buttons. Usually the descriptive text supports the headline before the CTA — visitors decide whether to click based on the description, not after.
- The .pitch line uses uppercase coral letterspacing — it reads as a slogan. But the kicker above it ALSO reads as a slogan. Two slogans in a row.

**Fix:** drop the `.pitch` paragraph entirely. Move the `.hero-subhead` above the `.hero-actions`. New order:

```
[KICKER]   iOS dashboard, self-hosted by design
[H1]       Your data, your machine, a dashboard that actually answers questions.
[SUBHEAD]  The Perch surfaces sleep, weight, calendar, packages, and bookmarks in one iOS layout, without a subscription or a third-party cloud.
[BUTTONS]
```

Cleaner, supports a confident first impression, no redundancy.

### 3. Reorder "Three things it does, quietly"

Card 2 ("Knows the difference between data and information") is the strongest because it has an actual sample insight quote — that's what makes the product feel real. Currently it's in the middle. Move it to first position so visitors hit the strongest message first. New order:

1. Knows the difference between data and information. *(the quote card — was #2)*
2. Reads your data, writes nothing back. *(was #1)*
3. Talks to the services you already pay for. *(was #3)*

### 4. Lazy-load images below the fold

10+ JPEG screenshots are loaded on initial paint. The hero needs eager-load; everything else can be deferred. Change every `<img>` in `#screens` and below to:

```html
<img src="..." alt="..." loading="lazy" decoding="async">
```

Don't add it to `.hero-image img` or `.hero-peek img` — those are above the fold.

### 5. Add `width` and `height` attributes to images

Without them, layout shifts when each image loads — measurable CLS (Cumulative Layout Shift) hit. For each `<img>`, set the actual pixel dimensions of the source file. The CSS `width: 100%` already overrides for layout, but the attributes give the browser an aspect ratio to reserve space.

### 6. Color contrast — `--muted` on `--bg` is borderline

`#6f5f72` muted text on `#EFD8D5` background is roughly 4.0:1 contrast. WCAG AA wants 4.5:1 for normal text. Two ways to fix:

- Darken `--muted`: `#5a4d5e` brings it to ~5.0:1 and stays in the muted-purple family.
- Or use `--ink` `#2b234f` for body text and reserve `--muted` for genuine secondary captions.

I'd go with darkening to `#5a4d5e`. Keeps the existing palette feel.

---

## Tier 2 — nice-to-have polish (≤2 hours)

### 7. Convert images to WebP/AVIF

Page is image-heavy. JPG → WebP cuts ~30%, → AVIF cuts ~50%. Use `<picture>`:

```html
<picture>
  <source srcset="perch-hero-today-a1.avif" type="image/avif">
  <source srcset="perch-hero-today-a1.webp" type="image/webp">
  <img src="perch-hero-today-a1.jpg" alt="..." loading="lazy" decoding="async">
</picture>
```

Bonus if you can also add 2x variants via `srcset` for retina displays.

### 8. Reduce decorative-blob compositing on mobile

The body has 4 stacked backgrounds (2 radial gradients + linear-gradient pattern + base color) plus `body::before` dot pattern. This is a lot of paint cost. On lower-end iPhones the parallax can scroll-jank.

On `@media (max-width: 760px)`, simplify to:

```css
@media (max-width: 760px) {
  body {
    background: var(--bg);
  }
  body::before {
    display: none;
  }
}
```

The decorative blobs in `.hero-card::before/::after` are already hidden on mobile (line ~870 of inline styles), good. Just simplify the body.

### 9. Tone down the rotation transforms

Almost every screenshot has a `transform: rotate(...)`:
- `.hero-image` rotate(1.1deg)
- `.hero-note` rotate(-2.5deg)
- `.hero-peek` rotate(-8deg)
- `.shot-feature` rotate(-0.8deg)
- `.shot-wide` rotate(0.6deg)
- `.shot-mini:nth-child(1)` rotate(-1.6deg)
- `.shot-mini:nth-child(2)` rotate(1.2deg)

Editorial-feeling in moderation, but at this density it starts to read as "everything is crooked." I'd reduce to: hero card stays, hero peek stays at -8deg (it's the strongest visual moment), drop the rotations on `.shot-feature`, `.shot-wide`, and the `.shot-mini` pair. Let those land flat — they're already in a wonky asymmetric grid.

### 10. The `.three-up .card` asymmetric border-radius is gorgeous on desktop, awkward on `≤980px`

On desktop those weird `34px 28px 40px 24px` corners feel intentional and premium. On stacked-mobile the asymmetry across THREE cards in a row reads as a render bug. Either:
- Reset to `--radius-lg` (24px) on `≤980px`, or
- Apply the same asymmetric set to all three (so it reads as a deliberate house-style detail).

I'd reset on mobile.

### 11. Add a favicon

```html
<link rel="icon" type="image/svg+xml" href="favicon.svg">
<link rel="icon" type="image/png" href="favicon-32.png" sizes="32x32">
<link rel="apple-touch-icon" href="apple-touch-icon.png">
```

Use a simple coral-on-indigo "P" matching the `.brand-mark` to stay on-system.

### 12. Empty-state messaging if a service is missing

The Services table currently lists every integration as if all are required. For a self-hosted-by-design pitch, it'd land harder if the table had a third column or trailing note that said which are optional. Or split the table into "Core" (Calendar + Fastmail JMAP + 17track) and "Optional" (everything else). The FAQ already says "Skip the ones you don't have," but the visual structure doesn't reinforce it.

---

## Tier 3 — stretch ideas (≥ half a day each)

### 13. Dark mode that keeps the brand

Editorial Linen is a warm-pink-paper aesthetic — fundamentally a "light mode" identity. But on a dark-mode visitor's machine the bright bg is jarring next to their other tabs. Consider a `prefers-color-scheme: dark` variant where:

- bg becomes `#1a1428` (deep version of `--ink`)
- card becomes `#2a2240`
- coral and indigo stay as accents but indigo becomes lighter (`#a89dd0`) since it'd be on a dark bg
- ink becomes `--card`'s value

Keep the warm-pink for light mode, swap to deep-indigo-paper for dark. The "shifts with time of day" tagline in the iOS app already sets this expectation.

### 14. One subtle interactive moment

The product is "a dashboard that answers questions" — it FEELS like software. The site is static. Consider one CSS-only animation that reinforces the dynamism:

- The sample insight quote in card 2 could rotate through 3 example insights every 5s (CSS keyframes + opacity fade).
- Or a small `details/summary` element on the Daily Insight card section labeled "see another" that swaps the body text on click without JS.

Risk: easy to overdo. Only do this if the rest of the page feels solid first.

### 15. "No tracking" as a feature

The site has no analytics, no JS at all. That's a strong privacy story for a privacy-focused product. Add a one-liner to the footer:

> No tracking. No analytics. No JavaScript. This page is one HTML file with inline CSS — view source to confirm.

It costs nothing and reinforces the self-hosted ethos.

### 16. SEO structured data

Add JSON-LD `SoftwareApplication` schema in `<head>`:

```html
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  "name": "The Perch",
  "applicationCategory": "HealthApplication",
  "operatingSystem": "iOS 26",
  "description": "...",
  "url": "https://whoisthisfabio.com/ThePerch/",
  "offers": { "@type": "Offer", "price": "0", "priceCurrency": "USD" },
  "author": { "@type": "Person", "name": "Fábio Resende", "email": "me@hellofabio.com" }
}
</script>
```

Helps Google render rich results when the page surfaces in search.

---

## What's already great — don't change

- The voice. "Photographed like software someone actually uses, not something pretending to be a lifestyle brand" / "Three things it does, quietly" / "The parts with teeth" / "Reasonable questions" — keep all of it.
- The Services table. Useful, scannable, no decoration tax.
- The five-things section with `01–05` numbering. The mono numbers next to italic-serif headings is a strong type pairing moment.
- Build credit at the bottom: "Built with Claude Code + a fair amount of stubbornness" — sets the right tone.
- All-inline CSS, no JavaScript, no external dependencies beyond Google Fonts. Genuinely fast.
- The iPhone notch detail in `.hero-image::before` — small craft, noticed.

---

## Summary

If you do nothing else, do Tier 1 items 1–3: OG meta tags + the hero copy reorder + the "three things" reorder. That's maybe 20 minutes and meaningfully improves how the page lands on first impression and on social shares.

The rest of Tier 1 (lazy-load, image dimensions, contrast tweak) is good hygiene before public flip — another 10–15 minutes total.

Tier 2 and Tier 3 can wait until after the public flip — you'll get real visitor signal then about what's actually worth investing in.
