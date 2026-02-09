import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["unitPrice", "totalPrice"]

  connect() {
    this.updateTotal()
  }

  updateTotal() {
    if (!this.hasUnitPriceTarget) return
    
    const unitPrice = this.readUnitPrice()
    const quantity = this.readQuantity()
    
    const total = unitPrice * quantity
    
    if (this.hasTotalPriceTarget) {
      this.totalPriceTarget.textContent = this.formatNumber(total)
    }
  }

  formatNumber(num) {
    return num.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",")
  }

  confirmPurchase(event) {
    event.preventDefault()
    
    const form = event.target
    const quantity = this.readQuantity()
    
    // Extract item name from the page
    const titleElement = document.querySelector('h1')
    const actualItemName = titleElement ? titleElement.textContent.trim() : 'this item'
    
    const unitPrice = this.readUnitPrice()
    const total = unitPrice * quantity
    
    const message = quantity > 1 
      ? `Are you sure you want to purchase ${quantity}x "${actualItemName}" for ${this.formatNumber(total)} shards?`
      : `Are you sure you want to purchase "${actualItemName}" for ${this.formatNumber(total)} shards?`
    
    if (confirm(message)) {
      form.submit()
    }
  }

  readUnitPrice() {
    if (!this.hasUnitPriceTarget) return 0

    const value = Number.parseInt(this.unitPriceTarget.dataset.unitPrice || "0", 10)
    return Number.isNaN(value) ? 0 : Math.max(value, 0)
  }

  readQuantity() {
    const quantitySelect = this.element.querySelector('#quantity')
    if (!quantitySelect) return 1

    const value = Number.parseInt(quantitySelect.value || "1", 10)
    return Number.isNaN(value) ? 1 : Math.max(value, 1)
  }
}
