import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "form", "submitButton", "submitText", "loadingText", "cancelButton"]

  open(e) {
    e.preventDefault()
    this.dialogTarget.classList.remove("hidden")
    this.dialogTarget.dataset.state = "open"
    document.body.classList.add("overflow-hidden")
  }

  close(e) {
    if (e) e.preventDefault()
    this.dialogTarget.classList.add("hidden")
    this.dialogTarget.dataset.state = "closed"
    document.body.classList.remove("overflow-hidden")

    // Reload page if bulk posters were successfully created
    const form = this.element.querySelector('[data-bulk-poster-modal-target="form"]')
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
    // Disable submit button and show loading state
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = true
      this.submitButtonTarget.classList.add("opacity-60", "cursor-not-allowed")
    }

    // Hide submit text, show loading text
    if (this.hasSubmitTextTarget && this.hasLoadingTextTarget) {
      this.submitTextTarget.classList.add("hidden")
      this.loadingTextTarget.classList.remove("hidden")
    }

    // Disable cancel button during submission
    if (this.hasCancelButtonTarget) {
      this.cancelButtonTarget.disabled = true
      this.cancelButtonTarget.classList.add("opacity-50", "cursor-not-allowed")
    }
  }

  endSubmit() {
    // Re-enable submit button and hide loading state
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = false
      this.submitButtonTarget.classList.remove("opacity-60", "cursor-not-allowed")
    }

    // Show submit text, hide loading text
    if (this.hasSubmitTextTarget && this.hasLoadingTextTarget) {
      this.submitTextTarget.classList.remove("hidden")
      this.loadingTextTarget.classList.add("hidden")
    }

    // Re-enable cancel button
    if (this.hasCancelButtonTarget) {
      this.cancelButtonTarget.disabled = false
      this.cancelButtonTarget.classList.remove("opacity-50", "cursor-not-allowed")
    }
  }

  connect() {
    document.addEventListener("keydown", this.closeOnEscape.bind(this))
  }

  disconnect() {
    document.removeEventListener("keydown", this.closeOnEscape.bind(this))
  }
}
