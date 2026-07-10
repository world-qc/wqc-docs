# Contributing to wqc-docs

Thank you for helping improve the World Quantum Computer documentation archive. This repository is the source of truth for protocol docs, whitepapers, examples, and related materials.

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you agree to uphold it. Report unacceptable behavior using the contact details in that document.

## What We Welcome

Most contributions fall into one of these categories:

| Kind | Examples | Typical review bar |
|------|----------|--------------------|
| **Typos & clarity** | Spelling, grammar, broken links, formatting | Fast path if the meaning is unchanged |
| **Translations** | Proposed wording in another language that matches English | Must track a specific English revision; discuss placement with maintainers |
| **New specs & guides** | Markdown under `/spec`, `/examples`, worker guides | Needs a clear purpose and maintainer review |
| **Figures & assets** | Diagrams, screenshots, SVG/PNG for specs | Prefer source-editable formats when possible |
| **Substantive protocol changes** | Whitepaper / yellowpaper / tokenomics meaning | **Not** merged casually — see below |

If you are unsure which category applies, open an issue first and describe the intent.

## Document tiers (read this before editing)

Not every Markdown file has the same weight. Maintainers treat documents differently depending on how much they define the protocol.

### Tier A — Canonical protocol documents (protected)

These define the public protocol narrative and must not be rewritten casually:

- `/whitepaper/` — versioned whitepapers (e.g. `WHITEPAPER_0.3_en.md`) and related scope notes
- Yellowpapers and formal appendices (when present under `/whitepaper/` or `/spec/`)
- `/tokenomics/` — economic model text that may be cited externally (when present)
- `/manifesto/` — project manifesto text (when present)

**Rules for Tier A:**

1. **Do not open a PR that silently rewrites meaning.** Typos, broken links, and formatting-only fixes are fine. Changes to claims, formulas, security assumptions, economics, or roadmap status are **substantive**.
2. **Substantive changes require an issue first.** Open a GitHub Issue that states:
   - which document and section you want to change
   - why the current text is wrong or incomplete
   - the proposed replacement (or a clear outline)
   - whether implementations (`wqc-core`, `wqc-node`, `wqc-orchestrator`, …) already match the proposal
3. **One concern per PR.** Do not mix typo cleanup with protocol redesign.
4. **Versioned whitepapers are historical.** Prefer adding a **new versioned file** (e.g. `WHITEPAPER_0.4_en.md`) or an errata / scope note over rewriting an already published version in place. In-place edits to published versions are limited to errata-style corrections that maintainers explicitly approve.
5. **Maintainers may close or request redesign** of PRs that change Tier A meaning without prior discussion. This is intentional: these docs are cited by the community and must stay reviewable.

### Tier B — Working specs and examples

- `/spec/` — API and networking specifications
- `/examples/` — circuits, scripts, and README guides
- Operational notes that are not versioned whitepapers

These may evolve with the codebase. Still keep PRs focused, and call out any behavior change that workers or clients must follow.

### Tier C — Meta docs

- `README.md`, this `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, license text

Improvements are welcome; keep tone consistent with the rest of the archive.

## Typos and small clarity fixes

1. Fork and branch from `main`.
2. Keep the change minimal — fix the typo or unclear sentence without restating nearby sections.
3. In the PR description, say that the change is **meaning-preserving**.
4. If a “typo fix” actually changes a formula, constant, or claim, treat it as Tier A substantive and open an issue first.

## Translation proposals

English in this repository is authoritative for protocol wording.

1. Open an issue before submitting a large translation so maintainers can agree on language, scope, and where the text should live.
2. In the PR, **cite the English source path and revision** (commit SHA or release tag) you translated from.
3. Do not invent new protocol claims in a translation. If English is ambiguous or wrong, fix or discuss English here first, then translate.
4. Keep filenames and section structure aligned with English where practical so reviewers can diff section-by-section.

## Adding new specifications (Markdown)

1. Open an issue describing the audience (client, worker, implementer) and what gap the doc fills.
2. Place the file under the right top-level directory (`/spec`, `/examples`, …). Avoid putting new canonical protocol narrative under `/whitepaper/` unless maintainers agree it belongs there.
3. Use clear Markdown:
   - One H1 title
   - Stable section headings
   - Explicit version or “status” line near the top (`Draft`, `Active`, `Superseded`)
4. Link related implementation docs (e.g. `wqc-core` README, `trace-spec`) when the spec depends on them.
5. If the spec changes wire formats or APIs, note compatibility impact in the PR.

### Suggested front matter for new specs

```markdown
# Title

- **Status:** Draft
- **Audience:** Worker implementers
- **Related:** wqc-node P2P protocols, wqc-core `/compute`
```

## Adding images and diagrams

1. Store assets next to the document that uses them, or under a clear `assets/` / `images/` folder for that topic.
2. Prefer SVG or other editable sources for diagrams; PNG/WebP for screenshots.
3. Use relative Markdown links, e.g. `![Architecture](./images/architecture.svg)`.
4. Keep files reasonably sized; do not commit huge binaries or generated build artifacts.
5. In the PR, briefly explain what the figure shows and which section references it.
6. Do not embed confidential keys, private endpoints, or personal data in screenshots.

## Pull request process

1. Fork the repository and create a branch from `main`.
2. Make a focused change set.
3. Open a PR against `main` with:
   - a short title
   - category (typo / translation / new spec / Tier A substantive)
   - link to the related issue (required for Tier A substantive changes)
4. Respond to review comments; maintainers may ask for splits if a PR mixes tiers.

### Branch naming

Examples:

- `fix/typo-whitepaper-0.3`
- `docs/spec-bootstrap-api`
- `feat/examples-phase-c-noise`
- `translate/fr-readme-outline`

## What will not be merged as-is

- Large unsolicited rewrites of Tier A documents
- “Drive-by” whitepaper edits that change economics, security claims, or roadmap without an issue
- Translations that diverge from English meaning
- Generated or scraped content without clear authorship and review
- Secrets, private keys, or non-public infrastructure details

## Licensing

By contributing, you agree that your contributions are licensed under the same terms as this repository: the [GNU Free Documentation License v1.3](LICENSE) (GFDL-1.3).

## Questions

Open a [GitHub Issue](https://github.com/world-qc/wqc-docs/issues) if you are unsure whether a change is Tier A, or if you need guidance on where a new document should live. We would rather discuss early than reject a large rewrite later.
