import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["unitPrice", "totalPrice"]

  connect() {
    this.updateTotal()
  }

  updateTotal() {
    if (!this.hasUnitPriceTarget) return
    
    const unitPrice = parseInt(this.unitPriceTarget.dataset.unitPrice)
    const quantitySelect = this.element.querySelector('#quantity')
    const quantity = quantitySelect ? parseInt(quantitySelect.value) : 1
    
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
    const quantitySelect = form.querySelector('#quantity')
    const quantity = quantitySelect ? parseInt(quantitySelect.value) : 1
    
    // Extract item name from the page
    const titleElement = document.querySelector('h1')
    const actualItemName = titleElement ? titleElement.textContent.trim() : 'this item'
    
    const unitPrice = this.hasUnitPriceTarget ? parseInt(this.unitPriceTarget.dataset.unitPrice) : 0
    const total = unitPrice * quantity
    
    const message = quantity > 1 
      ? `Are you sure you want to purchase ${quantity}x "${actualItemName}" for ${this.formatNumber(total)} shards?`
      : `Are you sure you want to purchase "${actualItemName}" for ${this.formatNumber(total)} shards?`
    
    if (confirm(message)) {
      form.submit()
    }
  }
}
