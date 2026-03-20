---
name: import-svg-template
description: Import Screenshot Bro templates from exported SVG files
---

# Import Templates from SVG

Import one or more SVG files as a new Screenshot Bro template in `screenshot/Templates.bundle/`.

Usage: `/import-svg-template <path1.svg> [path2.svg] [path3.svg]`

Each SVG becomes a separate row. If `$ARGUMENTS` is empty, ask for the SVG file path(s).

## Step 1: Determine next template folder

List existing folders in `screenshot/Templates.bundle/`. Pick the next sequential name (e.g. `template4`). Create `screenshot/Templates.bundle/<name>/resources/`.

## Step 2: Determine device type per SVG

Infer the device category from the file name or user input:

| Keyword in filename/input | Device category | ddc value | dfi |
|---|---|---|---|
| "iphone" / "ios" | iPhone | `"iphone"` | `"iphone17promax-silver-portrait"` |
| "ipad" | iPad | `"ipadPro11"` | `"ipadpro11-silver-portrait"` |
| "android" / "pixel" | Android | `"android"` | _(omit — uses abstract bezel)_ |
| "mac" / "desktop" | Mac | `"macbook"` | `"macbookair13-midnight-landscape"` |

**CRITICAL**: The `DeviceCategory` enum raw values are: `iphone`, `ipadPro11`, `ipadPro13`, `macbook`, `android` (NOT `androidPhone`), `androidTablet`. Using the wrong raw value will cause the entire template to fail silently, creating an empty project.

## Step 3: Determine template dimensions from presets

**ALWAYS use screenshot size presets** from `screenshot/Models/ScreenshotSize.swift` — never use raw SVG dimensions as the output tw × th. Read the file to get current presets.

Pick the preset whose aspect ratio best matches the SVG slice aspect ratio for the device type. Default presets when aspect ratio is ambiguous:

| Device type | Default preset | tw × th |
|---|---|---|
| iPhone | iPhone 6.5" Display Portrait | 1242 × 2688 |
| iPad | iPad Pro 13" Display Portrait (3rd–6th gen) | 2048 × 2732 |
| Mac | MacBook Air 13" (legacy) Landscape | 1280 × 800 |
| Android Phone | Modern 19.5:9 Portrait (preferred) | 1080 × 2340 |
| Android Tablet | Standard Portrait | 1200 × 1920 |

**Selecting the best preset**: Compute the SVG slice aspect ratio (`slice_h / slice_w`). For each portrait preset in the matching device category, compute its aspect ratio (`th / tw`). Pick the preset with the smallest absolute difference. If multiple are close, prefer the default above.

**Slice count inference**: Determine slice count from SVG viewBox width by finding clean integer divisions (remainder < 1px). The slice count comes from SVG structure, NOT from the preset. When the user overrides the preset (e.g., `force_preset`), keep the SVG-derived slice count — only the output dimensions change.

Common patterns:
- iPhone SVG viewBox 12900 wide → 12900/1290 = 10 slices
- iPad SVG viewBox 8192 wide → 8192/2048 = 4 slices
- Android SVG viewBox 11520 wide → 11520/1440 = 8 slices

**Uniform scaling with centering offset** (CRITICAL for correct positioning):
When SVG slice and preset have different aspect ratios, use **uniform scale** (`s = min(scaleX, scaleY)`) for all shape sizes and positions. This preserves proportions — a device centered in the SVG stays centered in the output.

Compute centering offsets for the dimension with extra space:
- `s = min(preset_tw / slice_w, preset_th / slice_h)`
- `ox = (preset_tw - slice_w * s) / 2` — horizontal offset per slice
- `oy = (preset_th - slice_h * s) / 2` — vertical offset

Transform SVG coordinates to model space:
- `model_x = slice_index * preset_tw + local_x * s + ox`
- `model_y = svg_y * s + oy`
- `model_w = svg_w * s`, `model_h = svg_h * s`

Do NOT use independent `scaleX`/`scaleY` for positions — this distorts centering when aspect ratios differ.

## Step 4: Parse SVG elements

**IMPORTANT — Write a Python script** to parse SVG files and generate project.json. Manual JSON construction is error-prone for complex templates. The script should use `xml.etree.ElementTree` for parsing and `json` for output.

Parse the SVG file to extract:

### Background color
The first `<rect>` matching the full viewBox dimensions with a solid hex fill is the base background color → set as `bgc` on the row.

### Slice override backgrounds
`<rect>` elements covering exactly one slice width × full height, with a fill different from the base background, become per-template `bgc` overrides with `"ob": true`.

### Background decorative shapes
`<path>` elements with non-white, non-background fills are decorative shapes. For each:
- Compute bounding box from path coordinates (parse M, L, C, H, V, S, Q, A commands — **must handle all SVG path commands**, not just M/L/C)
- Create an individual SVG shape:
```json
{
  "t": "svg",
  "c": "<fill color>",
  "suc": false,
  "svg": "<svg width='W' height='H' viewBox='minX minY W H' fill='none' xmlns='http://www.w3.org/2000/svg'><path d='...' fill='COLOR'/></svg>",
  "x": <bbox_min_x * scaleX>,
  "y": <bbox_min_y * scaleY>,
  "w": <bbox_w * scaleX>,
  "h": <bbox_h * scaleY>,
  "id": "<UUID>"
}
```

### Logo/image placeholders
`<circle>` elements → image placeholder:
```json
{
  "t": "image",
  "c": "#98989D",
  "br": <radius * s_min>,
  "x": <(cx - r) * scaleX>,
  "y": <(cy - r) * scaleY>,
  "w": <2*r * s_min>,
  "h": <2*r * s_min>,
  "id": "<UUID>"
}
```

### Text elements
SVG exports from Figma convert text to outlined paths. **CRITICAL**: Figma uses `fill="white"` (lowercase word), NOT `#FFFFFF`. Always normalize fill comparison: `fill.strip().lower() in ('white', '#ffffff', '#fff')`.

Use the **path bounding box** to determine position and approximate font size, then map to placeholder text:

1. Compute bbox of each white path (parse all M, L, H, V, C, S, Q, A coordinates to find min/max x, y)
2. Classify by **bounding box height** in SVG coordinates:
   - **Headline** (tall bbox h > 250): `"This is a very catchy App Headline"`, fs=110 (iPhone/Android) or fs=140 (iPad), fw=500, ta="center"
   - **Feature title** (h 150–250): `"This is a title for a helpful feature"`, fs=104, fw=500, ta="center"
   - **Description** (h 80–150): `"Lorem ipsum dolor sit amet, consectetur adipiscing elit. Erat."`, fs=65, fw=400, ta="center"
   - **FEATURE label** (h < 60): `"FEATURE"`, fs=56, fw=600, ta="center"
3. Convert bbox to text frame position:
   - **y**: `frame_y = (bbox_min_y - fontSize * 0.15) * scaleY` (adjust from glyph top to text frame top)
   - **x** (center-aligned): `frame_x = ((bbox_min_x + bbox_max_x) / 2) * scaleX - frame_w / 2`
   - **x** (left-aligned): `frame_x = bbox_min_x * scaleX`
   - **w**: Start with `bbox_width * s` (uniform scale). Ensure minimum width for target line count: `min_w = len(txt) * fs * 0.55 / max_lines * 1.1` where max_lines is 1 for labels, 2 for titles/headlines, 3 for descriptions. Cap at `preset_tw * 0.85` to leave margins. Never exceed template width. When widening center-aligned text, adjust x to maintain center.
4. Ensure full visibility:
   - Estimate lines: `chars_per_line = w / (fs * 0.55)`, `lines = ceil(len(txt) / chars_per_line)`
   - Set `h = lines * fs * 1.5`
   - Font: `fn: "DM Sans"`, all text white `c: "#FFFFFF"`
   - For headlines, add `"lns": -20, "ls": 0` for tighter line spacing

### Device frames
`<rect>` elements with `fill="url(#patternN_...)"` are device screen/frame images. They come in pairs per device position:

**Pairing is cross-rotation**: Device rects come in pairs (screen + frame) that may have DIFFERENT rotation angles (e.g., 0° screen + -90° frame for iPad, or 45° screen + -45° frame for tilted devices). Pair by center proximity regardless of angle, then pick the smaller-area rect as the screen.

**Tilted devices**: Some templates have devices at arbitrary angles (35°, 45°, etc.). These must be imported with `"rot": <angle>` in the shape JSON. Use the unrotated rect dimensions for shape w/h (the app applies rotation), but use the **rotated bounding box** for x/y positioning.

**Hero devices**: Some templates have a 2x-sized device spanning 2 slices (e.g., slices 4+5). These have significantly larger width/height than regular devices. Include them as normal device shapes.

**Pairing algorithm for non-rotated rects**:
1. Sort by x position
2. Group rects that are within `max(w1, w2)` pixels of each other
3. In each pair, pick the smaller-area rect as the screen
4. If no pairs found (each rect is isolated), each rect is its own screen position

**Device frame aspect ratio enforcement** (CRITICAL): After computing device w/h from SVG scaling, enforce the correct aspect ratio from `DeviceFrameSpec.swift`. SVG screen rects have different ratios than the actual device frame PNGs. Keep the height, adjust width to match the frame spec ratio, and re-center horizontally:

| dfi | Frame ratio (w/h) |
|---|---|
| `iphone17promax-*-portrait` | 1470/3000 = 0.4900 |
| `ipadpro11-*-portrait` | 1880/2640 = 0.7121 |
| `ipadpro13-*-portrait` | 2300/3000 = 0.7667 |
| Android (no dfi) | No enforcement — uses abstract bezel |

```python
correct_w = dev_h * target_ratio
dev_x += (dev_w - correct_w) / 2  # re-center
dev_w = correct_w
```

```json
{
  "t": "device",
  "c": "#00000000",
  "dc": "<device category>",
  "dfi": "<device frame id or omit for android>",
  "x": <adjusted_x>,
  "y": <model_y>,
  "w": <ratio-corrected width>,
  "h": <model_h>,
  "id": "<UUID>"
}
```

## Step 5: Fonts

Shared fonts live in `screenshot/Templates.bundle/shared/fonts/`. Template `resources/` directories should NOT contain fonts — they are copied into projects at load time by `PersistenceService.copySharedFontsIfNeeded()`. No action needed here unless introducing a new font not already in `shared/fonts/`.

## Step 6: Build project.json

```json
{
  "ls": {"alc": "en", "l": [{"c": "en", "l": "English"}], "o": {}},
  "m": <timestamp>,
  "r": [<one row object per SVG file>]
}
```

Each row:
```json
{
  "bgc": "<background color>",
  "ddbc": "#1C1C1F",
  "ddc": "<device category>",
  "ddfi": "<device frame id>",
  "id": "<UUID>",
  "l": "<row label from presetLabel()>",
  "s": [<shapes: bg shapes, then logo, then text, then devices>],
  "th": <preset height>,
  "tp": [<templates, each with bgc and id>],
  "tw": <preset width>
}
```

**Row labels** — use `presetLabel()` convention from `ScreenshotSize.swift`:
- 1242×2688 → `"iPhone 6.5\" Display Portrait"`
- 2048×2732 → `"iPad Pro 13\" Display Portrait"`
- 1440×2560 → `"Android Phone Portrait"`
- 1280×800 → `"Mac Desktop Landscape"`
- Other → `"{width}×{height}"`

**Template bgc**: Use the row's background color as the default template color. Override with `"ob": true` for slices that have a distinct full-coverage rect in the SVG.

**Shape z-order**: background SVGs first, then logo, then text, then devices on top.

**IDs**: Uppercase UUID v4 format. Every shape, template, and row needs a unique ID.

**Timestamp** (`m`): macOS `NSTimeInterval` (seconds since 2001-01-01). For 2026: ~795000000–796000000.

**Omit `ddfi` key entirely** for android rows (do not set to null or empty string).

## Step 7: Validate

1. Validate JSON: `python3 -c "import json; json.load(open('<path>'))"`.
2. Build from project root: `cd <project_root> && xcodebuild -scheme screenshot -destination 'platform=macOS' build`.
3. Report template name, rows (with device type, shape count, template count, dimensions).
