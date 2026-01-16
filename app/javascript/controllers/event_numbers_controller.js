import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["tab", "panel"];
  static values = { active: String };

  connect() {
    if (!this.hasActiveValue) {
      this.activeValue = this.tabTargets[0]?.dataset.key;
    } else {
      this.refresh();
    }
  }

  show(event) {
    const key = event.params?.key || event.currentTarget?.dataset.key;
    if (key && key !== this.activeValue) {
      this.activeValue = key;
    }
  }

  activeValueChanged() {
    this.refresh();
  }

  refresh() {
    this.tabTargets.forEach((tab) => {
      const isActive = tab.dataset.key === this.activeValue;
      tab.setAttribute("aria-selected", isActive);
      tab.dataset.state = isActive ? "active" : "inactive";
    });

    this.panelTargets.forEach((panel) => {
      const isActive = panel.dataset.key === this.activeValue;
      panel.hidden = !isActive;
      panel.dataset.state = isActive ? "active" : "inactive";
    });
  }
}
