import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog"]

  connect() {
    console.log("Video submission modal controller connected")
    // Add escape key listener
    this.escapeHandler = this.closeOnEscape.bind(this)
    document.addEventListener("keydown", this.escapeHandler)
  }

  disconnect() {
    document.removeEventListener("keydown", this.escapeHandler)
  }

  open(e) {
    console.log("Video submission modal open called", e)
    e.preventDefault()
    const button = e.currentTarget
    console.log("Button element:", button)
    const submissionId = button.dataset.videoSubmissionId
    console.log("Submission ID:", submissionId)
    const dialog = this.element.querySelector(`[data-video-submission-modal-target="dialog"][data-video-submission-id="${submissionId}"]`)
    console.log("Dialog found:", dialog)
    
    if (dialog) {
      console.log("Opening modal")
      // Prevent body and html scroll
      this.scrollY = window.scrollY
      document.documentElement.style.overflow = 'hidden'
      document.body.style.overflow = 'hidden'
      document.body.style.position = 'fixed'
      document.body.style.top = `-${this.scrollY}px`
      document.body.style.width = '100%'
      document.body.style.left = '0'
      document.body.style.right = '0'
      
      dialog.classList.remove("hidden")
      dialog.dataset.state = "open"
    } else {
      console.log("Modal not found")
    }
  }

  close(e) {
    if (e) e.preventDefault()
    const dialogs = this.element.querySelectorAll('[data-video-submission-modal-target="dialog"]')
    dialogs.forEach(dialog => {
      dialog.classList.add("hidden")
      dialog.dataset.state = "closed"
    })
    // Restore body and html scroll
    document.documentElement.style.overflow = ''
    document.body.style.overflow = ''
    document.body.style.position = ''
    document.body.style.top = ''
    document.body.style.width = ''
    document.body.style.left = ''
    document.body.style.right = ''
    window.scrollTo(0, this.scrollY)
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
}