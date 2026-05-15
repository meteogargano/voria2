import flatpickr from "flatpickr"
import { Italian } from "flatpickr/dist/l10n/it.js"

const DISPLAY_FORMATS = {
  date: "d/m/Y",
  datetime: "d/m/Y H:i",
}

const CANONICAL_FORMATS = {
  date_iso: "Y-m-d",
  datetime_local: "Y-m-d\\TH:i",
}

function validDate(date) {
  return date instanceof Date && !Number.isNaN(date.getTime())
}

function sameDate(a, b) {
  return validDate(a) && validDate(b) && a.getTime() === b.getTime()
}

function parseCanonical(instance, submitMode, value) {
  if (!value) return null

  if (submitMode === "utc_iso") {
    const parsed = new Date(value)
    return validDate(parsed) ? parsed : null
  }

  const format = CANONICAL_FORMATS[submitMode]

  if (!format) return null

  const parsed = flatpickr.parseDate(value, format)
  return validDate(parsed) ? parsed : null
}

function parseDisplay(instance, picker, value) {
  if (!value) return null

  const format = DISPLAY_FORMATS[picker]
  const parsed = flatpickr.parseDate(value, format)

  if (!validDate(parsed)) return null

  return instance.formatDate(parsed, format) === value ? parsed : null
}

function formatCanonical(instance, submitMode, date) {
  if (!validDate(date)) return ""

  if (submitMode === "utc_iso") {
    return date.toISOString()
  }

  const format = CANONICAL_FORMATS[submitMode]
  return format ? instance.formatDate(date, format) : ""
}

const FlatpickrInput = {
  mounted() {
    this.root = this.el
    this.input = this.root.querySelector("[data-role='flatpickr-visible-input']")
    this.hiddenInput = this.root.querySelector("[data-role='flatpickr-hidden-input']")

    if (!this.input || !this.hiddenInput) {
      return
    }

    this.picker = this.root.dataset.picker
    this.submitMode = this.root.dataset.submitMode
    this.pushEventName = this.root.dataset.pushEvent || ""
    this.form = this.input.form

    this.setHiddenValue = (value, {notify = true, push = false} = {}) => {
      const nextValue = value || ""
      const changed = this.hiddenInput.value !== nextValue

      this.hiddenInput.value = nextValue

      if (notify && changed) {
        this.hiddenInput.dispatchEvent(new Event("input", {bubbles: true}))
        this.hiddenInput.dispatchEvent(new Event("change", {bubbles: true}))
      }

      if (push && this.pushEventName && this.hiddenInput.name) {
        this.pushEvent(this.pushEventName, {[this.hiddenInput.name]: this.hiddenInput.value})
      }
    }

    this.syncFromSelectedDates = () => {
      const selected = this.instance.selectedDates[0]
      this.setHiddenValue(formatCanonical(this.instance, this.submitMode, selected), {
        notify: true,
        push: true,
      })
    }

    this.syncFromInput = () => {
      const raw = this.input.value.trim()

      if (raw === "") {
        this.instance.clear()
        this.setHiddenValue("", {notify: true, push: true})
        return
      }

      const parsed = parseDisplay(this.instance, this.picker, raw)

      if (!parsed) {
        this.instance.clear()
        this.input.value = raw
        this.setHiddenValue("", {notify: true, push: true})
        return
      }

      if (!sameDate(this.instance.selectedDates[0], parsed)) {
        this.instance.setDate(parsed, false, DISPLAY_FORMATS[this.picker])
      }

      this.input.value = this.instance.formatDate(parsed, DISPLAY_FORMATS[this.picker])
      this.setHiddenValue(formatCanonical(this.instance, this.submitMode, parsed), {
        notify: true,
        push: true,
      })
    }

    this.instance = flatpickr(this.input, {
      allowInput: true,
      allowInvalidPreload: true,
      clickOpens: true,
      dateFormat: DISPLAY_FORMATS[this.picker],
      disableMobile: this.root.dataset.forceCustomMobile !== "false",
      enableTime: this.picker === "datetime",
      locale: Italian,
      minuteIncrement: Number.parseInt(this.root.dataset.minuteIncrement || "5", 10),
      position: this.root.dataset.position || "auto left",
      time_24hr: this.picker === "datetime",
      onValueUpdate: this.syncFromSelectedDates,
      onChange: this.syncFromSelectedDates,
      onClose: this.syncFromInput,
    })

    this.boundInput = this.syncFromInput
    this.boundSubmit = this.syncFromInput

    this.input.addEventListener("input", this.boundInput)

    if (this.form) {
      this.form.addEventListener("submit", this.boundSubmit)
    }

    this.applyServerState()
  },

  updated() {
    if (!this.instance) return
    this.applyServerState()
  },

  destroyed() {
    if (this.input && this.boundInput) {
      this.input.removeEventListener("input", this.boundInput)
    }

    if (this.form && this.boundSubmit) {
      this.form.removeEventListener("submit", this.boundSubmit)
    }

    if (this.instance) {
      this.instance.destroy()
    }
  },

  applyServerState() {
    const displayValue = this.input.dataset.serverValue || ""
    const hiddenValue = this.hiddenInput.dataset.serverValue || ""
    const selected = parseCanonical(this.instance, this.submitMode, hiddenValue)

    if (selected) {
      if (!sameDate(this.instance.selectedDates[0], selected)) {
        this.instance.setDate(selected, false)
      }

      // Always derive the visible value from the canonical datetime so a
      // server round-trip can't leave the input showing UTC text.
      this.input.value = this.instance.formatDate(selected, DISPLAY_FORMATS[this.picker])

      this.setHiddenValue(hiddenValue, {notify: false, push: false})
      return
    }

    this.instance.clear(false)
    this.input.value = displayValue
    this.setHiddenValue(hiddenValue, {notify: false, push: false})
  },
}

export default FlatpickrInput
