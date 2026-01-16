import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "form", "submitButton", "submitText", "loadingText", "cancelButton", "countField", "nameFieldContainer"]

  toggleNameField() {
    if (this.hasNameFieldContainerTarget && this.hasCountFieldTarget) {
      const count = parseInt(this.countFieldTarget.value) || 1
      if (count === 1) {
        this.nameFieldContainerTarget.classList.add("hidden")
      } else {
        this.nameFieldContainerTarget.classList.remove("hidden")
      }
    }
  }

  open(e) {
    e.preventDefault()
    this.dialogTarget.classList.remove("hidden")
    this.dialogTarget.dataset.state = "open"
    document.body.classList.add("overflow-hidden")
    this.toggleNameField()
  }

  close(e) {
    if (e) e.preventDefault()
    this.dialogTarget.classList.add("hidden")
    this.dialogTarget.dataset.state = "closed"
    document.body.classList.remove("overflow-hidden")

    // Reload page if poster was successfully created (form is hidden)
    const form = this.element.querySelector('[data-poster-modal-target="form"]')
    if (form && form.style.display === 'none') {
      window.location.reload()
    }
  }

  closeOnBackdrop(e) {
    if (e.target === e.currentTarget) {
      this.close(e)
    }
  }

  closeOnEscape(e) {
    if (e.key === "Escape") {
      this.close(e)
    }
  }

  startSubmit() {
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = true
    }
    if (this.hasSubmitTextTarget && this.hasLoadingTextTarget) {
      this.submitTextTarget.classList.add("hidden")
      this.loadingTextTarget.classList.remove("hidden")
    }
    if (this.hasCancelButtonTarget) {
      this.cancelButtonTarget.disabled = true
    }
  }

  endSubmit() {
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = false
    }
    if (this.hasSubmitTextTarget && this.hasLoadingTextTarget) {
      this.submitTextTarget.classList.remove("hidden")
      this.loadingTextTarget.classList.add("hidden")
    }
    if (this.hasCancelButtonTarget) {
      this.cancelButtonTarget.disabled = false
    }
  }

  toggleNameField() {
    if (this.hasNameFieldContainerTarget && this.hasCountFieldTarget) {
      const count = parseInt(this.countFieldTarget.value) || 1
      if (count === 1) {
        this.nameFieldContainerTarget.classList.add("hidden")
      } else {
        this.nameFieldContainerTarget.classList.remove("hidden")
      }
    }
  }

  connect() {
    document.addEventListener("keydown", this.closeOnEscape.bind(this))
  }

  disconnect() {
    document.removeEventListener("keydown", this.closeOnEscape.bind(this))
  }
}
