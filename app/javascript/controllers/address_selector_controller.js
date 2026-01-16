import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "reauth"]

  connect() {
    this.fetchAddresses()
  }

  async fetchAddresses() {
    try {
      const response = await fetch('/hcauth/addresses', {
        headers: { 'Accept': 'application/json' }
      })
      const data = await response.json()
      
      this.selectTarget.innerHTML = ''

      if (this.hasReauthTarget) {
        this.reauthTarget.classList.add('hidden')
      }

      if (response.status === 401) {
        const option = document.createElement('option')
        option.value = ''
        option.textContent = 'Please reconnect Hack Club Auth to load your saved addresses.'
        this.selectTarget.appendChild(option)
        this.selectTarget.value = ''
        
        if (this.hasReauthTarget && data.reauth_url) {
          this.reauthTarget.href = data.reauth_url
          this.reauthTarget.classList.remove('hidden')
        }
        return
      }
      
      if (data.addresses && data.addresses.length > 0) {
        data.addresses.forEach((address) => {
          const option = document.createElement('option')
          const label = this.formatAddress(address)
          option.value = label
          option.textContent = label
          this.selectTarget.appendChild(option)
        })
      } else {
        const option = document.createElement('option')
        option.value = ''
        option.textContent = 'No addresses found. Please add one in HCAuth.'
        this.selectTarget.appendChild(option)
      }
    } catch (error) {
      console.error('Error fetching addresses:', error)
      this.selectTarget.innerHTML = '<option value="">Error loading addresses</option>'
    }
  }

  formatAddress(address) {
    // Matches HCAuth API contract (ref/auth/app/views/api/v1/addresses/_address.jb)
    const name = [address.first_name, address.last_name].filter(Boolean).join(' ').trim()

    const lineParts = [address.line_1, address.line_2].filter(p => p && p.trim() !== '')
    const cityLineParts = [
      address.city,
      address.state,
      address.postal_code
    ].filter(p => p && p.trim() !== '')

    const mainParts = []
    if (name) mainParts.push(name)
    if (lineParts.length) mainParts.push(lineParts.join(', '))
    if (cityLineParts.length) mainParts.push(cityLineParts.join(', '))
    if (address.country) mainParts.push(address.country)
    if (address.phone_number) mainParts.push(address.phone_number)

    const formatted = mainParts.join(' — ')
    return address.primary ? `${formatted} (Primary)` : formatted
  }
}
