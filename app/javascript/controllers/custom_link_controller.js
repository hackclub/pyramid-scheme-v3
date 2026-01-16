import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "feedback", "saveButton", "saveLabel"]
  static values = {
    validateUrl: String,
    updateUrl: String,
    baseUrl: String,
    isFree: String,
    changeCost: Number,
    userShards: Number
  }

  connect() {
    this.validationTimeout = null
    this.isValid = false
    this.originalValue = this.inputTarget.value
  }

  validate() {
    // Clear previous timeout
    if (this.validationTimeout) {
      clearTimeout(this.validationTimeout)
    }

    const value = this.inputTarget.value.trim()
    
    // If empty or unchanged, disable the save button
    if (!value || value === this.originalValue) {
      this.hideValidation()
      this.disableSave()
      return
    }

    // Client-side validation first
    const clientErrors = this.clientValidate(value)
    if (clientErrors.length > 0) {
      this.showError(clientErrors.join(", "))
      this.disableSave()
      return
    }

    // Debounced server-side validation
    this.showLoading()
    this.validationTimeout = setTimeout(() => {
      this.serverValidate(value)
    }, 300)
  }

  clientValidate(value) {
    const errors = []

    if (!/^[a-zA-Z]+$/.test(value)) {
      errors.push("Only letters (a-z, A-Z) allowed")
    }

    if (value.length > 64) {
      errors.push("Maximum 64 characters")
    }

    if (value.length < 3) {
      errors.push("Minimum 3 characters")
    }

    return errors
  }

  async serverValidate(value) {
    try {
      const response = await fetch(`${this.validateUrlValue}?custom_link=${encodeURIComponent(value)}`, {
        method: "GET",
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfToken()
        }
      })

      const data = await response.json()

      if (data.valid) {
        this.showSuccess("Available!")
        this.enableSave()
      } else {
        this.showError(data.errors.join(", "))
        this.disableSave()
      }
    } catch (error) {
      console.error("Validation error:", error)
      this.showError("Could not validate. Please try again.")
      this.disableSave()
    }
  }

  async save(event) {
    event.preventDefault()

    const value = this.inputTarget.value.trim()
    if (!value || !this.isValid) return

    // Check if user can afford (if not free)
    const isFree = this.isFreeValue === "true"
    if (!isFree && this.userShardsValue < this.changeCostValue) {
      this.showError(`Not enough shards. You need ${this.changeCostValue} shards.`)
      return
    }

    // Show confirmation dialog
    const confirmMessage = isFree
      ? `Set your custom link to "${value}"?`
      : `Change your custom link to "${value}"?\n\nThis will cost ${this.changeCostValue} shards.`

    if (!confirm(confirmMessage)) {
      return
    }

    // Disable button and show loading
    this.saveButtonTarget.disabled = true
    this.saveLabelTarget.textContent = "Saving..."

    try {
      const response = await fetch(this.updateUrlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfToken()
        },
        body: JSON.stringify({ custom_link: value })
      })

      const data = await response.json()

      if (data.success) {
        // Update the UI
        this.showSuccess(data.message)
        this.originalValue = value
        this.isFreeValue = "false" // Now changing will cost shards
        
        // Update the main referral link display
        const newLink = `${this.baseUrlValue}/?ref=${value}`
        const currentLinkEl = document.querySelector('[data-referral-modal-target="currentLink"]')
        if (currentLinkEl) {
          currentLinkEl.textContent = newLink
        }
        
        // Update copy buttons
        document.querySelectorAll('[data-referral-link]').forEach(el => {
          el.dataset.referralLink = newLink
        })

        // Update the shards display if present
        if (data.new_balance !== undefined) {
          this.userShardsValue = data.new_balance
        }

        // Reload after short delay to refresh all UI
        setTimeout(() => {
          window.location.reload()
        }, 1500)
      } else {
        this.showError(data.error)
      }
    } catch (error) {
      console.error("Save error:", error)
      this.showError("Could not save. Please try again.")
    } finally {
      this.saveButtonTarget.disabled = false
      this.updateSaveLabel()
    }
  }

  showLoading() {
    this.feedbackTarget.classList.remove("hidden", "text-green-400", "text-red-400")
    this.feedbackTarget.classList.add("text-gray-400")
    this.feedbackTarget.textContent = "Checking availability..."
  }

  showSuccess(message) {
    this.isValid = true
    this.feedbackTarget.classList.remove("hidden", "text-gray-400", "text-red-400")
    this.feedbackTarget.classList.add("text-green-400")
    this.feedbackTarget.textContent = `✓ ${message}`
  }

  showError(message) {
    this.isValid = false
    this.feedbackTarget.classList.remove("hidden", "text-gray-400", "text-green-400")
    this.feedbackTarget.classList.add("text-red-400")
    this.feedbackTarget.textContent = `✗ ${message}`
  }

  hideValidation() {
    this.isValid = false
    this.feedbackTarget.classList.add("hidden")
    this.feedbackTarget.textContent = ""
  }

  enableSave() {
    this.isValid = true
    this.saveButtonTarget.disabled = false
    this.saveButtonTarget.classList.remove("opacity-50", "cursor-not-allowed")
  }

  disableSave() {
    this.isValid = false
    this.saveButtonTarget.disabled = true
    this.saveButtonTarget.classList.add("opacity-50", "cursor-not-allowed")
  }

  updateSaveLabel() {
    const isFree = this.isFreeValue === "true"
    this.saveLabelTarget.textContent = isFree
      ? "Set Custom Link"
      : `Change Custom Link (${this.changeCostValue} shards)`
  }

  csrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.getAttribute("content") : ""
  }
}
