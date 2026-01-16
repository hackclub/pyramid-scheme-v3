import { Controller } from "@hotwired/stimulus"

// Dismissable "New!" badge controller
// Stores dismissed state in localStorage
export default class extends Controller {
  static values = {
    key: String // localStorage key for this badge
  }

  connect() {
    // Check localStorage before rendering to prevent flash
    if (this.isDismissed()) {
      this.element.style.display = "none"
    } else {
      this.element.style.display = "inline-flex"
    }
  }

  dismiss(event) {
    event.preventDefault()
    event.stopPropagation()
    localStorage.setItem(this.storageKey, "true")
    this.element.style.display = "none"
  }

  isDismissed() {
    return localStorage.getItem(this.storageKey) === "true"
  }

  get storageKey() {
    return `new_badge_dismissed_${this.keyValue}`
  }
}
