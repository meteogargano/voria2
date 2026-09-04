import maplibregl from "maplibre-gl"

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

// Zoom floor: just below the zoom level that fits all markers, so the
// whole network always stays in view when fully zoomed out.
const MIN_ZOOM_MARGIN = 0.5
const MIN_ZOOM_CAP = 12

// Bounds tolerance below which every marker shares (almost) the same spot
// and there is no meaningful "fit all markers" zoom.
const DEGENERATE_EPSILON = 1e-4

function cartoKey() {
  return document.querySelector('meta[name="carto-basemaps-api-key"]')?.content || ""
}

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

function boundsDegenerate(bounds) {
  return (
    bounds.east - bounds.west < DEGENERATE_EPSILON &&
    bounds.north - bounds.south < DEGENERATE_EPSILON
  )
}

const MaplibreMap = {
  mounted() {
    this.map = new maplibregl.Map({
      container: this.el,
      style: currentStyleUrl(),
      center: [10, 48],
      zoom: 5,
      maxZoom: 19,
      maxPitch: 0,
      attributionControl: {compact: true, customAttribution: ATTRIBUTION},
    })

    // Leaflet shipped a zoom control in the top-left corner by default.
    this.map.addControl(new maplibregl.NavigationControl({showCompass: false}), "top-left")
    // Leaflet has no bearing rotation — keep the interaction model identical.
    this.map.dragRotate.disable()

    this.markers = new Map()
    this._boundsSet = false
    this._markerBounds = null
    this._minZoomKey = null

    this.handleEvent("update_markers", ({markers}) => {
      this.updateMarkers(markers)
    })

    this._updateStyle = () => this.map.setStyle(currentStyleUrl())
    this._mediaQuery = window.matchMedia("(prefers-color-scheme: dark)")
    this._onStorage = (e) => {
      if (e.key === "phx:theme") this._updateStyle()
    }
    this._onResize = () => this.updateMinZoom()

    window.addEventListener("phx:set-theme", this._updateStyle)
    window.addEventListener("storage", this._onStorage)
    this._mediaQuery.addEventListener("change", this._updateStyle)
    this.map.on("resize", this._onResize)
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

        const marker = new maplibregl.Marker({element: el})
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
    } else {
      this.updateMinZoom()
    }
  },

  fitToMarkers() {
    const camera = this.cameraForMarkers()

    if (!camera) {
      this.updateMinZoom()
      return
    }

    this.map.easeTo(camera)
    // Apply the zoom floor once the intro animation lands, otherwise
    // setMinZoom would clamp the camera mid-flight.
    this.map.once("moveend", () => this.updateMinZoom())
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

  updateMinZoom() {
    if (!this._markerBounds || boundsDegenerate(this._markerBounds)) return

    const b = this._markerBounds
    const rect = this.map.getContainer().getBoundingClientRect()
    const key = [
      Math.round(rect.width),
      Math.round(rect.height),
      b.west.toFixed(4),
      b.south.toFixed(4),
      b.east.toFixed(4),
      b.north.toFixed(4),
    ].join("|")

    if (key === this._minZoomKey) return
    this._minZoomKey = key

    const camera = this.cameraForMarkers()

    if (!camera || !Number.isFinite(camera.zoom)) {
      // Container not measurable yet — retry on the next update/resize.
      this._minZoomKey = null
      return
    }

    this.map.setMinZoom(Math.max(0, Math.min(camera.zoom - MIN_ZOOM_MARGIN, MIN_ZOOM_CAP)))
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

  destroyed() {
    if (this.map) {
      this.map.remove()
      this.map = null
    }
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
