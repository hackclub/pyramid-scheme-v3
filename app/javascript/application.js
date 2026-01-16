// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Handle rate limit errors
document.addEventListener("turbo:fetch-request-error", (event) => {
  const { response } = event.detail
  if (response && response.status === 429) {
    event.preventDefault()
    
    const retryAfter = response.headers.get("Retry-After") || "60"
    
    // Create and append toast notification
    const toastContainer = document.getElementById("toast-container")
    if (toastContainer) {
      const toast = document.createElement("div")
      toast.setAttribute("data-controller", "toast")
      toast.setAttribute("data-toast-duration-value", "8000")
      toast.className = "transform translate-x-full opacity-0 transition-all duration-300 ease-out flex items-start gap-3 p-4 rounded-xl border border-destructive/30 bg-background shadow-lg backdrop-blur-sm"
      toast.innerHTML = `
        <div class="flex-shrink-0 w-5 h-5 mt-0.5 text-destructive text-xl">⚠️</div>
        <div class="flex-1 min-w-0">
          <p class="text-sm font-semibold text-foreground">Rate Limit Exceeded</p>
          <p class="text-sm text-muted-foreground mt-0.5">Please wait ${retryAfter} seconds before trying again.</p>
        </div>
        <button type="button" data-action="toast#dismiss" class="flex-shrink-0 p-1 -m-1 text-muted-foreground hover:text-foreground transition-colors text-xl">×</button>
      `
      toastContainer.appendChild(toast)
    }
  }
})
