const InputBlur = {
  mounted() {
    this.el.addEventListener("blur", e => {
      const name = this.el.name
      const value = this.el.value
      this.pushEvent("update_edit_form", {[name]: value})
    })
  }
}

export default InputBlur
