// Inspired By: https://github.com/stimulus-components/stimulus-dropdown/blob/master/src/index.ts
import UIPopover from "controllers/ui/popover_controller";

export default class extends UIPopover {
  static targets = ["content", "wrapper", "trigger", "item", "search"];

  filter() {
    if (!this.hasSearchTarget) return;
    const query = this.searchTarget.value.toLowerCase().trim();
    this.itemTargets.forEach((el) => {
      const name = (el.dataset.name || "").toLowerCase();
      el.classList.toggle("hidden", query.length > 0 && !name.includes(query));
    });
  }
}
