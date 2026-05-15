import "../../vendor/leaflet"
const L = window.L

const TILES = {
  light: "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png",
  dark: "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png",
}

const ATTRIBUTION =
  '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>'

function currentTileUrl() {
  const theme = document.documentElement.getAttribute("data-theme")
  if (theme === "dark") return TILES.dark
  if (theme === "light") return TILES.light
  // "system" or no attribute — fall back to OS preference
  return window.matchMedia("(prefers-color-scheme: dark)").matches
    ? TILES.dark
    : TILES.light
}

const LeafletMap = {
  mounted() {
    this.leafletMap = L.map(this.el).setView([48, 10], 5)

    this.tileLayer = L.tileLayer(currentTileUrl(), {
      attribution: ATTRIBUTION,
      subdomains: "abcd",
      maxZoom: 19,
    }).addTo(this.leafletMap)

    this.markers = new Map()
    this._boundsSet = false

    this.handleEvent("update_markers", ({ markers }) => {
      this.updateMarkers(markers)
    })

    this._updateTiles = () => this.tileLayer.setUrl(currentTileUrl())
    this._mediaQuery = window.matchMedia("(prefers-color-scheme: dark)")
    this._onStorage = (e) => {
      if (e.key === "phx:theme") this._updateTiles()
    }

    window.addEventListener("phx:set-theme", this._updateTiles)
    window.addEventListener("storage", this._onStorage)
    this._mediaQuery.addEventListener("change", this._updateTiles)
  },

  updateMarkers(markerList) {
    const seenIds = new Set(markerList.map((m) => m.id))

    this.markers.forEach((marker, id) => {
      if (!seenIds.has(id)) {
        marker.remove()
        this.markers.delete(id)
      }
    })

    markerList.forEach((data) => {
      const icon = L.divIcon({
        html: this.buildHtml(data),
        className: "",
        iconSize: [0, 0],
        iconAnchor: [0, 0],
      })

      if (this.markers.has(data.id)) {
        const existing = this.markers.get(data.id)
        existing.setIcon(icon)
      } else {
        const marker = L.marker([data.lat, data.lng], { icon }).addTo(
          this.leafletMap
        )
        marker.on("click", () => {
          window.location.href = `/installations/${data.id}`
        })
        this.markers.set(data.id, marker)
      }
    })

    if (!this._boundsSet && this.markers.size > 0) {
      const group = L.featureGroup([...this.markers.values()])
      this.leafletMap.fitBounds(group.getBounds().pad(0.25))
      this._boundsSet = true
    }
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
    if (this.leafletMap) {
      this.leafletMap.remove()
      this.leafletMap = null
    }
    window.removeEventListener("phx:set-theme", this._updateTiles)
    window.removeEventListener("storage", this._onStorage)
    if (this._mediaQuery) {
      this._mediaQuery.removeEventListener("change", this._updateTiles)
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

export default LeafletMap
