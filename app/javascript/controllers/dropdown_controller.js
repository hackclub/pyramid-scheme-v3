import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]

  connect() {
    this.boundClickOutside = this.clickOutside.bind(this)
  }

  toggle(e) {
    e.preventDefault()
    e.stopPropagation()
    if (this.menuTarget.classList.contains("hidden")) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    this.menuTarget.classList.remove("hidden")
    // Use setTimeout to prevent immediate close from bubbling click
    setTimeout(() => {
      document.addEventListener("click", this.boundClickOutside)
    }, 0)
  }

  close() {
    this.menuTarget.classList.add("hidden")
    document.removeEventListener("click", this.boundClickOutside)
  }

  clickOutside(e) {
    if (!this.element.contains(e.target)) {
      this.close()
    }
  }

  disconnect() {
    document.removeEventListener("click", this.boundClickOutside)
  }
}
