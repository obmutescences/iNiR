.pragma library

// Layout, coding and easing helpers for the windows picker.
// Mirrors docs/windows-picker/SPEC.md; keep both in sync.

const THUMB_RATIO = 10 / 16

function clamp(value, min, max) {
    return Math.min(max, Math.max(min, value))
}

function cubicBezier(t, x1, y1, x2, y2) {
    // Solve X(u) = t for u, then return Y(u). Newton with a bisection fallback.
    const cx = 3 * x1
    const bx = 3 * (x2 - x1) - cx
    const ax = 1 - cx - bx
    const cy = 3 * y1
    const by = 3 * (y2 - y1) - cy
    const ay = 1 - cy - by
    const sampleX = u => ((ax * u + bx) * u + cx) * u
    const sampleY = u => ((ay * u + by) * u + cy) * u
    let u = t
    for (let i = 0; i < 6; ++i) {
        const x = sampleX(u) - t
        if (Math.abs(x) < 1e-5)
            return sampleY(u)
        const d = (3 * ax * u + 2 * bx) * u + cx
        if (Math.abs(d) < 1e-6)
            break
        u -= x / d
    }
    let lo = 0
    let hi = 1
    u = t
    for (let i = 0; i < 24; ++i) {
        const x = sampleX(u)
        if (Math.abs(x - t) < 1e-5)
            break
        if (x < t)
            lo = u
        else
            hi = u
        u = (lo + hi) / 2
    }
    return sampleY(u)
}

const CURVES = {
    expoOut: [0.16, 1, 0.3, 1],
    springBouncy: [0.34, 1.56, 0.44, 1],
    springSoft: [0.25, 0.9, 0.35, 1.04],
    easeInOutCubic: [0.65, 0, 0.35, 1],
    cssEase: [0.25, 0.1, 0.25, 1]
}

// Per-mode entry geometry. close: 460ms easeInOutCubic for every mode.
const MODES = {
    fly: { duration: 560, curve: CURVES.expoOut, opacity: 240, opacityCurve: CURVES.cssEase },
    slide_up: { duration: 560, curve: CURVES.expoOut, opacity: 300, opacityCurve: CURVES.cssEase, shift: 56 },
    zoom_rotate: { duration: 640, curve: CURVES.springBouncy, opacity: 300, opacityCurve: CURVES.cssEase, scale: 0.34, rotation: -10 },
    flip: { duration: 620, curve: CURVES.springSoft, opacity: 220, opacityCurve: CURVES.cssEase, rotationX: 82, shift: 26 },
    unfold: { duration: 560, curve: CURVES.expoOut, opacity: 0, opacityCurve: CURVES.cssEase }
}

const CLOSE_DURATION = 460
const CLOSE_CURVE = CURVES.easeInOutCubic
const CLOSE_OPACITY_DELAY = 280
const CLOSE_OPACITY_DURATION = 150

function modeParams(mode) {
    return MODES[mode] ?? MODES.fly
}

function entryProgress(mode, elapsed, delay) {
    const params = modeParams(mode)
    const t = clamp((elapsed - delay) / params.duration, 0, 1)
    const [x1, y1, x2, y2] = params.curve
    return cubicBezier(t, x1, y1, x2, y2)
}

function exitProgress(elapsed, delay) {
    const t = clamp((elapsed - delay) / CLOSE_DURATION, 0, 1)
    const [x1, y1, x2, y2] = CLOSE_CURVE
    return 1 - cubicBezier(t, x1, y1, x2, y2)
}

function entryOpacity(mode, elapsed, delay) {
    const params = modeParams(mode)
    if (params.opacity <= 0)
        return 1
    const t = clamp((elapsed - delay) / params.opacity, 0, 1)
    const [x1, y1, x2, y2] = params.opacityCurve
    return cubicBezier(t, x1, y1, x2, y2)
}

function exitOpacity(elapsed, delay) {
    const t = clamp((elapsed - delay - CLOSE_OPACITY_DELAY) / CLOSE_OPACITY_DURATION, 0, 1)
    return 1 - t
}

function normalizeLetters(spec) {
    const raw = String(spec ?? "").toUpperCase()
    const seen = new Set()
    const letters = []
    for (const ch of raw) {
        if (ch < "A" || ch > "Z" || seen.has(ch))
            continue
        seen.add(ch)
        letters.push(ch)
    }
    return letters.length >= 2 ? letters : ["A", "S", "D", "F", "G", "H", "J", "K", "L"]
}

function shuffled(items) {
    const copy = items.slice()
    for (let i = copy.length - 1; i > 0; --i) {
        const j = Math.floor(Math.random() * (i + 1))
        const tmp = copy[i]
        copy[i] = copy[j]
        copy[j] = tmp
    }
    return copy
}

// N <= |L| -> single letters in configured order.
// N >  |L| -> every window gets a two-letter code, drawn at random from
//             |L| * (|L| - 1) ordered pairs. Never mixed lengths.
function assignCodes(count, letters) {
    if (count <= letters.length)
        return letters.slice(0, count)
    const pool = []
    for (const a of letters) {
        for (const b of letters) {
            if (a !== b)
                pool.push(a + b)
        }
    }
    return shuffled(pool).slice(0, count)
}

function gatherDelays(count, columns, mode, rows) {
    const delays = []
    const colCount = Math.max(1, columns)
    const rowCount = Math.max(1, rows ?? Math.ceil(count / colCount))
    const centerX = (colCount - 1) / 2
    const centerY = (rowCount - 1) / 2
    const maxDistance = Math.max(0.0001, Math.hypot(centerX, centerY))
    for (let i = 0; i < count; ++i) {
        const col = i % colCount
        const row = Math.floor(i / colCount)
        let delay = 0
        if (mode === "circular") {
            delay = 100 + 220 * (Math.hypot(col - centerX, row - centerY) / maxDistance)
        } else if (mode === "random") {
            delay = Math.random() * 400
        } else if (mode === "wave") {
            delay = col * 120 + row * 60
        } else {
            delay = (row + col) * 90
        }
        delays.push(Math.round(delay))
    }
    return delays
}

function layoutCards(count, screenWidth, screenHeight, options) {
    const opts = options ?? ({})
    const cardMax = opts.cardMax ?? 300
    const cardMin = opts.cardMin ?? 140
    const barHeight = opts.barHeight ?? 46
    const gapX = opts.gapX ?? 24
    const gapY = opts.gapY ?? 44
    const marginX = Math.max(36, Math.min(96, screenWidth * 0.05))
    const marginY = Math.max(32, Math.min(64, screenHeight * 0.05))
    const headerHeight = 58
    const areaWidth = screenWidth - marginX * 2
    const areaHeight = Math.max(120, screenHeight - marginY * 2 - headerHeight)

    let best = null
    for (let cols = 4; cols <= 8; ++cols) {
        const rows = Math.ceil(count / cols)
        const byWidth = (areaWidth - gapX * (cols - 1)) / cols
        const byHeight = ((areaHeight - gapY * (rows - 1)) / rows - barHeight) / THUMB_RATIO
        const width = Math.min(cardMax, byWidth, byHeight)
        // Larger columns only win when they actually buy a bigger card.
        if (!best || width > best.width + 0.5)
            best = { columns: cols, rows: rows, width: width }
    }

    const width = Math.max(cardMin, Math.min(cardMax, best.width))
    const cardHeight = width * THUMB_RATIO + barHeight
    // A short last row must not stretch the grid: only the used columns count.
    const usedColumns = Math.min(count, best.columns)
    const gridWidth = usedColumns * width + (usedColumns - 1) * gapX
    const contentHeight = best.rows * cardHeight + (best.rows - 1) * gapY
    const overflow = contentHeight > areaHeight + 0.5
    const originX = (areaWidth - gridWidth) / 2
    const originY = overflow ? 0 : (areaHeight - contentHeight) / 2

    const slots = []
    for (let i = 0; i < count; ++i) {
        const col = i % best.columns
        const row = Math.floor(i / best.columns)
        slots.push({
            x: originX + col * (width + gapX),
            y: originY + row * (cardHeight + gapY),
            w: width,
            h: cardHeight
        })
    }

    return {
        slots: slots,
        columns: best.columns,
        rows: best.rows,
        cardWidth: width,
        cardHeight: cardHeight,
        areaX: marginX,
        areaY: marginY + headerHeight,
        areaW: areaWidth,
        areaH: areaHeight,
        marginY: marginY,
        contentHeight: Math.max(areaHeight, contentHeight),
        overflow: overflow,
        gridX: originX,
        gridW: gridWidth
    }
}

// Best-effort screen rect for a window. Niri IPC exposes tile_size and the
// scrolling-layout position but no view offset, so the column of the focused
// window is centred on the output and everything else is placed relative to it.
function windowStartRect(windowData, workspaceWindows, screenWidth, screenHeight, focusedColumn) {
    const pos = windowData?.layout?.pos_in_scrolling_layout
    const tile = windowData?.layout?.tile_size
    const size = windowData?.layout?.window_size

    if (windowData?.is_floating) {
        const width = size?.[0] ?? screenWidth * 0.55
        const height = size?.[1] ?? screenHeight * 0.7
        return { x: (screenWidth - width) / 2, y: (screenHeight - height) / 2, w: width, h: height }
    }
    if (!pos || !tile)
        return { x: screenWidth * 0.2, y: screenHeight * 0.2, w: screenWidth * 0.6, h: screenHeight * 0.6 }

    const gap = 8
    const columnWidth = ({})
    const columnRows = ({})
    for (const other of workspaceWindows ?? []) {
        const otherPos = other?.layout?.pos_in_scrolling_layout
        if (!otherPos)
            continue
        const otherTile = other?.layout?.tile_size ?? tile
        const col = otherPos[0]
        const row = otherPos[1]
        columnWidth[col] = Math.max(columnWidth[col] ?? 0, otherTile[0])
        if (!columnRows[col])
            columnRows[col] = ({})
        columnRows[col][row] = Math.max(columnRows[col][row] ?? 0, otherTile[1])
    }

    const columns = Object.keys(columnWidth).map(Number).sort((a, b) => a - b)
    const columnStart = ({})
    let cursor = 0
    for (const col of columns) {
        columnStart[col] = cursor
        cursor += columnWidth[col] + gap
    }

    const anchor = columnStart[focusedColumn] !== undefined ? focusedColumn : columns[0]
    const offset = screenWidth / 2 - (columnStart[anchor] + columnWidth[anchor] / 2)

    const rows = columnRows[pos[0]] ?? ({})
    let y = 0
    for (const row of Object.keys(rows).map(Number).sort((a, b) => a - b)) {
        if (row >= pos[1])
            break
        y += rows[row] + gap
    }

    return {
        x: offset + columnStart[pos[0]],
        y: clamp(y, 0, Math.max(0, screenHeight - tile[1])),
        w: columnWidth[pos[0]],
        h: tile[1]
    }
}
