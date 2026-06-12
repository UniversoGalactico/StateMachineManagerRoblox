# StateMachineManager – Generic State Machine Engine for NPCs
# Motor de Estados Genérico para NPCs

🌐 **English** | **Español**

---

## 🇬🇧 English

A free, production‑ready state machine engine for Roblox NPCs.  
Supports 100+ concurrent NPCs with per‑NPC mutex, rate limiting, and automatic cleanup.

**What it offers:**
- **Per‑NPC Mutex** – Prevents simultaneous state changes.
- **Pending State Queue** – If a state change is requested while busy, it's queued.
- **Rate Limiting** – Limits how many times per second an NPC can change state.
- **Auto‑Cleanup** – NPCs destroyed in the workspace are automatically unregistered.
- **Heartbeat Optimization** – The Heartbeat loop stops when no NPCs are registered.
- **Memory Leak Prevention** – Periodic cleanup of stale timestamps.

**How to use:**
1. Place the `ModuleScript` in `ServerScriptService.ServerModules`.
2. Require it: `local StateMachineManager = require(script.Parent.StateMachineManager)`
3. Register an NPC: `StateMachineManager.registerNPC(model, states, "idle", {})`
4. Change its state: `StateMachineManager.setState(model, "attack")`
5. Unregister when removed: `StateMachineManager.unregisterNPC(model)`

**Links:**
- **Talent Hub:** [More advanced modules](https://create.roblox.com/talent/creators/5075515911)
- **Discord:** universogalactico_28974 (UniversoGalactico)

---

## 🇪🇸 Español

Un motor de estados gratuito y listo para producción para NPCs en Roblox.  
Soporta más de 100 NPCs simultáneos con mutex por NPC, rate limiting y limpieza automática.

**Qué ofrece:**
- **Mutex por NPC** – Evita cambios de estado simultáneos.
- **Cola de estados pendientes** – Si se solicita un cambio mientras está ocupado, se encola.
- **Rate Limiting** – Limita cuántas veces por segundo un NPC puede cambiar de estado.
- **Auto‑limpieza** – Los NPCs destruidos en el workspace se desregistran automáticamente.
- **Optimización de Heartbeat** – El bucle Heartbeat se detiene cuando no hay NPCs registrados.
- **Prevención de fugas de memoria** – Limpieza periódica de timestamps obsoletos.

**Cómo usarlo:**
1. Coloca el `ModuleScript` en `ServerScriptService.ServerModules`.
2. Requiérelo: `local StateMachineManager = require(script.Parent.StateMachineManager)`
3. Registra un NPC: `StateMachineManager.registerNPC(model, states, "idle", {})`
4. Cambia su estado: `StateMachineManager.setState(model, "attack")`
5. Desregístralo al eliminarlo: `StateMachineManager.unregisterNPC(model)`

**Enlaces:**
- **Talent Hub:** [Módulos avanzados de pago](https://create.roblox.com/talent/creators/5075515911)
- **Discord:** universogalactico_28974 (UniversoGalactico)
---

*Made with ❤️ by Universogalactico64*
