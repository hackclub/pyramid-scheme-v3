import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "uploadForm", "uploadButton", "fileInputs", "uploadProgress"]

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

    // Always reload the page when closing the modal
    window.location.reload()
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

  handleUploadSubmit(e) {
    // Show loading state
    if (this.hasUploadProgressTarget) {
      this.uploadProgressTarget.classList.remove("hidden")
    }

    // Disable file inputs and submit button
    if (this.hasFileInputsTarget) {
      this.fileInputsTargets.forEach(input => {
        input.disabled = true
        input.classList.add("opacity-50", "cursor-not-allowed")
      })
    }

    if (this.hasUploadButtonTarget) {
      this.uploadButtonTarget.disabled = true
      this.uploadButtonTarget.classList.add("opacity-50", "cursor-not-allowed")
      const originalText = this.uploadButtonTarget.textContent
      this.uploadButtonTarget.textContent = "Uploading..."
      this.uploadButtonTarget.dataset.originalText = originalText
    }
  }

  handleUploadEnd(e) {
    // Hide loading state
    if (this.hasUploadProgressTarget) {
      this.uploadProgressTarget.classList.add("hidden")
    }

    // Re-enable file inputs
    if (this.hasFileInputsTarget) {
      this.fileInputsTargets.forEach(input => {
        input.disabled = false
        input.classList.remove("opacity-50", "cursor-not-allowed")
      })
    }

    // Re-enable and restore submit button
    if (this.hasUploadButtonTarget) {
      this.uploadButtonTarget.disabled = false
      this.uploadButtonTarget.classList.remove("opacity-50", "cursor-not-allowed")
      if (this.uploadButtonTarget.dataset.originalText) {
        this.uploadButtonTarget.textContent = this.uploadButtonTarget.dataset.originalText
      }
    }
  }

  previewProofImage(e) {
    const file = e.target.files[0]
    if (!file || !file.type.startsWith('image/')) return

    const reader = new FileReader()
    reader.onload = (event) => {
      const previewId = `proof-preview-${e.target.dataset.posterId}`
      let preview = document.getElementById(previewId)

      if (!preview) {
        preview = document.createElement('div')
        preview.id = previewId
        preview.className = 'mt-3'
        e.target.parentElement.appendChild(preview)
      }

      preview.innerHTML = `
        <p class="text-xs text-[#5b2a1f]/70 mb-2">Preview:</p>
        <img src="${event.target.result}" class="w-full max-h-64 object-contain rounded-lg border-2 border-[#5b2a1f]/20" alt="Proof preview">
      `
    }
    reader.readAsDataURL(file)
  }

  previewSupportingEvidence(e) {
    const files = Array.from(e.target.files)
    if (files.length === 0) return

    const previewId = `evidence-preview-${e.target.dataset.posterId}`
    let preview = document.getElementById(previewId)

    if (!preview) {
      preview = document.createElement('div')
      preview.id = previewId
      preview.className = 'mt-3'
      e.target.parentElement.appendChild(preview)
    }

    const previewsHtml = files.map((file, index) => {
      if (file.type.startsWith('image/')) {
        return new Promise((resolve) => {
          const reader = new FileReader()
          reader.onload = (event) => {
            resolve(`<img src="${event.target.result}" class="w-full h-24 object-cover rounded-lg border-2 border-[#5b2a1f]/20" alt="Evidence preview ${index + 1}">`)
          }
          reader.readAsDataURL(file)
        })
      } else if (file.type.startsWith('video/')) {
        return Promise.resolve(`
          <div class="flex items-center justify-center h-24 rounded-lg border-2 border-[#5b2a1f]/20 bg-[#5b2a1f]/5">
            <span class="text-xs text-[#5b2a1f]/70">Video: ${file.name}</span>
          </div>
        `)
      } else {
        return Promise.resolve(`
          <div class="flex items-center justify-center h-24 rounded-lg border-2 border-[#5b2a1f]/20 bg-[#5b2a1f]/5">
            <span class="text-xs text-[#5b2a1f]/70">${file.name}</span>
          </div>
        `)
      }
    })

    Promise.all(previewsHtml).then(htmlArray => {
      preview.innerHTML = `
        <p class="text-xs text-[#5b2a1f]/70 mb-2">Preview (${files.length} file${files.length === 1 ? '' : 's'}):</p>
        <div class="grid grid-cols-2 gap-2">
          ${htmlArray.join('')}
        </div>
      `
    })
  }

  connect() {
    document.addEventListener("keydown", this.closeOnEscape.bind(this))

    // Listen for turbo:submit-start to show upload progress
    this.element.addEventListener("turbo:submit-start", this.handleUploadSubmit.bind(this))
    // Listen for turbo:submit-end to hide upload progress
    this.element.addEventListener("turbo:submit-end", this.handleUploadEnd.bind(this))
  }

  disconnect() {
    document.removeEventListener("keydown", this.closeOnEscape.bind(this))
    this.element.removeEventListener("turbo:submit-start", this.handleUploadSubmit.bind(this))
    this.element.removeEventListener("turbo:submit-end", this.handleUploadEnd.bind(this))
  }
}
