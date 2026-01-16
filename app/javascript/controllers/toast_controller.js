import { Controller } from "@hotwired/stimulus"

// Toast notification controller - shows notifications in the corner
export default class extends Controller {
  static values = {
    duration: { type: Number, default: 5000 }
  }

  connect() {
    // Auto-dismiss after duration
    if (this.durationValue > 0) {
      this.timeout = setTimeout(() => {
        this.dismiss()
      }, this.durationValue)
    }
    
    // Animate in
    requestAnimationFrame(() => {
      this.element.classList.remove("translate-x-full", "opacity-0")
      this.element.classList.add("translate-x-0", "opacity-100")
    })
  }

  disconnect() {
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
  }

  dismiss() {
    this.element.classList.remove("translate-x-0", "opacity-100")
    this.element.classList.add("translate-x-full", "opacity-0")
    
    setTimeout(() => {
      this.element.remove()
    }, 300)
  }
}
