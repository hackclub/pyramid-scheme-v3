import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "submitBtn", "submitText", "spinner"]

  connect() {
    console.log("PosterSubmit controller connected")
  }

  disableForm() {
    console.log("Disabling form...")
    // Disable all input fields
    this.inputTargets.forEach(input => {
      input.disabled = true
    })
    
    // Disable submit button
    if (this.hasSubmitBtnTarget) {
      this.submitBtnTarget.disabled = true
    }
    
    // Hide submit text and show spinner
    if (this.hasSubmitTextTarget) {
      this.submitTextTarget.classList.add("hidden")
    }
    if (this.hasSpinnerTarget) {
      this.spinnerTarget.classList.remove("hidden")
    }
  }

  enableForm() {
    console.log("Enabling form...")
    // Re-enable all input fields
    this.inputTargets.forEach(input => {
      input.disabled = false
    })
    
    // Re-enable submit button
    if (this.hasSubmitBtnTarget) {
      this.submitBtnTarget.disabled = false
    }
    
    // Show submit text and hide spinner
    if (this.hasSubmitTextTarget) {
      this.submitTextTarget.classList.remove("hidden")
    }
    if (this.hasSpinnerTarget) {
      this.spinnerTarget.classList.add("hidden")
    }
  }
}
