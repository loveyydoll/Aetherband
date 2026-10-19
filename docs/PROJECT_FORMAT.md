# Aetherband Project and Session Format

## Status

**The native C++/JUCE project format is not finalized or implemented.** Do not treat the legacy Flutter format as the target contract.

## Legacy reference

The previous Flutter implementation contains an early-alpha UTF-8 JSON format with extension .aetherband.json. It stores a session title, imported audio file references, track identifiers, and basic gain/pan/mute settings. It references local source paths rather than bundling all media and is not a production-ready portable project bundle.

That schema is evidence of legacy behavior, not a binding design decision. Inspect its implementation and tests before relying on details.

## Requirements for the native format

Before committing to a schema, decide and document:
- schema versioning and forward/backward compatibility;
- stable project, track, clip, media, and processor identifiers;
- relative media paths and missing-media recovery;
- whether projects bundle media or reference external assets;
- atomic save, crash safety, and dirty-state behavior;
- validation limits for file size, track count, parameters, and malformed input;
- instrument/effect state and automation persistence;
- deterministic migration and recovery from unsupported schema versions.

Opening a project must not destructively replace the active session until the candidate file and required media have been validated. Saving must report failures clearly and avoid silently corrupting the previous valid file.

## Initial vertical slice

Implement a minimal versioned session model for imported WAV tracks and arrangement/mixer settings. Add round-trip, malformed-input, missing-media, and failed-write tests. Expand the schema only when features require it.

Do not promise compatibility with .aetherband.json until a tested importer or migration path exists.
