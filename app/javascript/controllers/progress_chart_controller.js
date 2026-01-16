import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    metric: String
  }

  connect() {
    this.chart = null
    this.initChart()
  }

  async initChart() {
    // Wait for Chart.js to load
    await this.waitForChartJs()

    const canvas = this.element.querySelector("canvas")
    if (!canvas) return

    const ctx = canvas.getContext("2d")

    // Load initial data
    await this.loadData(this.metricValue)
  }

  async loadData(metric) {
    try {
      const response = await fetch(`/admin/progress/data?metric=${metric}`)
      const data = await response.json()

      // Destroy existing chart if it exists
      if (this.chart) {
        this.chart.destroy()
      }

      const canvas = this.element.querySelector("canvas")
      const ctx = canvas.getContext("2d")

      this.chart = new Chart(ctx, {
        type: "line",
        data: {
          labels: data.labels,
          datasets: [
            {
              label: "Pyramid v2",
              data: data.v2,
              borderColor: "#6366f1",
              backgroundColor: "#6366f120",
              borderWidth: 2,
              fill: false,
              tension: 0.3,
              pointRadius: 0,
              pointHoverRadius: 5
            },
            {
              label: "Pyramid v3 (Current)",
              data: data.v3,
              borderColor: "#22c55e",
              backgroundColor: "#22c55e20",
              borderWidth: 2,
              fill: false,
              tension: 0.3,
              pointRadius: 0,
              pointHoverRadius: 5
            }
          ]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          interaction: {
            intersect: false,
            mode: "index"
          },
          plugins: {
            legend: {
              display: true,
              position: "top",
              labels: {
                color: "#a1a1aa",
                usePointStyle: true,
                padding: 15
              }
            },
            tooltip: {
              backgroundColor: "rgba(0, 0, 0, 0.8)",
              titleColor: "#fff",
              bodyColor: "#fff",
              padding: 12,
              displayColors: true,
              callbacks: {
                title: function(context) {
                  return `Day ${context[0].label}`
                }
              }
            }
          },
          scales: {
            x: {
              title: {
                display: true,
                text: "Days Since Launch",
                color: "#a1a1aa"
              },
              grid: {
                color: "rgba(128, 128, 128, 0.15)"
              },
              ticks: {
                maxRotation: 0,
                maxTicksLimit: 10,
                color: "#a1a1aa"
              }
            },
            y: {
              beginAtZero: true,
              title: {
                display: true,
                text: "Cumulative Count",
                color: "#a1a1aa"
              },
              grid: {
                color: "rgba(128, 128, 128, 0.15)"
              },
              ticks: {
                precision: 0,
                color: "#a1a1aa"
              }
            }
          }
        }
      })
    } catch (error) {
      console.error(`Failed to load ${metric} data:`, error)
    }
  }

  async waitForChartJs() {
    // Wait up to 5 seconds for Chart.js
    for (let i = 0; i < 50; i++) {
      if (typeof Chart !== "undefined") return
      await new Promise(resolve => setTimeout(resolve, 100))
    }
    console.error("Chart.js not loaded")
  }

  changeMetric(event) {
    const metric = event.target.value
    this.loadData(metric)
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
    }
  }
}
