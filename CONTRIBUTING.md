# Contributing to Tero

Thanks for helping make Tero better. Small, focused changes are the easiest to review and ship.

## Before you start

- **Bugs:** open an issue with your macOS version, the app you selected from, what you expected and what happened. Never paste private text, API keys or clipboard content.
- **Features:** open an issue first so we can agree on the behaviour before you write code.

## Development

1. Fork and clone the repository, then open `Tero.xcodeproj` and use the **Tero Dev** scheme.
2. Set your own signing team in **Signing & Capabilities** (see the README).
3. Keep pure logic in `Sources/Core` with tests in `Tests/`. AppKit and UI changes run on the main actor.
4. Run the checks that cover your change:

   ```bash
   swift test
   make check
   python3 Scripts/test-byok.py
   ```

## Guidelines

- **Native and quiet.** SwiftUI for content, AppKit for the panel, no new third-party runtime dependencies without discussion.
- **Keyboard first.** Every new action works with the arrows, Return and Escape, and reuses the shared action bubbles.
- **Privacy.** Never persist selected text, never log user content, and never add provider secrets to the app. Bring-your-own-key requests go only to the provider the person chose.
- **No surprises.** Actions that change text or files run only after an explicit choice, revalidate their target and never overwrite files.
- **English UI**, sentence-case buttons, short copy.

If you change an AI prompt or its validation, update both `Resources/AI/Prompts.json` / `Sources/AI/LocalGateway.swift` and the matching gateway in `supabase/functions/tero-correct`, so own-key and Tero Pro behave the same.

## Pull requests

Describe what changed, why, and how you tested it. Include a screenshot for UI changes. By contributing, you agree that your contribution is licensed under the MIT License.
