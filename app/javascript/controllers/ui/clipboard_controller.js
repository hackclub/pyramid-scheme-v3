import { Controller } from "@hotwired/stimulus"

// Usage:
// <button data-controller="ui--clipboard"
//         data-ui--clipboard-text-value="..."
//         data-action="click->ui--clipboard#copy">
//   <span data-ui--clipboard-target="label">Copy</span>
// </button>
//
export default class extends Controller {
  static values = { text: String }
  static targets = ["label"]

  async copy() {
    const text = this.textValue || ""
    const originalText = this.hasLabelTarget ? this.labelTarget.textContent : null

    try {
      await navigator.clipboard.writeText(text)
      this.showSuccess(originalText)
    } catch (_e) {
      // Fallback for older/locked-down contexts
      const ta = document.createElement("textarea")
      ta.value = text
      ta.style.position = "fixed"
      ta.style.left = "-9999px"
      document.body.appendChild(ta)
      ta.select()
      try {
        document.execCommand("copy")
        this.showSuccess(originalText)
      } finally {
        document.body.removeChild(ta)
      }
    }
  }

  showSuccess(originalText) {
    this.element.dataset.copied = "true"
    if (this.hasLabelTarget) {
      this.labelTarget.textContent = "Copied!"
    }
    window.setTimeout(() => {
      delete this.element.dataset.copied
      if (this.hasLabelTarget && originalText) {
        this.labelTarget.textContent = originalText
      }
    }, 1200)
  }
}
