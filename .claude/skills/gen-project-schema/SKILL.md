---
name: gen-project-schema
description: Regenerate tools/project-schema.json from the Swift Codable models so it stays in sync with what the app writes to project.json files
---

# Regenerate Project JSON Schema

Update `tools/project-schema.json` to match the current Swift `Codable` definitions.
The schema describes the contents of a Screenshot Bro `projects/<uuid>/project.json` file (the `ProjectData` struct, not the top-level `projects.json` index).

## When to run this

After any change to the Swift models that affects the on-disk JSON shape:
- adding/renaming/removing a property on `Project`-tree types (rows, templates, shapes, locale state, gradients, backgrounds)
- adding/renaming an enum case used in `Codable` (e.g. a new `ShapeType`, `DeviceCategory`, `BackgroundStyle`, `ImageFillMode`, `GradientType`, `TextAlign`, `TextVerticalAlign`)
- changing a `CodingKeys` short code

If only behavior changed (computed vars, methods, view code), the schema does not need to change.

## Source of truth

Read these files — every `Codable` property you encounter must map to a schema field:

| Swift type | File |
|---|---|
| `ProjectData` (root) | `screenshot/Code/Models/Project.swift` |
| `ScreenshotRow` | `screenshot/Code/Models/ScreenshotRow.swift` |
| `ScreenshotTemplate` | `screenshot/Code/Models/ScreenshotTemplate.swift` |
| `CanvasShapeModel` | `screenshot/Code/Models/CanvasShapeModel.swift` |
| `BackgroundImageConfig`, `GradientConfig`, `GradientColorStop`, enums | `screenshot/Code/Models/BackgroundStyle.swift` |
| `ShapeType` | `screenshot/Code/Models/ShapeType.swift` |
| `DeviceCategory` | `screenshot/Code/Models/DeviceCategory.swift` |
| `LocaleState`, `LocaleDefinition`, `ShapeLocaleOverride` | `screenshot/Code/Models/LocaleModels.swift` |
| `TextAlign`, `TextVerticalAlign` | `screenshot/Code/Models/TextStyle.swift` |
| `CodableColor` | `screenshot/Code/Extensions/CodableColor.swift` |

## Translation rules

- **CodingKeys raw values are the JSON keys.** Use the short code (e.g. `tw`), not the Swift property name (`templateWidth`). Put the Swift name in the `description` so the schema is self-documenting.
- **`UUID`** → `$ref` to `#/$defs/UUID` (string with UUID regex).
- **`CodableColor`** → `$ref` to `#/$defs/Color` (hex string `#RRGGBB` or `#RRGGBBAA`, encoded by `CodableColor.encode`).
- **`Date`** → `{ "type": "number" }` (Swift's default `JSONEncoder` writes seconds since 2001-01-01).
- **`CGFloat` / `Double`** → `{ "type": "number" }`. **`Int`** → `{ "type": "integer" }`.
- **Enums** (`String`-backed) → `$ref` to a `$defs` entry with `"enum": [...]`. Use the enum's raw value, not the case name (e.g. `DeviceCategory.androidPhone` is `"android"`).
- **`Set<T>`** → `{ "type": "array", "uniqueItems": true, "items": ... }`.
- **`[String: [String: T]]`** (locale overrides) → object with `additionalProperties` nested.
- **Optional vs required:** a property is required iff `init(from decoder:)` calls `decode(...)` (no `IfPresent`) AND `encode(...)` always writes it. If either side is conditional, mark it optional.
- **Conditionally-encoded fields:** when `encode(...)` only writes a value under a condition (e.g. `if backgroundStyle != .color`), the field is optional. Note the condition in `description` so callers know when it appears.
- Set `"additionalProperties": false` on every object — this catches accidental drift in either direction.

## Steps

1. **Read every model file in the table above.** For each `Codable` struct, list its `CodingKeys` and the type of each property. For each enum, list raw values.
2. **Diff against the current `tools/project-schema.json`.** Compare field-by-field:
   - new `CodingKeys` entries → add to the corresponding `$defs` object
   - removed entries → delete from schema
   - new enum cases → append to `enum` array
   - changed required-ness → move between `required` and optional
3. **Edit `tools/project-schema.json` in place** with the changes. Keep the description text and `additionalProperties: false` on every object.
4. **Validate the schema is well-formed** (Draft 2020-12 meta-schema):
   ```bash
   python3 -m venv /tmp/.schemavenv 2>/dev/null; /tmp/.schemavenv/bin/pip install -q jsonschema
   /tmp/.schemavenv/bin/python -c "import json,jsonschema; \
     jsonschema.Draft202012Validator.check_schema(json.load(open('tools/project-schema.json'))); \
     print('schema OK')"
   ```
5. **Validate against real project files.** Find a few `project.json` files and check none produce errors (or that any errors are explainable, e.g. an old field that's now removed and that's fine because models only `decodeIfPresent`):
   ```bash
   /tmp/.schemavenv/bin/python <<'PY'
   import json, glob, jsonschema
   schema = json.load(open('tools/project-schema.json'))
   v = jsonschema.Draft202012Validator(schema)
   paths = sorted(glob.glob(
       '/Users/taras/Library/Mobile Documents/iCloud~xyz~tleskiv~screenshot/Documents/screenshot/projects/*/project.json'
   )) or sorted(glob.glob(
       '~/Library/Application Support/screenshot/projects/*/project.json'.replace('~', '/Users/taras')
   ))
   for p in paths[:25]:
       errs = list(v.iter_errors(json.load(open(p))))
       if errs:
           print(p.split('/')[-2][:8], len(errs), errs[0].message[:200])
   print(f"checked {min(len(paths),25)} files")
   PY
   ```
6. **Report** what changed (added/removed/renamed fields, new enum cases) so the user can confirm the diff matches their model edit.

## Scope notes

- The schema covers `ProjectData` (per-project `project.json`), not the `ProjectIndex` (`projects.json`) or the resources directory.
- If the user asks to extend the schema to the index, add a separate `$defs` entry for `Project` and `ProjectIndex` and document it as a top-level `oneOf` or as a sibling schema file.
- The `Templates.bundle/*/project.json` files use the same shape — they validate against this schema too.
