# Aetherband UI and UX Guidelines

**Status:** Working product guidance for the current Flutter desktop prototype. These rules guide new work; they do not claim every current screen already conforms.

## Product feel

Aetherband should feel like a creative instrument for musicians: focused, tactile, expressive and fast to operate. It can have a distinct visual identity without sacrificing timeline readability, editing precision or predictable behaviour. Avoid cloning any single commercial DAW. Learn from established DAWs' interaction patterns, but make deliberate choices that fit Aetherband.

The intended balance is **musician-first, powerful when needed**: the default workspace should be legible and approachable; advanced controls can appear in contextual panels or deeper views instead of crowding every screen.

## Current visual language

Use the existing theme as the baseline unless a task explicitly proposes a design change:
- Dark charcoal background and slightly lighter panel surfaces.
- Warm off-white primary text.
- Muted sage as the primary interaction/accent colour.
- Magenta as a secondary accent for selected creative/recording states where semantically appropriate.
- Blue may be used for a distinct secondary category, not as random decoration.
- Thin, low-contrast separators; clear spacing and alignment; restrained rounded corners.
- Compact desktop typography with clear hierarchy. Important transport and timeline labels must remain readable at normal desktop scale.

Current tokens live in `prototypes/aetherband-flutter-ui/lib/src/theme.dart`. Reuse `AetherColors` and `AetherTheme` instead of introducing local hex colours or a competing theme. If a token is missing, add it centrally and explain why. Do not recolour the entire application as part of an unrelated feature.

## Workspace and information hierarchy

The current UI is an **arrangement-first desktop workspace**:
- Top-level menu and transport area: application commands and high-frequency playback controls.
- Optional left browser: categories and selectable instruments/presets/assets.
- Central arrangement: track headers, timeline ruler, clips and playhead.
- Contextual workspace panels: selected-track/clip information and editing controls.
- Optional mixer view: channel-oriented level and track controls.
- Engine errors: visible, understandable status with a retry or recovery action where valid.

Treat these as current layout concepts, not a requirement to preserve every pixel. Improve layout when user workflows demonstrably benefit, but keep the arrangement central and maintain a clear hierarchy between transport, timeline, browser and inspector/mixer.

### Do
- Preserve the arrangement as the primary place to understand a session.
- Keep transport controls easy to find and visually consistent.
- Make selected track/clip state unmistakable without relying on colour alone.
- Use consistent alignment, panel padding, control sizes, labels and tooltips.
- Keep the timeline, track headers and ruler visually coordinated when zooming or scrolling.
- Give panels sensible minimum sizes and graceful behaviour at narrower desktop widths.
- Make important errors visible without permanently obscuring the work area.
- Use icons consistently and provide tooltips/labels for unfamiliar actions.
- Keep keyboard and mouse workflows first-class; shortcuts should be documented and avoid surprising conflicts.
- Design empty, loading, unavailable-engine, error and no-selection states—not just the happy path.

### Do not
- Do not make a desktop DAW look like a mobile settings app or a generic dashboard.
- Do not add cards, gradients, glowing borders, glassmorphism, heavy shadows or decorative animation without a concrete usability reason.
- Do not add arbitrary accent colours, inconsistent corner radii or per-widget typography.
- Do not hide core actions behind unexplained icons or nested menus.
- Do not use colour as the only indicator of selection, mute, recording, clipping, errors or track type.
- Do not shrink timeline labels or controls until they are hard to use just to fit more on screen.
- Do not redesign the entire workspace to deliver one feature.
- Do not replace the current design system or rewrite the theme as an incidental cleanup.
- Do not claim that a mock control operates real audio functionality.

## Timeline and clip interaction

The timeline is a precision editing surface, not just a visual illustration.

- Keep ruler divisions, clip positions, track rows, playhead and zoom in a shared coordinate system.
- Distinguish selected clips from unselected clips, and selected tracks from selected clips.
- Use clear hit targets for selection, move, trim/resize and future automation interactions.
- Prevent accidental edits when the user intended to select or scroll. Use explicit cursor/gesture feedback where possible.
- Keep horizontal zoom anchored predictably; don't let the playhead or selected content jump unexpectedly without reason.
- Clamp movement only when the product rule is explicit; avoid silent data loss or confusing snap behaviour.
- Any operation that edits real project data must update the underlying model, not only repaint the widget.
- Demo clips must remain visibly identifiable in code and documentation as demo data until backed by a loaded session.
- Add widget tests for important gestures and state changes. If snapping, undo or multi-select is not implemented, do not imply it is.

## Transport, mixer and engine state

- Play/pause/stop indicators must reflect engine-confirmed state or clearly communicate pending/unavailable state.
- Stop must not merely reset a Flutter timer or playhead while audio continues. Preserve and test the existing Stop/rewind regression fix.
- Record must not appear to record audio unless a real recording path exists. A prototype toggle must be labelled as a prototype or remain disabled with an explanation.
- Meter displays must use actual telemetry when represented as live meters. Do not animate fake meter values to imply signal.
- Gain, pan, mute, solo, routing and device controls must call a real supported engine API before being presented as functional.
- Surface native errors; never swallow them and silently update UI to a success state.
- Do not block Flutter's UI isolate while waiting for file I/O, device operations or long-running engine work.

## UI-to-engine boundary

- Flutter/Dart owns presentation, input handling, layout, view state and user feedback.
- Rust owns audio I/O, decoding, mixing, DSP, scheduling and real-time callback behaviour.
- Dart native interop belongs behind the existing adapter/controller in `prototypes/aetherband-flutter-ui/lib/src/native_engine.dart` and `engine_controller.dart`. Inspect the current implementation before changing it.
- Do not call private Rust symbols directly or route continuous audio buffers through widgets, isolates or platform channels.
- Do not create a second desktop frontend or reintroduce the retired C#/.NET/Avalonia UI unless the project owner explicitly changes that decision.
- Before adding a control, verify that the required C ABI operation exists. If it does not, decide whether to implement the full vertical slice or clearly mark the UI affordance as unavailable; never fabricate engine state.
- Any C ABI change must be coordinated with the Rust export, Dart FFI declaration, ownership/error semantics and tests.

## Accessibility and usability

- Maintain readable contrast and legible text at common desktop scaling settings.
- Provide tooltips or text labels for non-obvious icons.
- Ensure keyboard focus is visible and interactive controls can be reached by keyboard where practical.
- Do not rely only on colour or animation to communicate state.
- Use consistent disabled/loading/error states and avoid controls that look active when unavailable.
- Avoid needless motion; respect reduced-motion preferences where applicable.

## Responsive desktop behaviour

The target is desktop, not mobile-first. Prioritize wide arrangements, keyboard/mouse use, high-DPI scaling and resizable panels. Smaller window widths still need a deliberate fallback: collapse optional panels before hiding essential transport or timeline context, and never let controls overlap or become unreachable. Test at least one normal desktop size and one constrained width for layout changes.

## Definition of done for UI work

A UI feature is not done merely because it looks correct in a screenshot. Depending on scope:
1. Its state has a clear owner and stays consistent through rebuilds.
2. It handles loading, unavailable-engine and error states.
3. Its interactions are connected to real model/engine behaviour, or explicitly labelled as prototype-only.
4. Existing transport and timeline interactions still work.
5. Relevant widget tests and `flutter analyze` pass, or the exact unrun/failed checks are reported.
6. The UI matches the shared theme and avoids unrelated redesign.
7. Documentation and the feature tracker reflect the actual implementation status.
