const INPUT_DEBOUNCE_MS = 250

const HugeRteInput = {
  async mounted() {
    this.sourceInputId = this.el.dataset.inputId
    this.sourceInput = document.getElementById(this.sourceInputId)
    this.editorInputId = this.el.dataset.editorId
    this.editorInput = document.getElementById(this.editorInputId)

    if (!this.sourceInput || !this.editorInput) {
      return
    }

    this.pendingSync = null
    this.form = this.sourceInput.form

    this.syncSource = (value, {notify = true} = {}) => {
      const nextValue = value || ""
      const changed = this.sourceInput.value !== nextValue

      this.sourceInput.value = nextValue

      if (notify && changed) {
        this.sourceInput.dispatchEvent(new Event("input", {bubbles: true}))
      }
    }

    this.scheduleSync = () => {
      window.clearTimeout(this.pendingSync)
      this.pendingSync = window.setTimeout(() => {
        this.pendingSync = null
        this.flushSync()
      }, INPUT_DEBOUNCE_MS)
    }

    this.flushSync = ({notify = true} = {}) => {
      if (!this.editor) return
      this.syncSource(this.editor.getContent(), {notify})
    }

    this.initialValue = this.sourceInput.value || ""

    this.beforeSubmit = () => this.flushSync({notify: false})
    this.form?.addEventListener("submit", this.beforeSubmit)

    await this.initEditor()
  },

  destroyed() {
    window.clearTimeout(this.pendingSync)
    this.form?.removeEventListener("submit", this.beforeSubmit)

    if (this.editor) {
      this.editor.remove()
      this.editor = null
    }
  },

  async initEditor() {
    const {loadHugeRte} = await import("../vendor/hugerte_bundle")
    const hugerte = await loadHugeRte()

    const editors = await hugerte.init({
      target: this.editorInput,
      branding: false,
      menubar: "edit insert view format table tools help",
      height: 720,
      plugins: [
        "advlist",
        "autolink",
        "code",
        "fullscreen",
        "help",
        "image",
        "link",
        "lists",
        "media",
        "preview",
        "searchreplace",
        "table",
        "visualblocks",
        "wordcount",
      ],
      toolbar:
        "undo redo | blocks | bold italic underline | forecolor backcolor | bullist numlist outdent indent | alignleft aligncenter alignright | link image media table | removeformat code preview fullscreen",
      skin_url: "default",
      content_css: "default",
      resize: true,
      convert_urls: false,
      relative_urls: false,
      promotion: false,
      setup: editor => {
        editor.on("init", () => {
          editor.setContent(this.initialValue)
          this.syncSource(editor.getContent(), {notify: false})
        })

        editor.on("input", this.scheduleSync)
        editor.on("change undo redo", () => this.flushSync())
        editor.on("blur", () => this.flushSync())
      },
    })

    this.editor = Array.isArray(editors) ? editors[0] : editors
  },
}

export default HugeRteInput
