---
name: codegen
description: Run drift/build_runner code generation for Aura. Use after changing the drift schema (lib/data/db/app_database.dart) or any other build_runner-backed code, when you see "*.g.dart" / generated-output errors, or when the user says "run codegen" / "build_runner".
---

# Run code generation

Aura uses **drift** (SQLite) with `build_runner` to generate `app_database.g.dart`. Regenerate it
whenever the schema or other generated sources change.

## When it's needed
- You edited `lib/data/db/app_database.dart` (added/changed a table or column, bumped
  `schemaVersion`, added a DAO method).
- The analyzer/compiler complains about missing generated members, `_$AuraDatabase`, companions,
  or `.g.dart` being stale.

> Note: Riverpod providers in this project are **plain** (no provider codegen), so editing
> `providers.dart` does NOT require codegen. Only drift-backed code does.

## Command
```
C:\tools\flutter\bin\dart.bat run build_runner build --delete-conflicting-outputs
```
`--delete-conflicting-outputs` avoids prompts when generated files already exist.

## After running
- Run `C:\tools\flutter\bin\flutter.bat analyze` — it should be clean.
- If you changed the schema, make sure a matching migration exists: bump `schemaVersion` and add an
  `if (from < N) { ... }` block to the `MigrationStrategy` in `app_database.dart`.

## Verify
- Build completes with "Built with build_runner" and writes outputs.
- `app_database.g.dart` reflects the new tables/columns; `flutter analyze` passes.
