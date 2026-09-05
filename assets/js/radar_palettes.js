// Color rendering for the DPC radar overlay.
//
// PROVENANCE: the palettes below (paletteVMI, paletteSRI, paletteCUM,
// paletteTEMP, paletteIR108) are a faithful JavaScript port of the WebGL
// fragment shader shipped with the official Dipartimento della Protezione
// Civile radar viewer at https://radar.protezionecivile.it/ — specifically
// the `paletteVMI/SRI/CUM/TEMP/IR108` GLSL functions and the value decode
// `valuePhys() = mix(u_srcMin, u_srcMax, rgba.r)` found in the site's
// minified JS bundle (srcMin/srcMax per product, no-data cuts, smoothstep
// interpolation, alpha ramps and the vividness boost are preserved as-is).
//
// The DPC webp tiles encode the physical value in the red channel of an
// otherwise grayscale raster, so the client must apply these palettes to
// reproduce the official look. Data and palette are (c) Dipartimento della
// Protezione Civile, CC-BY-SA 4.0 (see RADAR_ATTRIBUTION in radar.js).
//
// Deviations from the original shader:
// - GLSL vec3/mix/smoothstep expressed with plain JS helpers (glSmoothstep
//   also allows flipped edges like GLSL does, used by paletteIR108).
// - TEMP: the constant sea fill value encoded in the red channel (R=68) is
//   treated as no-data (noDataFillR) to keep the sea transparent; the
//   original viewer renders it as its mapped color instead.
// - Edge color bleeding (bleedEdges) is added so GPU bilinear/mipmap
//   filtering of the colorized tiles fades to the correct color instead of
//   smearing dark fringes; the original avoids the problem by colorizing
//   per-pixel in the shader.

const clamp = (x, lo, hi) => (x < lo ? lo : x > hi ? hi : x)

function glSmoothstep(e0, e1, x) {
  const t = clamp((x - e0) / (e1 - e0), 0, 1)
  return t * t * (3 - 2 * t)
}

const norm01 = (v, lo, hi) => clamp((v - lo) / Math.max(1e-6, hi - lo), 0, 1)
const mix = (a, b, t) => a + (b - a) * t
const mix3 = (c0, c1, t) => [mix(c0[0], c1[0], t), mix(c0[1], c1[1], t), mix(c0[2], c1[2], t)]

const GRAY135 = [135 / 255, 135 / 255, 135 / 255]
const CYAN = [0, 250 / 255, 250 / 255]
const GREEN = [0, 250 / 255, 0]
const YELLOW = [250 / 255, 250 / 255, 0]
const ORANGE = [250 / 255, 100 / 255, 0]
const RED = [250 / 255, 0, 0]
const MAGENTA = [250 / 255, 0, 240 / 255]
const WHITE = [1, 1, 1]

function segmentSampler(stops) {
  return (v) => {
    if (v <= stops[0][0]) return [stops[0][1], stops[0][2]]
    const last = stops[stops.length - 1]
    if (v >= last[0]) return [last[1], last[2]]
    for (let i = 0; i < stops.length - 1; i++) {
      const [v0, c0, a0] = stops[i]
      const [v1, c1, a1] = stops[i + 1]
      if (v <= v1) return [mix3(c0, c1, glSmoothstep(v0, v1, v)), mix(a0, a1, glSmoothstep(v0, v1, v))]
    }
    return [last[1], last[2]]
  }
}

function boostVivid([r, g, b]) {
  let c = [r, g, b]
  const luma = 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]
  c = c.map((x) => clamp(mix(luma, x, 1.3), 0, 1))
  c = c.map((x) => clamp((x - 0.5) * 1.08 + 0.5, 0, 1))
  c = c.map((x) => Math.pow(x, 1 / 0.92))
  return c
}

const sampleVMI = segmentSampler([
  [0, GRAY135, 0],
  [10, CYAN, 0],
  [20, CYAN, 0.4],
  [30, GREEN, 0.8],
  [40, YELLOW, 0.8],
  [50, ORANGE, 0.8],
  [100, RED, 0.8],
])

function paletteVMI(v) {
  const [col, alpha] = sampleVMI(v)
  return [boostVivid(col), alpha]
}

function paletteSRI(v) {
  const t = norm01(v, 0, 100)
  const c0 = [0.75, 0.90, 0.5]
  const c1 = [0.00, 0.80, 1.00]
  const c2 = [0.00, 0.80, 0.00]
  const c3 = [1.00, 1.00, 0.00]
  const c4 = [1.00, 0.65, 0.30]
  const c5 = [1.00, 0.00, 0.30]
  const c6 = [0.60, 0.00, 0.80]
  const A = mix3(c0, c1, glSmoothstep(0.0, 0.08, t))
  const B = mix3(c2, c3, glSmoothstep(0.12, 0.30, t))
  const D = mix3(c4, c5, glSmoothstep(0.4, 0.7, t))
  const E = mix3(D, c6, glSmoothstep(0.7, 1.0, t))
  const col = mix3(mix3(A, B, t >= 0.2 ? 1 : 0), E, glSmoothstep(0.35, 1.0, t))
  return [col, glSmoothstep(0.01, 0.05, t)]
}

const sampleCUM = segmentSampler([
  [0, WHITE, 0],
  [0.1, CYAN, 0.4],
  [10.1, GREEN, 0.7],
  [20.1, YELLOW, 0.7],
  [40.1, ORANGE, 0.9],
  [60.1, RED, 0.9],
  [100.1, MAGENTA, 0.9],
])

const paletteCUM = (v) => sampleCUM(clamp(v, 0, 100.1))

const TEMP_STOPS = [
  [-16, [0, 26, 140]],
  [-14, [0, 46, 158]],
  [-10, [0, 85, 255]],
  [-4, [0, 181, 255]],
  [-2, [121, 225, 255]],
  [0, [0, 255, 0]],
  [2, [102, 255, 0]],
  [4, [153, 255, 0]],
  [8, [204, 255, 0]],
  [12, [255, 255, 102]],
  [16, [255, 234, 128]],
  [20, [255, 195, 77]],
  [24, [255, 158, 26]],
  [28, [255, 111, 0]],
  [32, [255, 54, 0]],
  [36, [224, 0, 0]],
  [40, [255, 0, 255]],
  [44, [178, 102, 255]],
].map(([v, rgb]) => [v, rgb.map((x) => x / 255)])

const sampleTEMP = segmentSampler(TEMP_STOPS)

const paletteTEMP = (v) => [sampleTEMP(v)[0], 0.95]

const IR_STOPS = [
  [-70, 1.0],
  [-60, 0.985],
  [-50, 0.975],
  [-40, 0.965],
  [-30, 0.955],
  [-20, 0.945],
  [-10, 0.935],
  [0, 0.925],
  [5, 0.91],
  [10, 0.895],
  [20, 0.87],
  [35, 0.84],
]

function paletteIR108(v) {
  let col = IR_STOPS[IR_STOPS.length - 1][1]
  for (let i = 0; i < IR_STOPS.length - 1; i++) {
    const [v0, g0] = IR_STOPS[i]
    const [v1, g1] = IR_STOPS[i + 1]
    if (v <= v1) {
      col = mix(g0, g1, glSmoothstep(0, 1, clamp((v - v0) / Math.max(1e-6, v1 - v0), 0, 1)))
      break
    }
  }
  const g = Math.pow(col, 0.85)

  let a
  if (v >= 20) a = 0
  else if (v >= 10) a = glSmoothstep(20, 10, v) * 0.35
  else if (v >= 0) a = mix(0.35, 0.6, glSmoothstep(10, 0, v))
  else if (v >= -20) a = mix(0.6, 0.85, glSmoothstep(0, -20, v))
  else if (v >= -40) a = mix(0.85, 0.95, glSmoothstep(-20, -40, v))
  else if (v >= -60) a = mix(0.95, 0.98, glSmoothstep(-40, -60, v))
  else a = 0.98

  return [[g, g, g], a * 0.95]
}

const PALETTES = {
  VMI: {unit: "dBZ", srcMin: 0, srcMax: 60, noDataCut01: 0, sample: paletteVMI},
  SRI: {unit: "mm/h", srcMin: 0, srcMax: 100, noDataCut01: 0, sample: paletteSRI},
  SRT1: {unit: "mm/h", srcMin: 0, srcMax: 100, noDataCut01: 0, sample: paletteSRI},
  CUM3: {unit: "mm", srcMin: 0, srcMax: 200, noDataCut01: 0, sample: paletteCUM},
  CUM6: {unit: "mm", srcMin: 0, srcMax: 200, noDataCut01: 0, sample: paletteCUM},
  CUM12: {unit: "mm", srcMin: 0, srcMax: 200, noDataCut01: 0, sample: paletteCUM},
  CUM24: {unit: "mm", srcMin: 0, srcMax: 200, noDataCut01: 0, sample: paletteCUM},
  TEMP: {unit: "°C", srcMin: -20, srcMax: 45, noDataCut01: 0.05, noDataFillR: [67, 69], sample: paletteTEMP},
  IR_108: {unit: "°C", srcMin: -70, srcMax: 35, noDataCut01: 0.03, sample: paletteIR108},
}

function paletteFor(productId) {
  return PALETTES[productId] || PALETTES.VMI
}

function colorizeData(productId, {data, width, height}) {
  const p = paletteFor(productId)
  for (let i = 0; i < data.length; i += 4) {
    const aIn = data[i + 3]
    if (aIn < 1) {
      data[i + 3] = 0
      continue
    }
    const v01 = data[i] / 255
    if (p.noDataCut01 > 0 && v01 <= p.noDataCut01) {
      data[i + 3] = 0
      continue
    }
    if (p.noDataFillR && data[i] >= p.noDataFillR[0] && data[i] <= p.noDataFillR[1]) {
      data[i + 3] = 0
      continue
    }
    const v = p.srcMin + v01 * (p.srcMax - p.srcMin)
    const [col, alpha] = p.sample(v)
    data[i] = Math.round(col[0] * 255)
    data[i + 1] = Math.round(col[1] * 255)
    data[i + 2] = Math.round(col[2] * 255)
    data[i + 3] = Math.round(clamp(alpha, 0, 1) * 255)
  }
  return {data, width, height}
}

function bleedEdges({data, width, height}, passes = 3) {
  const has = new Uint8Array(width * height)
  for (let p = 0; p < width * height; p++) {
    if (data[p * 4 + 3] > 0) has[p] = 1
  }
  for (let pass = 0; pass < passes; pass++) {
    const filled = []
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const p = y * width + x
        if (has[p]) continue
        let src = -1
        if (x > 0 && has[p - 1]) src = p - 1
        else if (x < width - 1 && has[p + 1]) src = p + 1
        else if (y > 0 && has[p - width]) src = p - width
        else if (y < height - 1 && has[p + width]) src = p + width
        if (src >= 0) filled.push([p, src])
      }
    }
    if (filled.length === 0) break
    for (const [p, src] of filled) {
      data[p * 4] = data[src * 4]
      data[p * 4 + 1] = data[src * 4 + 1]
      data[p * 4 + 2] = data[src * 4 + 2]
      has[p] = 1
    }
  }
  return {data, width, height}
}

export async function colorizeBitmap(productId, bitmap) {
  const canvas = document.createElement("canvas")
  canvas.width = bitmap.width
  canvas.height = bitmap.height
  const ctx = canvas.getContext("2d", {willReadFrequently: true})
  ctx.drawImage(bitmap, 0, 0)
  const image = ctx.getImageData(0, 0, canvas.width, canvas.height)
  bleedEdges(colorizeData(productId, image))
  ctx.putImageData(image, 0, 0)
  const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/png"))
  return blob.arrayBuffer()
}

export function legendDataUrl(productId) {
  const p = paletteFor(productId)
  const barW = 26
  const labelW = 46
  const h = 360
  const canvas = document.createElement("canvas")
  canvas.width = barW + labelW
  canvas.height = h
  const ctx = canvas.getContext("2d")

  ctx.fillStyle = "#ffffff"
  ctx.fillRect(0, 0, canvas.width, canvas.height)

  for (let y = 0; y < h; y++) {
    const v = mix(p.srcMax, p.srcMin, y / (h - 1))
    const [col, alpha] = p.sample(v)
    ctx.fillStyle = `rgba(${Math.round(col[0] * 255)},${Math.round(col[1] * 255)},${Math.round(col[2] * 255)},${clamp(alpha, 0, 1)})`
    ctx.fillRect(0, y, barW, 1)
  }

  ctx.strokeStyle = "rgba(0,0,0,0.55)"
  ctx.strokeRect(0.5, 0.5, barW - 1, h - 1)

  ctx.fillStyle = "rgba(0,0,0,0.75)"
  ctx.font = "11px system-ui, sans-serif"
  ctx.textAlign = "left"
  ctx.textBaseline = "middle"
  const ticks = 5
  for (let i = 0; i < ticks; i++) {
    const f = i / (ticks - 1)
    const y = Math.round(f * (h - 1))
    const v = mix(p.srcMax, p.srcMin, f)
    ctx.fillRect(barW, y - 1, 4, 2)
    const text = Number.isInteger(v) ? String(v) : v.toFixed(1)
    ctx.fillText(text, barW + 7, y)
  }

  ctx.textAlign = "center"
  ctx.fillText(p.unit, barW / 2, h - 9 + 6)
  return canvas.toDataURL("image/png")
}
