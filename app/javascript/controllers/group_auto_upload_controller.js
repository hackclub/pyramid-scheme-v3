import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "fileInput", "submitBtn", "submitText", "inputsContainer"]

  submit(event) {
    // Show loading state
    if (this.hasSubmitBtnTarget) {
      this.submitBtnTarget.disabled = true
      if (this.hasSubmitTextTarget) {
        this.submitTextTarget.textContent = "Uploading..."
      }
    }
  }

  // Called after turbo-frame loads content
  checkForError() {
    const errorMessage = this.element.querySelector('[data-group-auto-upload-target="errorMessage"]')
    
    // Find the inputs container and tip box within the form
    const form = this.element.querySelector('[data-group-auto-upload-target="form"]')
    if (!form) return
    
    const inputsContainer = form.querySelector('[data-group-auto-upload-target="inputsContainer"]')
    const tipBox = form.parentElement.querySelector('.flex.items-start.gap-2.p-3.rounded-lg')
    
    if (errorMessage) {
      // Hide inputs and tip when error is shown
      if (inputsContainer) inputsContainer.style.display = 'none'
      if (tipBox) tipBox.style.display = 'none'
    } else {
      // Show inputs and tip when no error
      if (inputsContainer) inputsContainer.style.display = ''
      if (tipBox) tipBox.style.display = ''
    }
  }

  // Reset form after successful submission
  resetForm() {
    if (this.hasFormTarget) {
      this.formTarget.reset()
    }
    if (this.hasSubmitBtnTarget) {
      this.submitBtnTarget.disabled = false
      if (this.hasSubmitTextTarget) {
        this.submitTextTarget.textContent = "Upload & Auto-Match"
      }
    }
    this.checkForError()
  }
}
