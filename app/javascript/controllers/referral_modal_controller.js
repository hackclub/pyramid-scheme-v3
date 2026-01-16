import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "copyLabel"]

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

  copy(e) {
    e.preventDefault()
    const link = e.currentTarget.dataset.referralLink

    navigator.clipboard.writeText(link).then(() => {
      // Show success feedback
      if (this.hasCopyLabelTarget) {
        const originalText = this.copyLabelTarget.textContent
        this.copyLabelTarget.textContent = "Copied!"

        setTimeout(() => {
          this.copyLabelTarget.textContent = originalText
        }, 2000)
      }
    }).catch(err => {
      console.error('Failed to copy:', err)
      alert('Failed to copy link. Please copy it manually from the box above.')
    })
  }

  connect() {
    document.addEventListener("keydown", this.closeOnEscape.bind(this))
  }

  disconnect() {
    document.removeEventListener("keydown", this.closeOnEscape.bind(this))
  }
}
