# Integration rules

Read README.md and docs/API.md. One machine per logical entity; explicit transitions only. Guard returns exactly true, synchronous. OnChanged is post-commit; true with an error code means state already changed. Never yield or reenter mutation methods from callbacks. Capture Token before asynchronous work and use TransitionIfCurrent. Caller owns scheduling, connections and cleanup. Destroy when done. Do not claim network authority or performance certification from this pure local library.
