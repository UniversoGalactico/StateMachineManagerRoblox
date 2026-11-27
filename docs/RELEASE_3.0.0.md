# StateMachineManager 3.0.0

Stable release of the generic state-machine API, MIT, no runtime dependencies. Includes the optional StateMachineGroup and Studio smoke script. See README and docs/API.md for integration.

Breaking change from the original global NPC registry: applications own scheduling and lifecycle.

Evidence: 33 regression suites at O0/O1/O2, strict CLI type analysis, 15 selected semantic mutations detected, finite external numerical audit on rc.2 (1,268,640 checks including repeated inputs and arithmetic-oracle checks), and maintainer-reported 15/15 Studio smoke checks. Final modules differ from rc.2 only in version strings. No certification of production scale or arbitrary game callbacks.
