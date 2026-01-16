import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    data: Object
  }

  connect() {
    this.initChart()
  }

  async initChart() {
    // Wait for Chart.js to load
    await this.waitForChartJs()

    const canvas = document.getElementById("shardPieChart")
    if (!canvas) return

    const ctx = canvas.getContext("2d")
    const data = this.dataValue

    const labels = Object.keys(data)
    const values = Object.values(data)
    const colors = ["#8b5cf6", "#06b6d4", "#f59e0b", "#ec4899", "#10b981", "#6366f1"]

    this.chart = new Chart(ctx, {
      type: "doughnut",
      data: {
        labels: labels,
        datasets: [{
          data: values,
          backgroundColor: colors.slice(0, labels.length),
          borderColor: "rgba(0, 0, 0, 0.1)",
          borderWidth: 2,
          hoverOffset: 4
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: true,
        cutout: "60%",
        plugins: {
          legend: {
            display: false
          },
          tooltip: {
            backgroundColor: "rgba(0, 0, 0, 0.8)",
            titleColor: "#fff",
            bodyColor: "#fff",
            padding: 12,
            displayColors: true,
            callbacks: {
              label: function(context) {
                const value = context.raw
                const total = context.dataset.data.reduce((a, b) => a + b, 0)
                const percentage = ((value / total) * 100).toFixed(1)
                return ` ${value.toLocaleString()} (${percentage}%)`
              }
            }
          }
        }
      }
    })
  }

  async waitForChartJs() {
    // Wait up to 5 seconds for Chart.js
    for (let i = 0; i < 50; i++) {
      if (typeof Chart !== "undefined") return
      await new Promise(resolve => setTimeout(resolve, 100))
    }
    console.error("Chart.js not loaded")
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
    }
  }
}
