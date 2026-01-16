import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggleable", "checkbox"]
  static values = { initial: Boolean }

  connect() {
    this.toggle()
  }

  toggle() {
    const isChecked = this.checkboxTarget.checked
    this.toggleableTargets.forEach(el => {
      el.disabled = !isChecked
    })
  }
}
