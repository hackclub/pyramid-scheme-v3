# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"

# Used by stimulus-use (imported directly from ga.jspm.io in our Stimulus controllers).
# Without this pin, the browser will throw:
#   Module name, 'hotkeys-js' does not resolve to a valid URL.
pin "hotkeys-js", to: "https://ga.jspm.io/npm:hotkeys-js@3.13.7/dist/hotkeys.esm.js"

pin_all_from "app/javascript/controllers", under: "controllers"
