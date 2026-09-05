import {
  RADAR_WINDOW_MS,
  connectRadarSocket,
  emitFrame,
  fetchLatest,
  floorToPeriod,
  formatSub,
  formatTime,
  parsePeriod,
  productById,
} from "../radar"
import {legendDataUrl} from "../radar_palettes"

const PLAY_FRAME_MS = 500
const PLAY_WINDOW_MS = 3 * 3600_000
const PLAY_MIN_FRAMES = 12
const PLAY_LOOP_HOLD_MS = 1100
const SERVER_SYNC_DEBOUNCE_MS = 600
const WS_RECONNECT_MIN_MS = 1000
const WS_RECONNECT_MAX_MS = 60_000

const PLAY_SVG =
  '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M8 5.14v13.72c0 .8.87 1.3 1.56.88l10.54-6.86a1.05 1.05 0 000-1.76L9.56 4.26A1.04 1.04 0 008 5.14z"/></svg>'
const PAUSE_SVG =
  '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M7 5h3.5v14H7zM13.5 5H17v14h-3.5z"/></svg>'
const PREV_SVG =
  '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M17.7 5.3a1 1 0 010 1.4L13.4 11l4.3 4.3a1 1 0 01-1.4 1.4l-5-5a1 1 0 010-1.4l5-5a1 1 0 011.4 0zM7 5h2v14H7z"/></svg>'
const NEXT_SVG =
  '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M6.3 5.3a1 1 0 000 1.4L10.6 11l-4.3 4.3a1 1 0 001.4 1.4l5-5a1 1 0 000-1.4l-5-5a1 1 0 00-1.4 0zM15 5h2v14h-2z"/></svg>'

function esc(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
}

const RadarTimeline = {
  mounted() {
    this._enabled = false
    this._product = "VMI"
    this._latest = null
    this._period = null
    this._time = null
    this._live = true
    this._playing = false
    this._dragging = false
    this._ws = null
    this._wsTimer = null
    this._wsDelay = WS_RECONNECT_MIN_MS
    this._playTimer = null
    this._playHold = null
    this._syncTimer = null
    this._publishRaf = null
    this._hourFmt = new Intl.DateTimeFormat(undefined, {
      timeZone: "Europe/Rome",
      hour: "2-digit",
      hourCycle: "h23",
    })
    this._dayFmt = new Intl.DateTimeFormat(undefined, {
      timeZone: "Europe/Rome",
      weekday: "short",
      day: "numeric",
    })

    this.buildDom()

    this.handleEvent("radar_state", (config) => this.applyState(config))

    this._onVisibility = () => {
      if (document.hidden) {
        this.stopPlay()
        this.closeSocket()
      } else if (this._enabled) {
        this.openSocket()
      }
    }
    document.addEventListener("visibilitychange", this._onVisibility)
  },

  buildDom() {
    this.el.innerHTML = `
      <button type="button" id="radar-tl-play" class="radar-btn" title="Play">${PLAY_SVG}</button>
      <button type="button" id="radar-tl-prev" class="radar-btn" title="-1">${PREV_SVG}</button>
      <button type="button" id="radar-tl-next" class="radar-btn" title="+1">${NEXT_SVG}</button>
      <div class="radar-tl-times">
        <span id="radar-tl-time" class="radar-tl-time">—</span>
        <span id="radar-tl-sub" class="radar-tl-sub">—</span>
      </div>
      <div id="radar-tl-track" class="radar-tl-track">
        <div class="radar-tl-rail"></div>
        <div id="radar-tl-ticks" class="radar-tl-ticks"></div>
        <div id="radar-tl-fill" class="radar-tl-fill"></div>
        <div id="radar-tl-handle" class="radar-tl-handle" role="slider" tabindex="0"
          aria-label="Tempo radar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="100"></div>
      </div>
      <button type="button" id="radar-tl-live" class="radar-btn radar-btn--live">
        <span class="radar-live-dot"></span>LIVE
      </button>
    `

    this._els = {
      play: this.el.querySelector("#radar-tl-play"),
      prev: this.el.querySelector("#radar-tl-prev"),
      next: this.el.querySelector("#radar-tl-next"),
      time: this.el.querySelector("#radar-tl-time"),
      sub: this.el.querySelector("#radar-tl-sub"),
      track: this.el.querySelector("#radar-tl-track"),
      ticks: this.el.querySelector("#radar-tl-ticks"),
      fill: this.el.querySelector("#radar-tl-fill"),
      handle: this.el.querySelector("#radar-tl-handle"),
      live: this.el.querySelector("#radar-tl-live"),
    }

    this._els.play.addEventListener("click", () => this.togglePlay())
    this._els.prev.addEventListener("click", () => this.step(-1))
    this._els.next.addEventListener("click", () => this.step(1))
    this._els.live.addEventListener("click", () => this.goLive())

    this._onTrackDown = (e) => {
      if (!this._enabled || this._latest == null || this._period == null) return
      this.stopPlay()
      this._dragging = true
      this._els.track.classList.add("is-dragging")
      try {
        this._els.track.setPointerCapture(e.pointerId)
      } catch {}
      this.dragTo(e.clientX)
    }
    this._onTrackMove = (e) => {
      if (this._dragging) this.dragTo(e.clientX)
    }
    this._onTrackUp = (e) => {
      if (!this._dragging) return
      this._dragging = false
      this._els.track.classList.remove("is-dragging")
      try {
        this._els.track.releasePointerCapture(e.pointerId)
      } catch {}
      this.publishFrame()
    }
    this._onHandleKey = (e) => {
      if (!this._enabled || this._latest == null || this._period == null) return
      const hours = this._period >= 3600_000 ? 1 : Math.max(1, Math.round(3600_000 / this._period))
      let handled = true
      if (e.key === "ArrowLeft") this.step(e.shiftKey ? -hours : -1)
      else if (e.key === "ArrowRight") this.step(e.shiftKey ? hours : 1)
      else if (e.key === "Home") this.setTime(this.oldestTime())
      else if (e.key === "End") this.goLive()
      else handled = false
      if (handled) e.preventDefault()
    }

    this._els.track.addEventListener("pointerdown", this._onTrackDown)
    this._els.track.addEventListener("pointermove", this._onTrackMove)
    this._els.track.addEventListener("pointerup", this._onTrackUp)
    this._els.track.addEventListener("pointercancel", this._onTrackUp)
    this._els.handle.addEventListener("keydown", this._onHandleKey)

    const legend = document.getElementById("radar-legend")
    if (legend) {
      this._legend = legend
      this._legendImg = legend.querySelector("img")
      this._onLegendError = () => legend.classList.remove("radar-legend--on")
      this._legendImg?.addEventListener("error", this._onLegendError)
    }
  },

  applyState({enabled, product, opacity} = {}) {
    const prevProduct = this._product
    this._enabled = !!enabled
    if (product && product !== this._product) this._product = product
    this.el.classList.toggle("radar-timeline--on", this._enabled)
    this.updateLegend()

    if (this._enabled) {
      this.openSocket()
      if (this._latest == null || prevProduct !== this._product) {
        this.resync()
      } else {
        this.publishFrame()
      }
    } else {
      this.stopPlay()
      this.closeSocket()
    }
  },

  updateLegend() {
    if (!this._legend || !this._legendImg) return
    if (this._enabled) {
      if (this._legendImg.dataset.product !== this._product) {
        this._legendImg.dataset.product = this._product
        this._legendImg.src = legendDataUrl(this._product)
      }
      this._legend.classList.add("radar-legend--on")
    } else {
      this._legend.classList.remove("radar-legend--on")
    }
  },

  async resync() {
    if (this._syncing) return
    this._syncing = true
    this._els.sub.textContent = "…"
    try {
      const last = await fetchLatest(this._product)
      const period = parsePeriod(last.period) || productById(this._product).periodMs
      const latest = floorToPeriod(last.time, period)
      this._latest = latest
      this._period = period
      if (this._live || this._time == null) {
        this._time = latest
      } else {
        this._time = this.snapToGrid(this._time)
      }
      this.buildTicks()
      this.publishFrame()
    } catch {
      this._els.time.textContent = "—"
      this._els.sub.textContent = "—"
    } finally {
      this._syncing = false
    }
  },

  snapToGrid(time) {
    const maxIdx = Math.floor(this.windowSpan() / this._period)
    const idx = Math.min(Math.max(Math.round((this._latest - time) / this._period), 0), maxIdx)
    return this._latest - idx * this._period
  },

  windowSpan() {
    return RADAR_WINDOW_MS
  },

  oldestTime() {
    if (this._latest == null || this._period == null) return null
    const maxIdx = Math.floor(this.windowSpan() / this._period)
    return this._latest - maxIdx * this._period
  },

  posFor(time) {
    const oldest = this._latest - this.windowSpan()
    return Math.min(Math.max(((time - oldest) / this.windowSpan()) * 100, 0), 100)
  },

  buildTicks() {
    if (this._latest == null || !this._els.ticks) return
    const oldest = this._latest - this.windowSpan()
    const start = Math.floor(this._latest / 3600_000) * 3600_000
    let html = ""
    let lastDay = null
    for (let t = start; t >= oldest; t -= 3600_000) {
      const hour = parseInt(this._hourFmt.format(new Date(t)), 10)
      const day = this._dayFmt.format(new Date(t))
      const pos = this.posFor(t).toFixed(3)
      if (lastDay !== null && day !== lastDay) {
        html += `<div class="radar-tl-tick radar-tl-tick--day" style="left:${pos}%"></div>`
        html += `<div class="radar-tl-tick-label" style="left:${pos}%">${esc(day)}</div>`
      } else if (hour % 3 === 0) {
        html += `<div class="radar-tl-tick" style="left:${pos}%"></div>`
      }
      lastDay = day
    }
    this._els.ticks.innerHTML = html
  },

  dragTo(clientX) {
    if (this._latest == null || this._period == null) return
    const rect = this._els.track.getBoundingClientRect()
    if (rect.width === 0) return
    const ratio = Math.min(Math.max((clientX - rect.left) / rect.width, 0), 1)
    const oldest = this._latest - this.windowSpan()
    const idx = Math.round(((oldest + ratio * this.windowSpan() - this._latest) / this._period))
    const maxIdx = Math.floor(this.windowSpan() / this._period)
    const clamped = Math.min(Math.max(idx, -maxIdx), 0)
    const time = this._latest + clamped * this._period
    if (time !== this._time) {
      this._time = time
      this._live = false
      this.schedulePublish()
    }
  },

  step(frames) {
    if (this._latest == null || this._period == null) return
    this.stopPlay()
    const oldest = this.oldestTime()
    const next = this._time + frames * this._period
    this.setTime(Math.min(Math.max(next, oldest), this._latest))
  },

  goLive() {
    if (this._latest == null) return
    this.stopPlay()
    this.setTime(this._latest)
    if (this.pushEvent) this.pushEvent("radar_go_live", {})
  },

  setTime(time) {
    if (time === this._time) {
      this.publishFrame()
      return
    }
    this._time = time
    this.publishFrame()
  },

  togglePlay() {
    if (this._playing) {
      this.stopPlay()
    } else {
      this.startPlay()
    }
  },

  startPlay() {
    if (!this._enabled || this._latest == null || this._period == null) return
    const span = this.windowSpan()
    let count = Math.max(Math.round(PLAY_WINDOW_MS / this._period), PLAY_MIN_FRAMES)
    count = Math.min(count, Math.floor(span / this._period) + 1)
    this._playFrom = this._latest - (count - 1) * this._period
    this._playing = true
    this._els.play.innerHTML = PAUSE_SVG
    this._els.play.classList.add("is-active")
    this._time = this._playFrom
    this.publishFrame()
    this._playTimer = setInterval(() => this.advancePlay(), PLAY_FRAME_MS)
  },

  advancePlay() {
    const next = this._time + this._period
    if (next >= this._latest) {
      this._time = this._latest
      this.publishFrame()
      clearInterval(this._playTimer)
      this._playTimer = null
      this._playHold = setTimeout(() => {
        if (this._playing) {
          this._time = this._playFrom
          this.publishFrame()
          this._playTimer = setInterval(() => this.advancePlay(), PLAY_FRAME_MS)
        }
      }, PLAY_LOOP_HOLD_MS)
    } else {
      this._time = next
      this.publishFrame()
    }
  },

  stopPlay() {
    this._playing = false
    if (this._playTimer) {
      clearInterval(this._playTimer)
      this._playTimer = null
    }
    if (this._playHold) {
      clearTimeout(this._playHold)
      this._playHold = null
    }
    if (this._els) {
      this._els.play.innerHTML = PLAY_SVG
      this._els.play.classList.remove("is-active")
    }
  },

  schedulePublish() {
    if (this._publishRaf) return
    this._publishRaf = requestAnimationFrame(() => {
      this._publishRaf = null
      this.publishFrame()
    })
  },

  publishFrame() {
    if (!this._enabled || this._time == null || this._latest == null) return
    if (this._time >= this._latest) {
      this._time = this._latest
      this._live = true
    } else {
      this._live = false
    }

    emitFrame({time: this._time, live: this._live, product: this._product})

    this._els.time.textContent = formatTime(this._time)
    this._els.sub.textContent = formatSub(this._time)

    const pos = this.posFor(this._time)
    this._els.handle.style.left = `${pos}%`
    this._els.fill.style.left = `${pos}%`
    this._els.fill.style.width = `${100 - pos}%`
    this._els.handle.setAttribute("aria-valuenow", String(Math.round(pos)))
    this._els.handle.setAttribute("aria-valuetext", formatSub(this._time))
    this._els.live.classList.toggle("is-live", this._live)

    if (this._syncTimer) clearTimeout(this._syncTimer)
    this._syncTimer = setTimeout(() => {
      if (this.pushEvent) this.pushEvent("radar_time_changed", {time: this._time, live: this._live})
    }, SERVER_SYNC_DEBOUNCE_MS)
  },

  openSocket() {
    if (this._ws || document.hidden) return
    const socket = connectRadarSocket(
      (ev) => this.onSocketMessage(ev),
      () => this.scheduleReconnect()
    )
    this._ws = socket
  },

  onSocketMessage(ev) {
    let msg
    try {
      msg = JSON.parse(ev.data)
    } catch {
      return
    }
    if (!msg || msg.productType !== this._product || !Number.isFinite(msg.time)) return
    const period = this._period || productById(this._product).periodMs
    const t = floorToPeriod(msg.time, period)
    if (this._latest == null || t > this._latest) {
      this._latest = t
      if (this._live && !this._playing) {
        this._time = t
        this.buildTicks()
        this.publishFrame()
      } else {
        this.buildTicks()
      }
    }
  },

  scheduleReconnect() {
    this._ws = null
    if (!this._enabled) return
    if (this._wsTimer) clearTimeout(this._wsTimer)
    this._wsTimer = setTimeout(() => {
      this._wsTimer = null
      if (this._enabled && !document.hidden) {
        this.openSocket()
        this.resync()
      }
    }, this._wsDelay)
    this._wsDelay = Math.min(this._wsDelay * 2, WS_RECONNECT_MAX_MS)
  },

  closeSocket() {
    if (this._wsTimer) {
      clearTimeout(this._wsTimer)
      this._wsTimer = null
    }
    this._wsDelay = WS_RECONNECT_MIN_MS
    if (this._ws) {
      this._ws.close()
      this._ws = null
    }
  },

  destroyed() {
    this.stopPlay()
    this.closeSocket()
    if (this._syncTimer) clearTimeout(this._syncTimer)
    if (this._publishRaf) cancelAnimationFrame(this._publishRaf)
    document.removeEventListener("visibilitychange", this._onVisibility)
    if (this._legendImg && this._onLegendError) {
      this._legendImg.removeEventListener("error", this._onLegendError)
    }
  },
}

export default RadarTimeline
