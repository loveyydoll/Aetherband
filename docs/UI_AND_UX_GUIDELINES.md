# Aetherband UI and UX Guidelines

**Status:** Target product guidance for the native C++/JUCE application. The existing Flutter UI is a legacy visual/behavioral reference only; these guidelines do not claim that the current target already implements the design.

## Product feel

Aetherband should feel like a creative instrument for musicians: focused, tactile, expressive, and fast to operate. Learn from established DAWs' arrangement, mixer, transport, and editing patterns without cloning any single product. The interface should support creative flow rather than demand attention for its own sake.

The intended balance is **musician-first, powerful when needed**: the main workspace should remain legible, with advanced controls exposed contextually instead of crowding every view.

## Visual language

- Dark charcoal background and slightly lighter panel surfaces.
- Warm off-white primary text.
- Muted sage as a primary interaction accent.
- Magenta as a secondary accent for selected creative or recording states when semantically appropriate.
- Blue may distinguish a secondary category, not serve as random decoration.
- Thin, low-contrast separators, clear spacing, consistent alignment, and restrained rounded corners.
- Compact desktop typography with a clear hierarchy; transport and timeline labels must remain readable at normal desktop scaling.
- Preserve the existing Aetherband logo and visual identity. Avoid a large centered application title inside the working DAW interface.

## Workspace direction

The primary desktop view should prioritize:
- a top menu bar with conventional File/Edit/View/Track/Help-style entry points;
- a visible transport and project/session status;
- an arrangement timeline with readable track headers and clip regions;
- a mixer and track controls that feel integrated with the arrangement;
- contextual inspector/browser areas that can be resized or collapsed;
- keyboard shortcuts and precise mouse interaction;
- clear selection, mute, solo, record-arm, clipping, and error states.

The arrangement should be inspired by the efficiency of established DAWs while keeping its own tone. The interface should feel like music software, not a generic app mockup, landing page, or splash screen.

## Native implementation rules

- Implement the target UI in C++/JUCE.
- Keep project state and engine state outside widget ownership.
- UI updates must not block or allocate unpredictably on the audio callback.
- Separate presentation state from the authoritative session model.
- Design for resizable windows, high-DPI displays, keyboard navigation, and Windows/macOS conventions.
- Prefer real, wired controls over decorative mock controls. Label prototypes and disabled features clearly.
- Do not polish a mockup at the expense of the first real end-to-end audio workflow.

## Acceptance checks

Review at practical desktop window sizes on both platforms. Test menu and keyboard workflows, panel resizing, readable timeline/mixer density, focus behavior, device/error status, and accessibility basics. Do not claim the visual guidelines are fully implemented until checked against the native application.
