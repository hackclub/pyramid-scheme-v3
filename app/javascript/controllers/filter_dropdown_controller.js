import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  select(event) {
    const button = event.currentTarget
    const value = button.dataset.filterDropdownParam
    const formId = button.dataset.filterDropdownFormId
    const name = button.dataset.filterDropdownName
    
    const form = document.getElementById(formId)
    if (!form) return
    
    // Update or add hidden input
    let input = form.querySelector(`input[name="${name}"]`)
    if (!input) {
      input = document.createElement('input')
      input.type = 'hidden'
      input.name = name
      form.appendChild(input)
    }
    input.value = value
    
    // Submit the form
    form.requestSubmit()
  }
}