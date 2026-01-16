import { Controller } from "@hotwired/stimulus"

// Simple client-side filter for a list of items.
//
// Usage:
// - Put this controller on a wrapper element.
// - Mark the search input as data-ui--list-filter-target="search"
// - Mark each item as data-ui--list-filter-target="item" and set data-name="...".
export default class extends Controller {
  static targets = ["search", "item"]

  filter(event) {
    const query = (event?.target?.value || "").toLowerCase().trim()

    this.itemTargets.forEach((item) => {
      const name = (item.dataset.name || item.textContent || "").toLowerCase()
      item.style.display = name.includes(query) ? "" : "none"
    })
  }
}
