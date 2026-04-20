# Planzers — project guidelines

These rules apply to everyone working on the repository, including automated coding agents.

**Cursor:** The same policy is loaded automatically via [`.cursor/rules/planzers-guidelines.mdc`](.cursor/rules/planzers-guidelines.mdc) (`alwaysApply: true`). If you change these guidelines, update that file too so agents stay in sync.

## Language

- **Commit messages:** English only. Use clear, imperative-style subjects (e.g. `feat(trips): add expense list screen`).
- **Commit detail (body):** Write for a product/domain audience. Explain what changes for users or the business, not how the code is wired. Avoid technical jargon, function or variable names, and similar implementation noise unless a detail is genuinely hard to infer later and needs that precision.
- **Source code:** English for identifiers, file names, and in-code documentation (`//`, `///`).
- **Comments:** English only.
- **User-facing copy:** Follow the product language (currently French for UI strings and SnackBars). Do not translate the app to English in code unless explicitly requested.
- **UI copy scope (agents):** Do not add extra explanatory sentences, hints, helper text, or “did you know” copy to feature UIs unless the task explicitly asks for that wording. Stick to labels and messages that implement what was requested; the product owner will supply hints and tutorials separately when they want them.

## Engineering

- Prefer small, focused changes. Avoid drive-by refactors unrelated to the task.
- Match existing patterns in the codebase (structure, naming, state management, routing).
- After non-trivial edits, run `flutter analyze` and fix new issues.
- **Profile badges / avatars:** Never use Google-hosted profile image URLs directly in feature UIs (to avoid quota/429 issues). Use only badge/photo URLs stored in our own Firestore profile fields.

## Stack (reference)

- **Flutter / Dart** with **Riverpod** for state.
- **go_router** for navigation (including nested / shell routes where appropriate).
- **Firebase** (Auth, Firestore, Functions, etc.) — follow existing repository and security patterns.

## Pull requests and reviews

- Describe what changed and why in complete sentences, with the same domain-first tone as commit bodies (business outcome over code-level listing).
- Link issues or tickets when applicable.

## AI / agent usage

- Read this file at the start of substantive work on the repo.
- Obey user instructions that override or refine these defaults when they conflict.

### Challenging requests (web / mobile / Flutter)

- **Simplicity over “making it work at any cost”:** Do not add complicated or clever code just to satisfy a literal wording when a simpler, conventional solution matches the intent and fits the stack.
- **Assume product context, not platform expertise:** The product owner may not be deeply familiar with web, mobile, or Flutter. Treat feature requests as hypotheses to validate against current best practices, platform norms, and what is realistically maintainable in this codebase.
- **Push back constructively:** When the requested approach is suboptimal, uncommon, or discouraged, say so clearly and propose alternatives (standard patterns, platform-recommended flows, or a different feature shape). Prefer honest trade-offs over fragile workarounds.
- **Say when something “isn’t done” here:** If something is impractical, a poor fit, or not realistically done on these technologies or distribution channels (e.g. app stores, browser constraints), state that plainly rather than implementing a brittle workaround.
- **Profile save strategy check:** For the account/profile section, proactively challenge and confirm the save strategy when new options/preferences are added (immediate save vs explicit save), and align interactions/feedback with the agreed behavior before implementing.
