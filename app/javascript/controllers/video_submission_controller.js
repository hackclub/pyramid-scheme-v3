import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "urlInput", "fileInput", "filePreview", "fileError", "submitButton", "uploadProgress"]

  connect() {
    this.element.addEventListener("turbo:submit-start", this.handleSubmitStart.bind(this))
    this.element.addEventListener("turbo:submit-end", this.handleSubmitEnd.bind(this))
  }

  disconnect() {
    this.element.removeEventListener("turbo:submit-start", this.handleSubmitStart.bind(this))
    this.element.removeEventListener("turbo:submit-end", this.handleSubmitEnd.bind(this))
  }

  validateFiles() {
    const files = Array.from(this.fileInputTarget.files)

    this.filePreviewTarget.classList.add("hidden")
    this.fileErrorTarget.classList.add("hidden")

    if (files.length === 0) return

    if (files.length > 5) {
      this.fileErrorTarget.textContent = "Maximum 5 files allowed"
      this.fileErrorTarget.classList.remove("hidden")
      this.fileInputTarget.value = ""
      return
    }

    const totalSize = files.reduce((sum, file) => sum + file.size, 0)
    const maxSize = 200 * 1024 * 1024

    if (totalSize > maxSize) {
      this.fileErrorTarget.textContent = `Total size (${this.formatSize(totalSize)}) exceeds 200MB limit`
      this.fileErrorTarget.classList.remove("hidden")
      this.fileInputTarget.value = ""
      return
    }

    const fileNames = files.map(f => `${f.name} (${this.formatSize(f.size)})`).join(", ")
    this.filePreviewTarget.textContent = `Selected: ${fileNames}`
    this.filePreviewTarget.classList.remove("hidden")
  }

  formatSize(bytes) {
    if (bytes < 1024) return `${bytes} B`
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
  }

  handleSubmitStart() {
    if (this.hasUploadProgressTarget) {
      this.uploadProgressTarget.classList.remove("hidden")
    }

    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = true
      this.submitButtonTarget.classList.add("opacity-50", "cursor-not-allowed")
    }
  }

  handleSubmitEnd() {
    if (this.hasUploadProgressTarget) {
      this.uploadProgressTarget.classList.add("hidden")
    }

    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = false
      this.submitButtonTarget.classList.remove("opacity-50", "cursor-not-allowed")
    }
  }
}
