import {addProtocol, config as maplibreConfig, Map as MapLib, Marker, NavigationControl} from "maplibre-gl"
import {RADAR_ATTRIBUTION, onFrame, parseProtocolUrl, RADAR_PROTOCOL, rawTileUrl, tileUrl} from "../radar"
import {colorizeBitmap} from "../radar_palettes"

maplibreConfig.WORKER_URL = "/assets/js/maplibre_worker.js"

const STYLES = {
  light: "https://basemaps.cartocdn.com/gl/positron-gl-style/style.json",
  dark: "https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json",
}

const ATTRIBUTION =
  '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>'

// Viewport padding used when fitting every marker on screen.
// Equivalent to the previous Leaflet fitBounds(bounds.pad(0.25)).
const FIT_PADDING_RATIO = 1 / 6
const FIT_PADDING_MIN = 40

// Radar DPC overlay: tiles only exist up to z7, MapLibre upscales beyond it.
const RADAR_SOURCE_ID = "dpc-radar"
const RADAR_LAYER_ID = "dpc-radar-layer"
const RADAR_MAX_ZOOM = 7

function cartoKey() {
  return document.querySelector('meta[name="carto-basemaps-api-key"]')?.content || ""
}

const TILE_CACHE_MAX = 128
const tileCache = new Map()
const tileInFlight = new Map()

function fetchColorizedTile(url) {
  const cached = tileCache.get(url)
  if (cached) {
    tileCache.delete(url)
    tileCache.set(url, cached)
    return Promise.resolve(cached)
  }
  let pending = tileInFlight.get(url)
  if (!pending) {
    pending = (async () => {
      const parts = parseProtocolUrl(url)
      if (!parts) throw new Error(`invalid radar tile url: ${url}`)
      const raw = rawTileUrl(parts.productId, parts.timeMs, parts.z, parts.x, parts.y)
      const res = await fetch(raw)
      if (!res.ok) throw new Error(`radar tile error ${res.status}: ${raw}`)
      const bitmap = await createImageBitmap(await res.blob())
      const buffer = await colorizeBitmap(parts.productId, bitmap)
      bitmap.close()
      if (tileCache.size >= TILE_CACHE_MAX) {
        tileCache.delete(tileCache.keys().next().value)
      }
      tileCache.set(url, buffer)
      return buffer
    })()
    tileInFlight.set(url, pending)
    pending.finally(() => tileInFlight.delete(url)).catch(() => {})
  }
  return pending
}

// Recolors DPC radar tiles client-side before MapLibre uploads them as
// raster textures. The color mapping reproduces the official DPC viewer
// (https://radar.protezionecivile.it/); see the provenance notes at the
// top of assets/js/radar_palettes.js for details and license.
addProtocol(RADAR_PROTOCOL, async (params) => ({data: await fetchColorizedTile(params.url)}))

function withKey(url) {
  const key = cartoKey()
  return key ? `${url}?key=${encodeURIComponent(key)}` : url
}

function currentStyleUrl() {
  const theme = document.documentElement.getAttribute("data-theme")
  if (theme === "dark") return withKey(STYLES.dark)
  if (theme === "light") return withKey(STYLES.light)
  // "system" or no attribute — fall back to OS preference
  return window.matchMedia("(prefers-color-scheme: dark)").matches
    ? withKey(STYLES.dark)
    : withKey(STYLES.light)
}

function extendBounds(bounds, lng, lat) {
  if (!bounds) return {west: lng, south: lat, east: lng, north: lat}

  return {
    west: Math.min(bounds.west, lng),
    south: Math.min(bounds.south, lat),
    east: Math.max(bounds.east, lng),
    north: Math.max(bounds.north, lat),
  }
}

function boundsToArray(bounds) {
  return [
    [bounds.west, bounds.south],
    [bounds.east, bounds.north],
  ]
}

const MaplibreMap = {
  mounted() {
    this.map = new MapLib({
      container: this.el,
      style: currentStyleUrl(),
      center: [10, 48],
      zoom: 5,
      maxZoom: 19,
      maxPitch: 0,
      attributionControl: {compact: true, customAttribution: ATTRIBUTION},
    })

    // Leaflet shipped a zoom control in the top-left corner by default.
    this.map.addControl(new NavigationControl({showCompass: false}), "top-left")
    // Leaflet has no bearing rotation — keep the interaction model identical.
    this.map.dragRotate.disable()

    this.markers = new Map()
    this._boundsSet = false
    this._markerBounds = null

    this.handleEvent("update_markers", ({markers}) => {
      this.updateMarkers(markers)
    })

    this._radar = {enabled: false, product: null, opacity: 0.85, time: null}

    this.handleEvent("radar_state", ({enabled, product, opacity}) => {
      const prevProduct = this._radar.product
      this._radar.enabled = !!enabled
      if (product) this._radar.product = product
      const parsed = parseFloat(opacity)
      if (Number.isFinite(parsed)) this._radar.opacity = parsed

      if (this._radar.enabled) {
        if (!this.map.getLayer(RADAR_LAYER_ID)) {
          this.addRadarLayer()
        } else {
          this.map.setPaintProperty(RADAR_LAYER_ID, "raster-opacity", this._radar.opacity)
          if (prevProduct !== this._radar.product && this._radar.time != null) {
            this.updateRadarTiles()
          }
        }
      } else if (this.map.getLayer(RADAR_LAYER_ID) || this.map.getSource(RADAR_SOURCE_ID)) {
        this.removeRadar()
      }
    })

    this._offRadarFrame = onFrame(({time}) => this.applyRadarFrame(time))
    window.__maplibreDebug = this

    this._updateStyle = () => {
      this.map.setStyle(currentStyleUrl())
      this.map.once("style.load", () => this.addRadarLayer())
    }
    this._mediaQuery = window.matchMedia("(prefers-color-scheme: dark)")
    this._onStorage = (e) => {
      if (e.key === "phx:theme") this._updateStyle()
    }

    window.addEventListener("phx:set-theme", this._updateStyle)
    window.addEventListener("storage", this._onStorage)
    this._mediaQuery.addEventListener("change", this._updateStyle)
  },

  updateMarkers(markerList) {
    const seenIds = new Set(markerList.map((m) => m.id))

    this.markers.forEach((marker, id) => {
      if (!seenIds.has(id)) {
        marker.remove()
        this.markers.delete(id)
      }
    })

    let bounds = null

    markerList.forEach((data) => {
      if (this.markers.has(data.id)) {
        const existing = this.markers.get(data.id)
        existing.getElement().innerHTML = this.buildHtml(data)
      } else {
        // Zero-size anchor element: MapLibre pins it exactly on the
        // coordinate while .map-marker keeps its own CSS transform offset,
        // matching the previous Leaflet iconAnchor/iconSize setup.
        const el = document.createElement("div")
        el.style.width = "0"
        el.style.height = "0"
        el.innerHTML = this.buildHtml(data)
        el.tabIndex = 0
        el.addEventListener("click", () => {
          window.location.href = `/installations/${data.id}`
        })
        el.addEventListener("keydown", (e) => {
          if (e.key === "Enter") {
            e.stopPropagation()
            window.location.href = `/installations/${data.id}`
          }
        })

        const marker = new Marker({element: el})
          .setLngLat([data.lng, data.lat])
          .addTo(this.map)
        this.markers.set(data.id, marker)
      }

      bounds = extendBounds(bounds, data.lng, data.lat)
    })

    this._markerBounds = bounds

    if (!this._boundsSet && this.markers.size > 0) {
      this._boundsSet = true
      this.fitToMarkers()
    }
  },

  fitToMarkers() {
    const camera = this.cameraForMarkers()

    if (!camera) return

    this.map.easeTo(camera)
  },

  cameraForMarkers() {
    if (!this._markerBounds) return null

    return this.map.cameraForBounds(boundsToArray(this._markerBounds), {
      padding: this.fitPadding(),
    })
  },

  fitPadding() {
    const rect = this.map.getContainer().getBoundingClientRect()

    return Math.max(
      FIT_PADDING_MIN,
      Math.round(Math.min(rect.width, rect.height) * FIT_PADDING_RATIO)
    )
  },

  buildHtml(data) {
    const webcamIcon = data.has_webcam
      ? `<span class="map-marker-webcam" title="Webcam">` +
        `<svg width="10" height="10" viewBox="0 0 24 24" fill="currentColor">` +
        `<path d="M17 10.5V7a1 1 0 00-1-1H4a1 1 0 00-1 1v10a1 1 0 001 1h12a1 1 0 001-1v-3.5l4 4v-11l-4 4z"/>` +
        `</svg></span>`
      : ""

    const faultIcon = data.has_fault
      ? `<span class="map-marker-fault" title="Active fault">` +
        `<svg width="10" height="10" viewBox="0 0 24 24" fill="currentColor">` +
        `<path d="M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z"/>` +
        `</svg></span>`
      : ""

    const valueAt = data.value_at
      ? `<span class="map-marker-at">${new Date(data.value_at).toLocaleTimeString(undefined, {hour: "2-digit", minute: "2-digit", hour12: false})}</span>`
      : ""

    return `<div class="map-marker">${esc(data.value)}${valueAt}${webcamIcon}${faultIcon}</div>`
  },

  radarBeforeLayerId() {
    const layers = this.map.getStyle().layers
    for (const layer of layers) {
      if (layer.type === "symbol") return layer.id
    }
    return undefined
  },

  addRadarLayer() {
    if (!this._radar.enabled || this._radar.product == null || this._radar.time == null) return
    if (!this.map.getSource(RADAR_SOURCE_ID)) {
      this.map.addSource(RADAR_SOURCE_ID, {
        type: "raster",
        tiles: [tileUrl(this._radar.product, this._radar.time)],
        tileSize: 256,
        minzoom: 0,
        maxzoom: RADAR_MAX_ZOOM,
        attribution: RADAR_ATTRIBUTION,
      })
    }
    if (!this.map.getLayer(RADAR_LAYER_ID)) {
      this.map.addLayer(
        {
          id: RADAR_LAYER_ID,
          type: "raster",
          source: RADAR_SOURCE_ID,
          paint: {
            "raster-opacity": this._radar.opacity,
            "raster-fade-duration": 0,
            "raster-resampling": "linear",
          },
        },
        this.radarBeforeLayerId()
      )
    }
  },

  removeRadar() {
    if (this.map.getLayer(RADAR_LAYER_ID)) this.map.removeLayer(RADAR_LAYER_ID)
    if (this.map.getSource(RADAR_SOURCE_ID)) this.map.removeSource(RADAR_SOURCE_ID)
  },

  updateRadarTiles() {
    const source = this.map.getSource(RADAR_SOURCE_ID)
    if (!source) return
    const url = tileUrl(this._radar.product, this._radar.time)
    if (typeof source.setTiles === "function") {
      source.setTiles([url])
    } else {
      this.removeRadar()
      this.addRadarLayer()
    }
  },

  applyRadarFrame(time) {
    if (time == null) return
    this._radar.time = time
    if (!this._radar.enabled) return
    if (!this.map.getLayer(RADAR_LAYER_ID)) {
      this.addRadarLayer()
      return
    }
    this.updateRadarTiles()
  },

  destroyed() {
    if (this.map) {
      this.map.remove()
      this.map = null
    }
    if (this._offRadarFrame) this._offRadarFrame()
    window.removeEventListener("phx:set-theme", this._updateStyle)
    window.removeEventListener("storage", this._onStorage)
    if (this._mediaQuery) {
      this._mediaQuery.removeEventListener("change", this._updateStyle)
    }
  },
}

function esc(s) {
  if (!s) return "\u2014"
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
}

export default MaplibreMap
