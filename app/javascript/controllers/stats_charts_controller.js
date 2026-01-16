import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    range: { type: String, default: "1m" }
  }

  connect() {
    this.charts = {}
    this.modes = {
      growth: "users",
      success: "completed_referrals",
      traffic: "proxy_hits"
    }

    // Wait for Chart.js to load
    this.initCharts()
  }

  async initCharts() {
    // Wait a bit for Chart.js to be available
    await new Promise(resolve => setTimeout(resolve, 100))

    if (typeof Chart === "undefined") {
      console.error("Chart.js not loaded")
      return
    }

    // Set default Chart.js options for dark mode compatibility
    // Use explicit light colors since CSS variables may not be available
    Chart.defaults.color = '#a1a1aa' // zinc-400 - visible on dark backgrounds
    Chart.defaults.borderColor = '#3f3f46' // zinc-700

    await Promise.all([
      this.loadChart("growth", "growthChart", this.modes.growth),
      this.loadChart("success", "successChart", this.modes.success),
      this.loadChart("traffic", "trafficChart", this.modes.traffic)
    ])
  }

  async loadChart(chartKey, canvasId, dataType) {
    const canvas = document.getElementById(canvasId)
    if (!canvas) return

    const ctx = canvas.getContext("2d")

    try {
      const response = await fetch(`/admin/statistics/data?range=${this.rangeValue}&type=${dataType}`)
      if (!response.ok) {
        console.error(`Failed to load ${chartKey} chart: ${response.status} ${response.statusText}`)
        return
      }
      const data = await response.json()

      // Destroy existing chart if it exists
      if (this.charts[chartKey]) {
        this.charts[chartKey].destroy()
      }

      this.charts[chartKey] = new Chart(ctx, {
        type: "line",
        data: {
          labels: data.labels,
          datasets: [{
            label: this.getLabel(dataType),
            data: data.values,
            borderColor: this.getColor(chartKey),
            backgroundColor: this.getColor(chartKey) + "20",
            borderWidth: 2,
            fill: true,
            tension: 0.3,
            pointRadius: 3,
            pointHoverRadius: 5
          }]
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
              display: false
            },
            tooltip: {
              backgroundColor: "rgba(0, 0, 0, 0.8)",
              titleColor: "#fff",
              bodyColor: "#fff",
              padding: 12,
              displayColors: false
            }
          },
          scales: {
            x: {
              grid: {
                display: false
              },
              ticks: {
                maxRotation: 0,
                maxTicksLimit: 8,
                color: '#a1a1aa' // zinc-400
              }
            },
            y: {
              beginAtZero: true,
              grid: {
                color: "rgba(128, 128, 128, 0.15)"
              },
              ticks: {
                precision: 0,
                color: '#a1a1aa' // zinc-400
              }
            }
          }
        }
      })
    } catch (error) {
      console.error(`Failed to load ${chartKey} chart:`, error)
    }
  }

  getLabel(dataType) {
    const labels = {
      users: "New Users",
      referrals: "New Referrals",
      completed_referrals: "Completed Referrals",
      verified_posters: "Verified Posters",
      proxy_hits: "Referral Hits",
      poster_scans: "Poster Scans"
    }
    return labels[dataType] || dataType
  }

  getColor(chartKey) {
    const colors = {
      growth: "#3b82f6",
      success: "#22c55e",
      traffic: "#f59e0b"
    }
    return colors[chartKey] || "#6366f1"
  }

  switchMode(event) {
    const chartKey = event.params.chart
    const mode = event.params.mode

    this.modes[chartKey] = mode

    // Update button styling
    const buttons = event.target.closest(".flex").querySelectorAll(".chart-mode-btn")
    buttons.forEach(btn => {
      btn.classList.remove("bg-background", "text-foreground", "shadow-sm")
      btn.classList.add("text-muted-foreground", "hover:text-foreground")
    })
    event.target.classList.remove("text-muted-foreground", "hover:text-foreground")
    event.target.classList.add("bg-background", "text-foreground", "shadow-sm")

    // Reload the chart with new data
    const canvasId = chartKey + "Chart"
    this.loadChart(chartKey, canvasId, mode)
  }

  disconnect() {
    Object.values(this.charts).forEach(chart => {
      if (chart) chart.destroy()
    })
  }
}
