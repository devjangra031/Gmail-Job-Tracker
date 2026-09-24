import { Controller } from "@hotwired/stimulus"

// Submits the applications filter form into its Turbo Frame as you type or pick,
// and shows the custom date fields only for the "custom" range preset.
export default class extends Controller {
  static targets = ["range", "custom"]

  connect() {
    this.toggleCustom()
  }

  search() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.submit(), 300)
  }

  submit() {
    this.element.requestSubmit()
  }

  rangeChanged() {
    this.toggleCustom()
    if (this.rangeTarget.value !== "custom") this.submit()
  }

  toggleCustom() {
    const custom = this.rangeTarget.value === "custom"
    this.customTargets.forEach((el) => el.classList.toggle("hidden", !custom))
  }
}
