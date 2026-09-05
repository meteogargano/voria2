// Public endpoints used by the official DPC radar viewer
// (https://radar.protezionecivile.it/): tile cache, REST API and websocket.
const TILE_BASE = "https://s3-prod-dpc-radar-webp-cache.s3.eu-south-1.amazonaws.com"
const API_BASE = "https://radar-api.protezionecivile.it"
const WSS_URL = "wss://radar-wss.protezionecivile.it/"

export const RADAR_PROTOCOL = "dpc-radar"

export const RADAR_WINDOW_MS = 7 * 24 * 3600 * 1000

export const RADAR_ATTRIBUTION =
  '<a href="https://radar.protezionecivile.it/" target="_blank" rel="noopener">Radar-DPC</a> — Dipartimento ' +
  'di Protezione Civile (<a href="https://creativecommons.org/licenses/by-sa/4.0/" target="_blank" rel="noopener">CC-BY-SA 4.0</a>)'

const PRODUCTS = [
  {id: "VMI", file: "vmi", periodMs: 5 * 60_000},
  {id: "SRI", file: "sri", periodMs: 5 * 60_000},
  {id: "SRT1", file: "srt1", periodMs: 5 * 60_000},
  {id: "CUM3", file: "cum3", periodMs: 30 * 60_000},
  {id: "CUM6", file: "cum6", periodMs: 30 * 60_000},
  {id: "CUM12", file: "cum12", periodMs: 30 * 60_000},
  {id: "CUM24", file: "cum24", periodMs: 30 * 60_000},
  {id: "TEMP", file: "temp", periodMs: 3600_000},
  {id: "IR_108", file: "ir_108", periodMs: 5 * 60_000},
]

export function productById(id) {
  return PRODUCTS.find((p) => p.id === id) || PRODUCTS[0]
}

export function rawTileUrl(productId, timeMs, z, x, y) {
  const product = productById(productId)
  const d = new Date(timeMs)
  const yyyy = d.getUTCFullYear()
  const mm = String(d.getUTCMonth() + 1).padStart(2, "0")
  const dd = String(d.getUTCDate()).padStart(2, "0")
  const hh = String(d.getUTCHours()).padStart(2, "0")
  const mi = String(d.getUTCMinutes()).padStart(2, "0")
  return (
    `${TILE_BASE}/${product.id}/${yyyy}/${mm}/${dd}/${hh}${mi}` +
    `/${z}/${x}/${y}/${product.file}.webp`
  )
}

export function parseProtocolUrl(url) {
  const rest = url.replace(`${RADAR_PROTOCOL}://`, "")
  const [productId, timeMs, z, x, y] = rest.split("/")
  if (!productId || !timeMs || !z || !x || !y) return null
  return {productId, timeMs: Number(timeMs), z, x, y}
}

export function tileUrl(productId, timeMs) {
  return `${RADAR_PROTOCOL}://${productId}/${timeMs}/{z}/{x}/{y}`
}

export function parsePeriod(iso) {
  const m = /^PT(?:(\d+)H)?(?:(\d+)M)?$/.exec(iso || "")
  if (!m) return null
  const hours = parseInt(m[1] || "0", 10)
  const minutes = parseInt(m[2] || "0", 10)
  return (hours * 3600 + minutes * 60) * 1000 || null
}

export function floorToPeriod(ms, periodMs) {
  return Math.floor(ms / periodMs) * periodMs
}

export async function fetchLatest(productId) {
  const res = await fetch(`${API_BASE}/findLastProductByType?type=${encodeURIComponent(productId)}`, {
    headers: {Accept: "application/json"},
  })
  if (!res.ok) throw new Error(`radar api error ${res.status}`)
  const body = await res.json()
  const last = body && body.lastProducts && body.lastProducts[0]
  if (!last || !Number.isFinite(last.time)) throw new Error("radar api empty response")
  return last
}

const FRAME_EVENT = "voria2:radar-frame"

export function emitFrame(detail) {
  window.dispatchEvent(new CustomEvent(FRAME_EVENT, {detail}))
}

export function onFrame(handler) {
  const listener = (event) => handler(event.detail)
  window.addEventListener(FRAME_EVENT, listener)
  return () => window.removeEventListener(FRAME_EVENT, listener)
}

const romeTimeFmt = new Intl.DateTimeFormat(undefined, {
  timeZone: "Europe/Rome",
  hour: "2-digit",
  minute: "2-digit",
  hourCycle: "h23",
})

const romeDayFmt = new Intl.DateTimeFormat(undefined, {
  timeZone: "Europe/Rome",
  weekday: "short",
  day: "numeric",
  month: "short",
})

export function formatTime(ms) {
  return romeTimeFmt.format(new Date(ms))
}

export function formatDay(ms) {
  return romeDayFmt.format(new Date(ms))
}

export function formatRelative(ms, now = Date.now()) {
  const rtf = new Intl.RelativeTimeFormat(undefined, {numeric: "auto"})
  const diffMin = Math.round((ms - now) / 60_000)
  if (Math.abs(diffMin) < 1) return rtf.format(0, "minute")
  if (Math.abs(diffMin) < 60) return rtf.format(diffMin, "minute")
  const diffH = Math.round(diffMin / 60)
  if (Math.abs(diffH) < 24) return rtf.format(diffH, "hour")
  return rtf.format(Math.round(diffH / 24), "day")
}

export function formatSub(ms) {
  return `${formatDay(ms)} · ${formatRelative(ms)}`
}

export function connectRadarSocket(onMessage, onClose) {
  let closed = false
  let ws
  try {
    ws = new WebSocket(WSS_URL)
  } catch {
    return {close: () => {}}
  }
  ws.onmessage = onMessage
  ws.onclose = () => {
    if (!closed) onClose()
  }
  ws.onerror = () => {
    try {
      ws.close()
    } catch {}
  }
  return {
    close() {
      closed = true
      ws.onclose = null
      ws.onmessage = null
      try {
        ws.close()
      } catch {}
    },
  }
}
