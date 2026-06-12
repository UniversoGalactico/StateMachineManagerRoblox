--[[
	StateMachineManager.lua | Generic State Machine Engine for NPCs
	Motor de Estados Genérico para NPCs
	
	🌐 ENGLISH / ESPAÑOL 🌐
	
	🔒 FEATURES / CARACTERÍSTICAS:
	• Supports 100+ concurrent NPCs / Soporta más de 100 NPCs simultáneos
	• Per-NPC mutex with pending state queue / Mutex por NPC con cola de estados pendientes
	• Rate limiting for state changes / Rate limiting para cambios de estado
	• Auto-cleanup of destroyed NPCs / Auto-limpieza de NPCs destruidos
	• Heartbeat optimization (stops when idle) / Optimización de Heartbeat (se detiene si no hay NPCs)
	• Memory leak prevention with periodic cleanup / Prevención de fugas de memoria con limpieza periódica
	
	📚 USAGE / USO:
	1. Place this ModuleScript in ServerScriptService.ServerModules
	2. Require it: local StateMachineManager = require(script.Parent.StateMachineManager)
	3. Call StateMachineManager.registerNPC(model, states, initialState, initialData)
	4. Call StateMachineManager.setState(model, newState) to change state
	5. Call StateMachineManager.unregisterNPC(model) when the NPC is removed
	
	By Universogalactico64 – Free module. More advanced systems on Talent Hub.
]]

local StateMachineManager = {}
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local CONFIG = table.freeze({
	MAX_NPCS = 100,
	MAX_STATEDATA_KEYS = 100,
	STATE_CHANGE_RATE = 10,            -- cambios de estado por segundo por NPC
	HEARTBEAT_STOP_WHEN_EMPTY = true,  -- detener Heartbeat si no hay NPCs
	WATCHDOG_INTERVAL = 30,            -- segundos entre limpiezas de memoria
})

-- Estado interno
local npcs = {}                  -- array de NPCs
local npcLookup = {}             -- [model] = index en npcs
local heartbeatConn = nil
local loopActive = false

-- Rate limiting para cambios de estado (por NPC)
local stateChangeTimestamps = {} -- [npcKey] = {timestamps}

-- Helper de logs
local function log(level, msg)
	if level == "warn" then
		warn("[StateMachine] " .. msg)
	elseif level == "info" then
		print("[StateMachine] " .. msg)
	end
end

-- Sanitización de datos (patrón DataManager)
local function isValidData(value)
	if value == nil then return true end -- nil es válido
	local t = type(value)
	if t == "function" or t == "userdata" or t == "thread" then return false end
	if typeof(value) == "Instance" then return false end
	if t == "number" and value ~= value then return false end
	if t == "table" then
		local count = 0
		for k, v in pairs(value) do
			count += 1
			if count > CONFIG.MAX_STATEDATA_KEYS then return false end
			if not isValidData(k) or not isValidData(v) then return false end
		end
	end
	return true
end

-- Adquiere mutex para un NPC
local function lockNPC(npc)
	if npc.mutex then return false end
	npc.mutex = true
	return true
end

local function unlockNPC(npc)
	npc.mutex = false
end

-- Rate limiting para cambios de estado
local function isStateChangeLimited(npcKey)
	local now = os.clock()
	stateChangeTimestamps[npcKey] = stateChangeTimestamps[npcKey] or {}
	local ts = stateChangeTimestamps[npcKey]
	local i = 1
	while ts[i] and (now - ts[i]) > 1.0 do
		table.remove(ts, i)
	end
	if #ts >= CONFIG.STATE_CHANGE_RATE then return true end
	table.insert(ts, now)
	return false
end

-- Cambia el estado de un NPC de forma segura
local function setState(npc, newStateName)
	if not npc or not npc.model or not npc.model.Parent then
		log("warn", "setState: NPC inválido o destruido")
		return
	end
	if not npc.states[newStateName] then
		log("warn", "setState: estado '" .. tostring(newStateName) .. "' no definido")
		return
	end
	if npc.currentState == newStateName then return end

	-- Clave única para rate limiting (se calcula después de validar el modelo)
	local npcKey = tostring(npc.model) .. "_" .. npc._id

	-- Rate limiting
	if isStateChangeLimited(npcKey) then
		log("warn", "setState: rate limit para " .. npcKey)
		return
	end

	-- Mutex
	if not lockNPC(npc) then
		-- Encolar cambio para después
		if not npc._pendingState then
			npc._pendingState = newStateName
			task.delay(0, function()
				if npc and npc.model and npc.model.Parent then
					setState(npc, npc._pendingState)
					npc._pendingState = nil
				end
			end)
		else
			npc._pendingState = newStateName
		end
		return
	end

	local oldState = npc.currentState
	local oldCbs = npc.states[oldState]
	local newCbs = npc.states[newStateName]

	-- Ejecutar onExit (protegido)
	if oldCbs and oldCbs.onExit then
		pcall(oldCbs.onExit, npc.model, npc.stateData)
	end

	-- Actualizar estado
	npc.currentState = newStateName

	-- Ejecutar onEnter (protegido)
	if newCbs and newCbs.onEnter then
		pcall(newCbs.onEnter, npc.model, npc.stateData)
	end

	unlockNPC(npc)
	log("info", "NPC cambió de '" .. oldState .. "' a '" .. newStateName .. "'")
end

-- Bucle Heartbeat (con protección de iteración)
local function startHeartbeat()
	if heartbeatConn then return end
	loopActive = true
	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		-- Sanitizar dt
		if type(dt) ~= "number" or dt ~= dt or dt <= 0 or dt > 1 then
			dt = 1/60 -- valor por defecto
		end

		-- Clonar la lista de NPCs para evitar problemas si un callback modifica la tabla
		local currentNPCs = table.clone(npcs)
		local toRemove = {}

		for i, npc in ipairs(currentNPCs) do
			if not npc.model or not npc.model.Parent then
				table.insert(toRemove, i)
				continue
			end

			local state = npc.currentState
			local cbs = npc.states[state]
			if cbs and cbs.onUpdate then
				local ok, err = pcall(cbs.onUpdate, npc.model, dt, npc.stateData)
				if not ok then
					log("warn", "Error en onUpdate de '" .. state .. "': " .. tostring(err))
				end
			end
		end

		-- Eliminar NPCs destruidos (de atrás hacia adelante)
		for i = #toRemove, 1, -1 do
			local idx = toRemove[i]
			local npc = npcs[idx] -- usar la tabla original para obtener el NPC real
			if npc then
				local cbs = npc.states[npc.currentState]
				if cbs and cbs.onExit then
					pcall(cbs.onExit, npc.model, npc.stateData)
				end
				-- Limpiar rate limiting
				local npcKey = tostring(npc.model) .. "_" .. npc._id
				stateChangeTimestamps[npcKey] = nil
				npcLookup[npc.model] = nil
				table.remove(npcs, idx)
				-- Actualizar índices en lookup
				for j = idx, #npcs do
					npcLookup[npcs[j].model] = j
				end
				log("info", "NPC auto‑eliminado (destruido). Restantes: " .. #npcs)
			end
		end

		-- Detener Heartbeat si no hay NPCs
		if #npcs == 0 and CONFIG.HEARTBEAT_STOP_WHEN_EMPTY then
			loopActive = false
			if heartbeatConn then
				heartbeatConn:Disconnect()
				heartbeatConn = nil
			end
		end
	end)
end

-- Watchdog de limpieza de memoria
task.spawn(function()
	while true do
		task.wait(CONFIG.WATCHDOG_INTERVAL)
		local now = os.clock()
		for npcKey, timestamps in pairs(stateChangeTimestamps) do
			-- Eliminar entradas vacías o muy antiguas
			local i = 1
			while timestamps[i] and (now - timestamps[i]) > 60 do
				table.remove(timestamps, i)
			end
			if #timestamps == 0 then
				stateChangeTimestamps[npcKey] = nil
			end
		end
	end
end)

-- ================================================================
-- API PÚBLICA
-- ================================================================

local nextId = 0
function StateMachineManager.registerNPC(npcModel, stateDefinitions, initialStateName, initialStateData)
	if not npcModel or not npcModel.Parent then
		log("warn", "registerNPC: modelo inválido")
		return false
	end
	if type(stateDefinitions) ~= "table" or not stateDefinitions[initialStateName] then
		log("warn", "registerNPC: estados inválidos")
		return false
	end
	if #npcs >= CONFIG.MAX_NPCS then
		log("warn", "registerNPC: límite alcanzado")
		return false
	end
	if npcLookup[npcModel] then
		log("warn", "registerNPC: ya registrado")
		return false
	end

	local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		log("warn", "registerNPC: el modelo no tiene Humanoid, no podrá moverse")
	end

	-- Sanitizar stateData
	local sanitizedData = {}
	if initialStateData then
		if not isValidData(initialStateData) then
			log("warn", "registerNPC: stateData contiene tipos prohibidos, se ignorará")
		else
			sanitizedData = table.clone(initialStateData)
		end
	end

	-- Asignar ID único
	nextId = nextId + 1
	local npcId = nextId

	local npc = {
		model = npcModel,
		states = stateDefinitions,
		currentState = initialStateName,
		stateData = sanitizedData,
		mutex = false,
		_pendingState = nil,
		_id = npcId,
	}
	table.insert(npcs, npc)
	npcLookup[npcModel] = #npcs

	if not heartbeatConn then
		startHeartbeat()
	end

	-- Ejecutar onEnter del estado inicial (protegido y con mutex)
	lockNPC(npc)
	local initCbs = stateDefinitions[initialStateName]
	if initCbs and initCbs.onEnter then
		pcall(initCbs.onEnter, npcModel, sanitizedData)
	end
	unlockNPC(npc)

	log("info", "NPC registrado (ID: " .. npcId .. "). Total: " .. #npcs)
	return true
end

function StateMachineManager.unregisterNPC(npcModel)
	local idx = npcLookup[npcModel]
	if not idx then return false end

	local npc = npcs[idx]
	-- Ejecutar onExit del estado actual
	local cbs = npc.states[npc.currentState]
	if cbs and cbs.onExit then
		pcall(cbs.onExit, npcModel, npc.stateData)
	end

	-- Limpiar estado pendiente
	npc._pendingState = nil

	-- Limpiar rate limiting
	local npcKey = tostring(npc.model) .. "_" .. npc._id
	stateChangeTimestamps[npcKey] = nil

	-- Eliminar y actualizar índices
	table.remove(npcs, idx)
	npcLookup[npcModel] = nil
	for i = idx, #npcs do
		npcLookup[npcs[i].model] = i
	end

	-- Detener Heartbeat si no quedan NPCs
	if #npcs == 0 and CONFIG.HEARTBEAT_STOP_WHEN_EMPTY then
		loopActive = false
		if heartbeatConn then
			heartbeatConn:Disconnect()
			heartbeatConn = nil
		end
	end

	log("info", "NPC eliminado. Restantes: " .. #npcs)
	return true
end

function StateMachineManager.setState(npcModel, newStateName)
	local idx = npcLookup[npcModel]
	if not idx then
		log("warn", "setState: NPC no encontrado")
		return
	end
	setState(npcs[idx], newStateName)
end

function StateMachineManager.stop()
	loopActive = false
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
	-- Limpiar todos los NPCs (sin ejecutar onExit, es detención de emergencia)
	for _, npc in ipairs(npcs) do
		unlockNPC(npc)
		npc._pendingState = nil
	end
	table.clear(npcs)
	table.clear(npcLookup)
	table.clear(stateChangeTimestamps)
	log("info", "Motor detenido.")
end

-- Cierre seguro
game:BindToClose(function()
	StateMachineManager.stop()
end)

return StateMachineManager
