#!/usr/bin/env python3
"""Parse 3 SVG files and generate project.json for template1."""

import json
import re
import uuid
import xml.etree.ElementTree as ET

IPHONE_SVG = None  # Set per-template in main()
IPAD_SVG = None
ANDROID_SVG = None

# Presets from ScreenshotSize.swift
PRESETS = {
    "iphone": [
        (1320, 2868), (1290, 2796), (1284, 2778), (1242, 2688),
        (1206, 2622), (1179, 2556), (1260, 2736),
    ],
    "ipadPro11": [
        (2064, 2752), (2048, 2732), (1668, 2420), (1668, 2388),
    ],
    "android": [
        (1080, 1920), (1080, 2340), (1440, 3120),
    ],
}

FONT_EXTENSIONS = {"ttf", "otf", "ttc"}

# Device frame aspect ratios (frameWidth / frameHeight) from DeviceFrameSpec.swift
DEVICE_FRAME_RATIOS = {
    "iphone17promax-silver-portrait": 1470 / 3000,
    "iphone17promax-cosmicOrange-portrait": 1470 / 3000,
    "iphone17promax-deepBlue-portrait": 1470 / 3000,
    "ipadpro11-silver-portrait": 1880 / 2640,
    "ipadpro13-silver-portrait": 2300 / 3000,
    # Android uses abstract bezels, no fixed ratio to enforce
}


COLOR_NAMES = {
    'black': '#000000', 'white': '#FFFFFF', 'red': '#FF0000',
    'green': '#00FF00', 'blue': '#0000FF', 'none': '#00000000',
}


def normalize_color(c):
    """Ensure color is a hex string (#RRGGBB or #RRGGBBAA)."""
    if not c:
        return '#000000'
    cl = c.strip().lower()
    if cl in COLOR_NAMES:
        return COLOR_NAMES[cl]
    if c.startswith('#'):
        return c
    # Unknown — fallback to black
    return '#000000'


def uid():
    return str(uuid.uuid4()).upper()


def best_preset(device_category, svg_slice_w, svg_slice_h):
    """Pick the preset whose aspect ratio best matches the SVG slice."""
    svg_ratio = svg_slice_h / svg_slice_w
    presets = PRESETS.get(device_category, [])
    if not presets:
        return int(svg_slice_w), int(svg_slice_h)
    best = min(presets, key=lambda p: abs(p[1] / p[0] - svg_ratio))
    return best


def parse_path_bbox(d):
    """Parse SVG path d attribute and compute bounding box."""
    xs, ys = [], []
    tokens = re.findall(r'[MmLlHhVvCcSsQqTtAaZz]|[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?', d)
    cmd = 'M'
    cx, cy = 0, 0
    ti = 0
    while ti < len(tokens):
        t = tokens[ti]
        if t.isalpha() or t in ('Z', 'z'):
            cmd = t
            ti += 1
            continue
        val = float(t)
        if cmd == 'M':
            cx, cy = val, float(tokens[ti + 1])
            xs.append(cx); ys.append(cy)
            ti += 2; cmd = 'L'
        elif cmd == 'm':
            cx += val; cy += float(tokens[ti + 1])
            xs.append(cx); ys.append(cy)
            ti += 2; cmd = 'l'
        elif cmd == 'L':
            cx, cy = val, float(tokens[ti + 1])
            xs.append(cx); ys.append(cy)
            ti += 2
        elif cmd == 'l':
            cx += val; cy += float(tokens[ti + 1])
            xs.append(cx); ys.append(cy)
            ti += 2
        elif cmd == 'H':
            cx = val; xs.append(cx); ti += 1
        elif cmd == 'h':
            cx += val; xs.append(cx); ti += 1
        elif cmd == 'V':
            cy = val; ys.append(cy); ti += 1
        elif cmd == 'v':
            cy += val; ys.append(cy); ti += 1
        elif cmd == 'C':
            for j in range(0, 6, 2):
                xs.append(float(tokens[ti + j]))
                ys.append(float(tokens[ti + j + 1]))
            cx = float(tokens[ti + 4]); cy = float(tokens[ti + 5])
            ti += 6
        elif cmd == 'c':
            for j in range(0, 6, 2):
                xs.append(cx + float(tokens[ti + j]))
                ys.append(cy + float(tokens[ti + j + 1]))
            cx += float(tokens[ti + 4]); cy += float(tokens[ti + 5])
            ti += 6
        elif cmd == 'S':
            for j in range(0, 4, 2):
                xs.append(float(tokens[ti + j]))
                ys.append(float(tokens[ti + j + 1]))
            cx = float(tokens[ti + 2]); cy = float(tokens[ti + 3])
            ti += 4
        elif cmd == 's':
            for j in range(0, 4, 2):
                xs.append(cx + float(tokens[ti + j]))
                ys.append(cy + float(tokens[ti + j + 1]))
            cx += float(tokens[ti + 2]); cy += float(tokens[ti + 3])
            ti += 4
        elif cmd == 'Q':
            for j in range(0, 4, 2):
                xs.append(float(tokens[ti + j]))
                ys.append(float(tokens[ti + j + 1]))
            cx = float(tokens[ti + 2]); cy = float(tokens[ti + 3])
            ti += 4
        elif cmd == 'q':
            for j in range(0, 4, 2):
                xs.append(cx + float(tokens[ti + j]))
                ys.append(cy + float(tokens[ti + j + 1]))
            cx += float(tokens[ti + 2]); cy += float(tokens[ti + 3])
            ti += 4
        elif cmd == 'A':
            xs.append(float(tokens[ti + 5]))
            ys.append(float(tokens[ti + 6]))
            cx = float(tokens[ti + 5]); cy = float(tokens[ti + 6])
            ti += 7
        elif cmd == 'a':
            cx += float(tokens[ti + 5]); cy += float(tokens[ti + 6])
            xs.append(cx); ys.append(cy)
            ti += 7
        elif cmd == 'T':
            cx, cy = val, float(tokens[ti + 1])
            xs.append(cx); ys.append(cy)
            ti += 2
        elif cmd == 't':
            cx += val; cy += float(tokens[ti + 1])
            xs.append(cx); ys.append(cy)
            ti += 2
        else:
            ti += 1

    if not xs or not ys:
        return None
    return min(xs), min(ys), max(xs), max(ys)


def parse_svg(path):
    """Parse an SVG and return structured elements."""
    tree = ET.parse(path)
    root = tree.getroot()

    for elem in root.iter():
        if '}' in elem.tag:
            elem.tag = elem.tag.split('}', 1)[1]
        for k in list(elem.attrib.keys()):
            if '}' in k:
                elem.attrib[k.split('}', 1)[1]] = elem.attrib.pop(k)

    # Build gradient lookup: id -> first stop color, and full gradient info
    import math as _math_parse
    gradient_colors = {}
    gradient_defs = {}  # id -> {'stops': [(color, location), ...], 'angle': degrees}
    for elem in root.iter():
        if elem.tag in ('linearGradient', 'radialGradient'):
            gid = elem.get('id', '')
            stops = []
            for stop in elem:
                sc = stop.get('stop-color', '')
                offset = float(stop.get('offset', '0'))
                if sc:
                    stops.append((sc, offset))
            if stops:
                gradient_colors[gid] = stops[0][0]
            if elem.tag == 'linearGradient' and stops:
                x1 = float(elem.get('x1', '0'))
                y1 = float(elem.get('y1', '0'))
                x2 = float(elem.get('x2', '0'))
                y2 = float(elem.get('y2', '0'))
                # SVG angle: atan2(dy, dx) in degrees. Convert to app convention (0=up, clockwise)
                svg_angle = _math_parse.degrees(_math_parse.atan2(y2 - y1, x2 - x1))
                app_angle = (svg_angle + 90) % 360
                gradient_defs[gid] = {'stops': stops, 'angle': app_angle}

    def resolve_fill(fill_attr):
        """Resolve fill attribute to a color. Returns (color, is_gradient, gradient_ref_id)."""
        if not fill_attr or fill_attr == 'none':
            return None, False, None
        if fill_attr.startswith('url(#'):
            ref_id = fill_attr[5:].rstrip(')')
            if ref_id.startswith('pattern'):
                return None, False, None  # pattern fill = device image
            color = gradient_colors.get(ref_id)
            return color, True, ref_id
        return fill_attr, False, None

    vb = root.get('viewBox', '').split()
    vw, vh = float(vb[2]), float(vb[3])

    main_g = root.find('.//g')
    children = list(main_g) if main_g is not None else list(root)

    elements = {
        'viewBox': (vw, vh),
        'bg_color': None,
        'slice_override_rects': [],
        'decorative_rects': [],
        'paths': [],
        'circles': [],
        'white_paths': [],
        'device_rects': [],
        'ellipses': [],
        'bg_gradient': None,  # gradient_defs entry if bg is a gradient
    }

    for elem in children:
        tag = elem.tag
        fill = elem.get('fill', '')

        if tag == 'rect':
            w = float(elem.get('width', '0'))
            h = float(elem.get('height', '0'))
            x = float(elem.get('x', '0'))
            y = float(elem.get('y', '0'))
            rx = elem.get('rx')

            resolved_color, is_gradient, grad_ref = resolve_fill(fill)

            if fill.startswith('url(#pattern'):
                # Pattern fills are device frame/screen images
                elements['device_rects'].append({
                    'x': x, 'y': y, 'w': w, 'h': h,
                    'rx': float(rx) if rx else None,
                    'fill': fill,
                    'transform': elem.get('transform', ''),
                })
            elif fill.startswith('url(') and resolved_color is None:
                # Unknown url ref — skip
                pass
            elif w >= vw * 0.95 and h >= vh * 0.95:
                # Full-viewBox rect = background; last opaque one wins (top layer covers previous)
                elements['bg_color'] = resolved_color or fill or elements['bg_color']
                if grad_ref and grad_ref in gradient_defs:
                    elements['bg_gradient'] = gradient_defs[grad_ref]
            elif (resolved_color or fill) and (resolved_color or fill) != elements.get('bg_color', '') and fill != 'none':
                effective = resolved_color or fill
                # Apply rotate(-180) transforms to get effective position
                eff_x, eff_y = x, y
                transform = elem.get('transform', '')
                rot_m = re.match(r'rotate\(([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\)', transform)
                if rot_m and abs(float(rot_m.group(1)) + 180) < 0.1:
                    # rotate(-180 cx cy) => effective x = 2*cx - x - w
                    rcx = float(rot_m.group(2))
                    rcy = float(rot_m.group(3))
                    eff_x = 2 * rcx - x - w
                    eff_y = 2 * rcy - y - h
                rect_info = {
                    'x': eff_x, 'y': eff_y, 'w': w, 'h': h, 'fill': effective,
                    'rx': float(rx) if rx else 0,
                }
                # Attach gradient info if this rect has a gradient fill
                if is_gradient and grad_ref and grad_ref in gradient_defs:
                    rect_info['gradient'] = gradient_defs[grad_ref]
                # Full-slice-height rects are potential slice overrides (checked later)
                # Smaller rects are decorative shapes (rounded rects behind devices, etc.)
                if h >= vh * 0.9:
                    elements['slice_override_rects'].append(rect_info)
                else:
                    elements['decorative_rects'].append(rect_info)

        elif tag == 'path':
            d = elem.get('d', '')
            bbox = parse_path_bbox(d)
            if not bbox:
                continue
            resolved_path_color, path_is_gradient, path_grad_ref = resolve_fill(fill)
            effective_fill = resolved_path_color or fill
            fill_norm = effective_fill.strip().lower()
            if fill_norm in ('#ffffff', 'white', '#fff'):
                elements['white_paths'].append({
                    'd': d, 'fill': effective_fill, 'bbox': bbox,
                })
            elif effective_fill and effective_fill != 'none' and effective_fill != elements.get('bg_color', ''):
                path_info = {
                    'd': d, 'fill': effective_fill, 'bbox': bbox,
                }
                if path_is_gradient and path_grad_ref and path_grad_ref in gradient_defs:
                    path_info['gradient'] = gradient_defs[path_grad_ref]
                elements['paths'].append(path_info)

        elif tag == 'circle':
            circ_color, circ_is_grad, circ_grad_ref = resolve_fill(fill)
            circ_info = {
                'cx': float(elem.get('cx', '0')),
                'cy': float(elem.get('cy', '0')),
                'r': float(elem.get('r', '0')),
                'fill': circ_color or fill,
            }
            if circ_is_grad and circ_grad_ref and circ_grad_ref in gradient_defs:
                circ_info['gradient'] = gradient_defs[circ_grad_ref]
            elements['circles'].append(circ_info)

        elif tag == 'ellipse':
            resolved_color, is_gradient, ell_grad_ref = resolve_fill(fill)
            eff_fill = resolved_color or fill
            if eff_fill and eff_fill != 'none' and not fill.startswith('url(#pattern'):
                ell_info = {
                    'cx': float(elem.get('cx', '0')),
                    'cy': float(elem.get('cy', '0')),
                    'rx': float(elem.get('rx', '0')),
                    'ry': float(elem.get('ry', '0')),
                    'fill': eff_fill,
                }
                if is_gradient and ell_grad_ref and ell_grad_ref in gradient_defs:
                    ell_info['gradient'] = gradient_defs[ell_grad_ref]
                elements['ellipses'].append(ell_info)

    return elements


def classify_white_paths(white_paths, slice_w, scale_x, scale_y, device_category):
    """Classify white paths into text elements per slice."""
    headline_fs = 140 if device_category == "ipadPro11" else 110
    texts = []
    for wp in white_paths:
        bx1, by1, bx2, by2 = wp['bbox']
        bw = bx2 - bx1
        bh = by2 - by1
        center_x = (bx1 + bx2) / 2
        slice_idx = int(center_x / slice_w)

        if bh > 250:
            txt = "This is a very catchy App Headline"
            fs = headline_fs
            fw = 500
            text_type = "headline"
        elif bh > 150:
            txt = "This is a title for a helpful feature"
            fs = 104
            fw = 500
            text_type = "title"
        elif bh > 80:
            txt = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Erat."
            fs = 65
            fw = 400
            text_type = "description"
        else:
            txt = "FEATURE"
            fs = 56
            fw = 600
            text_type = "label"

        texts.append({
            'slice': slice_idx,
            'type': text_type,
            'txt': txt,
            'fs': fs,
            'fw': fw,
            'bbox': (bx1, by1, bx2, by2),
        })

    return texts


def infer_slice_count(vw, vh):
    """Determine slice count from SVG viewBox by finding clean integer divisions."""
    # Try all reasonable slice counts, pick the one with cleanest division
    candidates = []
    for n in range(1, 21):
        sw = vw / n
        remainder = abs(sw - round(sw))
        if remainder < 1:
            candidates.append((n, round(sw)))
    return candidates


def gradient_to_shape_fill(gradient_info):
    """Convert a gradient_defs entry to shape fill JSON fields (fst + fgc)."""
    return {
        "fst": "gradient",
        "fgc": {
            "s": [
                {"id": uid(), "c": normalize_color(color), "l": loc}
                for color, loc in gradient_info['stops']
            ],
            "a": gradient_info['angle'],
        },
    }


def apply_gradient_to_shape(shape, element_data):
    """If element_data has a gradient, add fill style fields to shape dict."""
    gradient = element_data.get('gradient')
    if gradient:
        shape.update(gradient_to_shape_fill(gradient))


def build_shapes_for_row(data, preset_w, preset_h, num_slices, device_category, device_frame_id):
    """Build shape list from parsed SVG data.

    Uses uniform scaling (s_min) to preserve shape proportions and positions.
    Centers content in the preset dimensions when aspect ratios differ.
    """
    vw, vh = data['viewBox']
    slice_w = vw / num_slices

    # Uniform scale factor: fit SVG slice into preset while preserving aspect ratio
    scale_x = preset_w / slice_w
    scale_y = preset_h / vh
    s = min(scale_x, scale_y)  # uniform scale

    # Centering offset for the dimension with extra space
    ox = (preset_w - slice_w * s) / 2   # horizontal offset per slice
    oy = (preset_h - vh * s) / 2        # vertical offset

    def tx(svg_x):
        """Transform SVG x coordinate to model space."""
        # Determine which slice this x falls in
        slice_idx = int(svg_x / slice_w) if svg_x >= 0 else 0
        local_x = svg_x - slice_idx * slice_w
        return slice_idx * preset_w + local_x * s + ox

    def ty(svg_y):
        """Transform SVG y coordinate to model space."""
        return svg_y * s + oy

    def tw(svg_w):
        """Transform SVG width to model space."""
        return svg_w * s

    def th(svg_h):
        """Transform SVG height to model space."""
        return svg_h * s

    shapes = []

    # 1. Decorative SVG paths (these span multiple slices — use full-row coordinates)
    for p in data['paths']:
        bx1, by1, bx2, by2 = p['bbox']
        bw = bx2 - bx1
        bh = by2 - by1
        svg_content = (
            f"<svg width='{bw:.1f}' height='{bh:.1f}' "
            f"viewBox='{bx1:.2f} {by1:.2f} {bw:.2f} {bh:.2f}' "
            f"fill='none' xmlns='http://www.w3.org/2000/svg'>"
            f"<path d='{p['d']}' fill='{p['fill']}'/></svg>"
        )
        shapes.append({
            "t": "svg",
            "c": p['fill'],
            "suc": False,
            "svg": svg_content,
            "x": tx(bx1),
            "y": ty(by1),
            "w": tw(bw),
            "h": th(bh),
            "id": uid(),
        })

    # 1b. Decorative rectangles (colored rounded rects behind devices, etc.)
    for r in data['decorative_rects']:
        shape = {
            "t": "rectangle",
            "c": r['fill'],
            "x": tx(r['x']),
            "y": ty(r['y']),
            "w": tw(r['w']),
            "h": th(r['h']),
            "id": uid(),
        }
        if r['rx'] > 0:
            shape["br"] = r['rx'] * s
        apply_gradient_to_shape(shape, r)
        shapes.append(shape)

    # 2. Circles: pattern-filled = app icon placeholder, colored = decorative
    for c in data['circles']:
        r = c['r']
        if c['fill'].startswith('url(#pattern'):
            shapes.append({
                "t": "image",
                "c": "#98989D",
                "br": r * s,
                "x": tx(c['cx'] - r),
                "y": ty(c['cy'] - r),
                "w": 2 * r * s,
                "h": 2 * r * s,
                "id": uid(),
            })
        elif c['fill'] and c['fill'] != 'none':
            circ_shape = {
                "t": "circle",
                "c": c['fill'],
                "x": tx(c['cx'] - r),
                "y": ty(c['cy'] - r),
                "w": 2 * r * s,
                "h": 2 * r * s,
                "id": uid(),
            }
            apply_gradient_to_shape(circ_shape, c)
            shapes.append(circ_shape)

    # 2b. Decorative ellipses (colored circles/ovals)
    for e in data['ellipses']:
        ell_shape = {
            "t": "circle",
            "c": e['fill'],
            "x": tx(e['cx'] - e['rx']),
            "y": ty(e['cy'] - e['ry']),
            "w": tw(2 * e['rx']),
            "h": th(2 * e['ry']),
            "id": uid(),
        }
        apply_gradient_to_shape(ell_shape, e)
        shapes.append(ell_shape)

    # 3. Text elements
    texts = classify_white_paths(data['white_paths'], slice_w, scale_x, scale_y, device_category)
    for t in texts:
        bx1, by1, bx2, by2 = t['bbox']
        bw = bx2 - bx1
        fs = t['fs']

        frame_w = bw * s
        # Target max lines: labels=1, titles/headlines=2, descriptions=3
        max_lines = {'label': 1, 'headline': 2, 'title': 2, 'description': 3}.get(t['type'], 2)
        # Minimum width to fit text in target lines
        min_w = len(t['txt']) * fs * 0.55 / max_lines * 1.1
        # Cap at 85% of template width to leave margins
        max_w = preset_w * 0.85
        frame_w = max(frame_w, min(min_w, max_w))
        # Never exceed template width
        frame_w = min(frame_w, max_w)

        chars_per_line = max(1, frame_w / (fs * 0.55))
        lines = max(1, -(-len(t['txt']) // int(chars_per_line)))
        frame_h = lines * fs * 1.5

        center_x = tx((bx1 + bx2) / 2)
        frame_x = center_x - frame_w / 2
        frame_y = ty(by1) - fs * 0.15 * s

        shape = {
            "c": "#FFFFFF",
            "fn": "DM Sans",
            "fs": fs,
            "fw": t['fw'],
            "h": frame_h,
            "id": uid(),
            "t": "text",
            "ta": "center",
            "txt": t['txt'],
            "w": frame_w,
            "x": frame_x,
            "y": frame_y,
        }
        if t['type'] == 'headline':
            shape['lns'] = -20
            shape['ls'] = 0
        shapes.append(shape)

    # 4. Device frames
    # Separate by rotation angle: group rects that share the same transform
    import math as _math

    def parse_rotation(transform):
        """Extract rotation angle and center from transform string."""
        if not transform:
            return None
        m = re.match(r'rotate\(([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\)', transform)
        if m:
            return float(m.group(1)), float(m.group(2)), float(m.group(3))
        return None

    def rotated_center(r):
        """Get center of rect after rotation."""
        rot = parse_rotation(r.get('transform', ''))
        if not rot:
            return r['x'] + r['w'] / 2, r['y'] + r['h'] / 2
        angle, rcx, rcy = rot
        # Center of unrotated rect
        cx = r['x'] + r['w'] / 2
        cy = r['y'] + r['h'] / 2
        # Rotate center around rotation origin
        rad = _math.radians(angle)
        dx, dy = cx - rcx, cy - rcy
        rx = rcx + dx * _math.cos(rad) - dy * _math.sin(rad)
        ry = rcy + dx * _math.sin(rad) + dy * _math.cos(rad)
        return rx, ry

    def rotated_bbox(r):
        """Get axis-aligned bounding box of a rotated rect."""
        rot = parse_rotation(r.get('transform', ''))
        if not rot:
            return r['x'], r['y'], r['w'], r['h']
        angle, rcx, rcy = rot
        rad = _math.radians(angle)
        corners = [
            (r['x'], r['y']),
            (r['x'] + r['w'], r['y']),
            (r['x'] + r['w'], r['y'] + r['h']),
            (r['x'], r['y'] + r['h']),
        ]
        rotated = []
        for px, py in corners:
            dx, dy = px - rcx, py - rcy
            rx = rcx + dx * _math.cos(rad) - dy * _math.sin(rad)
            ry = rcy + dx * _math.sin(rad) + dy * _math.cos(rad)
            rotated.append((rx, ry))
        min_x = min(p[0] for p in rotated)
        min_y = min(p[1] for p in rotated)
        max_x = max(p[0] for p in rotated)
        max_y = max(p[1] for p in rotated)
        return min_x, min_y, max_x - min_x, max_y - min_y

    # Pair device rects (screen + frame) across all angles.
    # Strategy: pair each rect with the closest rect by center distance,
    # regardless of rotation. The smaller of each pair is the screen rect.
    # -90° rects paired with 0° rects are iPad frame overlays (discard the -90° one).
    all_rects = list(data['device_rects'])
    all_rects_with_info = []
    for r in all_rects:
        rot = parse_rotation(r.get('transform', ''))
        angle = round(rot[0], 1) if rot else 0.0
        cx, cy = rotated_center(r)
        all_rects_with_info.append((r, angle, cx, cy))

    paired = set()
    screen_rects = []  # (rect_dict, angle) tuples

    # Sort by area descending so we process larger (frame) rects first
    indexed = list(enumerate(all_rects_with_info))
    for i, (r, angle, cx, cy) in indexed:
        if i in paired:
            continue
        # Find closest unpaired rect
        best_j = None
        best_dist = float('inf')
        for j, (r2, angle2, cx2, cy2) in indexed:
            if j == i or j in paired:
                continue
            dist = _math.hypot(cx - cx2, cy - cy2)
            if dist < best_dist and dist < max(r['w'], r2['w']):
                best_dist = dist
                best_j = j

        if best_j is not None:
            r2, angle2, _, _ = all_rects_with_info[best_j]
            # Pick the smaller rect as screen
            if r['w'] * r['h'] <= r2['w'] * r2['h']:
                screen_r, screen_angle = r, angle
            else:
                screen_r, screen_angle = r2, angle2
            screen_rects.append((screen_r, screen_angle))
            paired.add(i)
            paired.add(best_j)

    # Handle unpaired rects (standalone devices)
    for i, (r, angle, _, _) in enumerate(all_rects_with_info):
        if i not in paired:
            screen_rects.append((r, angle))

    # Compute target aspect ratio for device frame
    target_ratio = DEVICE_FRAME_RATIOS.get(device_frame_id) if device_frame_id else None

    for sr, angle in screen_rects:
        if angle != 0:
            # For rotated devices, use the rotated bounding box for position
            bbox_x, bbox_y, bbox_w, bbox_h = rotated_bbox(sr)
            dev_x = tx(bbox_x)
            dev_y = ty(bbox_y)
            # Use unrotated dimensions for the shape (app applies rotation)
            dev_w = tw(sr['w'])
            dev_h = th(sr['h'])
        else:
            dev_x = tx(sr['x'])
            dev_y = ty(sr['y'])
            dev_w = tw(sr['w'])
            dev_h = th(sr['h'])

        # Enforce device frame aspect ratio: keep height, adjust width, re-center
        if target_ratio:
            correct_w = dev_h * target_ratio
            dev_x += (dev_w - correct_w) / 2
            dev_w = correct_w

        shape = {
            "t": "device",
            "c": "#00000000",
            "dc": device_category,
            "x": dev_x,
            "y": dev_y,
            "w": dev_w,
            "h": dev_h,
            "id": uid(),
        }
        if device_frame_id:
            shape["dfi"] = device_frame_id
        if angle != 0:
            shape["rot"] = angle
        shapes.append(shape)

    return shapes


def build_row(data, device_category, device_frame_id, row_label_override=None, force_preset=None):
    """Build a complete row dict."""
    vw, vh = data['viewBox']

    # 1. Determine slice count and preset from SVG geometry
    slice_candidates = infer_slice_count(vw, vh)
    # Filter to reasonable counts (2-20 slices, slice width > 500)
    slice_candidates = [(n, sw) for n, sw in slice_candidates if 500 < sw < vw and n >= 2]

    # Always determine best slice count + preset from SVG aspect ratios
    presets = PRESETS.get(device_category, [])
    best_preset_wh = None
    best_ratio_diff = float('inf')
    best_n = None

    for n, sw in slice_candidates:
        svg_ratio = vh / sw
        for pw, ph in presets:
            preset_ratio = ph / pw
            diff = abs(preset_ratio - svg_ratio)
            if diff < best_ratio_diff:
                best_ratio_diff = diff
                best_preset_wh = (pw, ph)
                best_n = n

    if best_preset_wh is None:
        best_n = slice_candidates[0][0]
        best_preset_wh = (int(vw / best_n), int(vh))

    num_slices = best_n

    # force_preset overrides dimensions but keeps the SVG-derived slice count
    if force_preset:
        preset_w, preset_h = force_preset
    else:
        preset_w, preset_h = best_preset_wh
    slice_w = vw / num_slices

    shapes = build_shapes_for_row(data, preset_w, preset_h, num_slices, device_category, device_frame_id)

    # Build templates
    bgc = data['bg_color'] or "#047855"
    templates = []
    for i in range(num_slices):
        tp = {"id": uid()}
        for r in data['slice_override_rects']:
            if (r['w'] >= slice_w * 0.9 and r['h'] >= vh * 0.9 and
                    abs(r['x'] - i * slice_w) < slice_w * 0.1):
                tp["bgc"] = r['fill']
                tp["ob"] = True
                # If the override rect has a gradient, set template background gradient
                if r.get('gradient'):
                    tp["bgs"] = "gradient"
                    tp["gc"] = {
                        "s": [
                            {"id": uid(), "c": normalize_color(color), "l": loc}
                            for color, loc in r['gradient']['stops']
                        ],
                        "a": r['gradient']['angle'],
                    }
                break
        if "bgc" not in tp:
            tp["bgc"] = bgc
        templates.append(tp)

    # Row label from presetLabel convention
    label_map = {
        (1242, 2688): 'iPhone 6.5" Display Portrait',
        (1284, 2778): 'iPhone 6.5" Display Portrait',
        (1290, 2796): 'iPhone 6.7" Display Portrait',
        (1320, 2868): 'iPhone 6.9" Display Portrait',
        (1206, 2622): 'iPhone 6.3" Display Portrait',
        (1179, 2556): 'iPhone 6.1" Display Portrait',
        (1260, 2736): 'iPhone 6.1" Display Portrait',
        (2064, 2752): 'iPad Pro 13" Display Portrait',
        (2048, 2732): 'iPad Pro 13" Display Portrait',
        (1668, 2420): 'iPad Pro 11" Display Portrait',
        (1668, 2388): 'iPad Pro 11" Display Portrait',
        (1080, 1920): 'Android Phone Portrait',
        (1080, 2340): 'Android Phone Portrait',
        (1440, 3120): 'Android Phone Portrait',
        (1200, 1920): 'Android Tablet Portrait',
        (1600, 2560): 'Android Tablet Portrait',
        (1280, 800): 'Mac Desktop Landscape',
    }
    row_label = row_label_override or label_map.get((preset_w, preset_h), f"{preset_w}\u00d7{preset_h}")

    # Normalize all color values in shapes
    color_keys = {'c', 'bgc'}
    for s in shapes:
        for k in color_keys:
            if k in s:
                s[k] = normalize_color(s[k])
    for tp in templates:
        for k in color_keys:
            if k in tp:
                tp[k] = normalize_color(tp[k])
    bgc = normalize_color(bgc)

    row = {
        "bgc": bgc,
        "ddbc": "#1C1C1F",
        "ddc": device_category,
        "id": uid(),
        "l": row_label,
        "s": shapes,
        "th": preset_h,
        "tp": templates,
        "tw": preset_w,
    }

    # Add gradient background if present
    bg_gradient = data.get('bg_gradient')
    if bg_gradient:
        row["bgs"] = "gradient"
        row["gc"] = {
            "s": [
                {"id": uid(), "c": normalize_color(color), "l": loc}
                for color, loc in bg_gradient['stops']
            ],
            "a": bg_gradient['angle'],
            "gt": "linear",
        }
        row["span"] = True
    if device_frame_id:
        row["ddfi"] = device_frame_id
    return row


def generate_template(template_num, iphone_svg, ipad_svg, android_svg, project_root=None):
    import os
    if project_root is None:
        project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    base = os.path.join(project_root, "screenshot", "Templates.bundle")
    out_path = os.path.join(base, f"template{template_num}", "project.json")

    print(f"\n=== Template {template_num} ===")
    for label, path in [("iPhone", iphone_svg), ("iPad", ipad_svg), ("Android", android_svg)]:
        data = parse_svg(path)
        print(f"  {label}: viewBox={data['viewBox']}, bg={data['bg_color']}, paths={len(data['paths'])}, white={len(data['white_paths'])}, devices={len(data['device_rects'])}")

    iphone_data = parse_svg(iphone_svg)
    ipad_data = parse_svg(ipad_svg)
    android_data = parse_svg(android_svg)

    iphone_row = build_row(iphone_data, "iphone", "iphone17promax-silver-portrait")
    ipad_row = build_row(ipad_data, "ipadPro11", "ipadpro11-silver-portrait")
    android_row = build_row(android_data, "android", None, force_preset=(1080, 2340))

    project = {
        "ls": {"alc": "en", "l": [{"c": "en", "l": "English"}], "o": {}},
        "m": 795800000.0,
        "r": [iphone_row, ipad_row, android_row],
    }

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, 'w') as f:
        json.dump(project, f, separators=(',', ':'))
    print(f"  Wrote {out_path}")

    for name, row in [("iPhone", iphone_row), ("iPad", ipad_row), ("Android", android_row)]:
        types = {}
        for s in row['s']:
            types[s['t']] = types.get(s['t'], 0) + 1
        print(f"  {name}: {row['tw']}x{row['th']} ({row['l']}), {len(row['tp'])} templates, shapes: {types}")


def generate_preview(project_json_path, preview_path, num_slices_shown=5):
    """Generate a tiny preview PNG from a project.json showing first N iPhone slices."""
    from PIL import Image, ImageDraw

    with open(project_json_path) as f:
        project = json.load(f)

    row = project['r'][0]  # iPhone row
    tw, th = row['tw'], row['th']
    templates = row['tp']
    shapes = row['s']

    # Preview dimensions: show first N slices, scale to ~preview height
    n = min(num_slices_shown, len(templates))
    preview_h = 36
    scale = preview_h / th
    slice_w = int(tw * scale)
    gap = 3  # gap between slices
    preview_w = slice_w * n + gap * (n - 1)

    img = Image.new('RGBA', (preview_w, preview_h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    def parse_color(c):
        if not c:
            return (128, 128, 128, 255)
        c = c.strip().lower()
        if c == 'black':
            return (0, 0, 0, 255)
        if c == 'white':
            return (255, 255, 255, 255)
        if c.startswith('#') and len(c) >= 7:
            try:
                r = int(c[1:3], 16)
                g = int(c[3:5], 16)
                b = int(c[5:7], 16)
                a = int(c[7:9], 16) if len(c) >= 9 else 255
                return (r, g, b, a)
            except ValueError:
                return (128, 128, 128, 255)
        return (128, 128, 128, 255)

    row_bg = parse_color(row.get('bgc'))

    for i in range(n):
        tp = templates[i]
        bg = parse_color(tp['bgc']) if tp.get('ob') else row_bg
        x_off = i * (slice_w + gap)
        # Draw slice background with rounded corners
        draw.rounded_rectangle(
            [x_off, 0, x_off + slice_w - 1, preview_h - 1],
            radius=6, fill=bg
        )

    # Draw shapes that fall within shown slices
    shown_width = tw * n
    for s in shapes:
        sx, sy = s.get('x', 0), s.get('y', 0)
        sw, sh = s.get('w', 0), s.get('h', 0)

        # Skip shapes outside shown slices
        if sx + sw < 0 or sx > shown_width or sy + sh < 0 or sy > th:
            continue

        # Map to preview coordinates
        slice_idx = max(0, int(sx / tw))
        if slice_idx >= n:
            continue
        local_x = sx - slice_idx * tw
        px = int(slice_idx * (slice_w + gap) + local_x * scale)
        py = int(sy * scale)
        pw = max(1, int(sw * scale))
        ph = max(1, int(sh * scale))

        color = parse_color(s.get('c'))
        t = s.get('t')

        if t in ('svg', 'rectangle'):
            draw.rectangle([px, py, px + pw, py + ph], fill=color)
        elif t == 'circle':
            draw.ellipse([px, py, px + pw, py + ph], fill=color)
        elif t == 'device':
            # Draw a dark rounded rect as device placeholder
            dev_color = (28, 28, 31, 200)
            br = max(2, int(min(pw, ph) * 0.08))
            draw.rounded_rectangle([px, py, px + pw, py + ph], radius=br, fill=dev_color)
            # Inner screen area (slightly lighter)
            inset = max(1, int(min(pw, ph) * 0.04))
            draw.rounded_rectangle(
                [px + inset, py + inset, px + pw - inset, py + ph - inset],
                radius=max(1, br - 1), fill=(60, 60, 66, 200)
            )
        elif t == 'text':
            # Draw text lines as thin white/colored bars
            fs = s.get('fs', 60)
            line_h = max(1, int(fs * scale * 0.6))
            line_gap = max(1, int(fs * scale * 0.4))
            text_color = (*color[:3], min(color[3], 180))
            cy = py
            for _ in range(min(3, max(1, ph // max(1, line_h + line_gap)))):
                lw = pw * 0.8 if _ == 2 else pw  # last line shorter
                lx = px + int((pw - lw) / 2) if s.get('ta') == 'center' else px
                draw.rounded_rectangle(
                    [int(lx), cy, int(lx + lw), cy + line_h],
                    radius=max(1, line_h // 2), fill=text_color
                )
                cy += line_h + line_gap
                if cy > py + ph:
                    break
        elif t == 'image':
            # App icon placeholder
            br = int(s.get('br', 0) * scale)
            draw.rounded_rectangle([px, py, px + pw, py + ph], radius=br, fill=(152, 152, 157, 200))

    img.save(preview_path, 'PNG')
    print(f"  Preview: {preview_path}")


def main():
    import os
    base = "/Users/taras/Library/CloudStorage/Dropbox/hustle/tempates"
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    bundle = os.path.join(project_root, "screenshot", "Templates.bundle")

    for tmpl_num, svg_num in [(n, n) for n in range(1, 28)]:
        generate_template(
            tmpl_num,
            f"{base}/iphone/{svg_num}.svg",
            f"{base}/ipad/{svg_num}.svg",
            f"{base}/android-phone/{svg_num}.svg",
        )

    # Generate previews for ALL templates (including 1-3)
    for tmpl_dir in sorted(os.listdir(bundle)):
        pj = os.path.join(bundle, tmpl_dir, "project.json")
        if os.path.isfile(pj):
            preview = os.path.join(bundle, tmpl_dir, "preview.png")
            generate_preview(pj, preview)


if __name__ == '__main__':
    main()
