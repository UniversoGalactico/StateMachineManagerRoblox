--!strict
-- Optional deterministic registry for stepping many machines from one caller loop.
-- Membership is not ownership: removing or destroying a group never destroys a machine.
export type Member = {Step: (self: any, dt: number) -> (boolean, string?, any?)}
export type Issue = {Member: Member, Succeeded: boolean, Code: string, Detail: any?}
export type Summary = {
	Attempted: number, Succeeded: number, Failed: number, Warnings: number,
	RemovedDestroyed: number, Issues: {Issue},
}
export type Group = {
	Add: (self: Group, member: Member) -> (boolean, string?),
	Remove: (self: Group, member: Member) -> (boolean, string?),
	Has: (self: Group, member: Member) -> boolean,
	Count: (self: Group) -> number,
	Step: (self: Group, dt: number) -> (boolean, Summary | string),
	Destroy: (self: Group) -> (boolean, string?),
}
type Record = {Member: Member?, Step: ((any, number) -> (boolean, string?, any?))?}
local StateMachineGroup = {VERSION="3.0.0-rc.2"}

-- Adapters are permitted, but a broken adapter must not suspend a group tick.
local function call(step: any, member: Member, dt: number): (boolean, string?, any?)
	local thread = coroutine.create(step)
	local ran, ok, code, detail = coroutine.resume(thread, member, dt)
	if coroutine.status(thread) ~= "dead" then
		if task and task.cancel then pcall(task.cancel, thread) end
		pcall(coroutine.close, thread)
		return false, "STEP_YIELDED", nil
	end
	if not ran then return false, "STEP_ERROR", ok end
	if type(ok) ~= "boolean" or (code ~= nil and type(code) ~= "string") then
		return false, "INVALID_STEP_RESULT", nil
	end
	return ok, code, detail
end

function StateMachineGroup.new(): Group
	local order: {Record} = {}
	local records: {[Member]: Record} = {}
	local count = 0
	local busy = false
	local destroyed = false
	local group = {} :: any

	local function compact()
		-- Rebuild both containers to release old peak capacity after heavy churn.
		local newOrder: {Record} = {}
		local newRecords: {[Member]: Record} = {}
		for _, record in ipairs(order) do
			local member = record.Member
			if member ~= nil then
				table.insert(newOrder, record)
				newRecords[member] = record
			end
		end
		order, records = newOrder, newRecords
	end
	local function shouldCompact(): boolean
		return count == 0 or (#order - count >= 64 and #order >= 2*count)
	end
	local function remove(record: Record)
		local member = record.Member
		if member == nil or records[member] ~= record then return false end
		records[member] = nil
		record.Member, record.Step = nil, nil
		count -= 1
		-- Amortized compaction outside a tick. During a tick, its insertion-order
		-- snapshot is preserved; removed entries are tombstones without references.
		if not busy and shouldCompact() then compact() end
		return true
	end
	function group:Add(member: any): (boolean, string?)
		if destroyed then return false, "DESTROYED" end
		if type(member) ~= "table" or getmetatable(member) ~= nil then return false, "INVALID_MEMBER" end
		local step = rawget(member, "Step")
		if type(step) ~= "function" then return false, "INVALID_MEMBER" end
		if records[member] then return false, "ALREADY_ADDED" end
		local record: Record = {Member=member, Step=step}
		records[member] = record
		table.insert(order, record)
		count += 1
		return true, nil
	end
	function group:Remove(member: any): (boolean, string?)
		if destroyed then return false, "DESTROYED" end
		if type(member) ~= "table" then return false, "INVALID_MEMBER" end
		local record = records[member]
		if not record then return false, "NOT_FOUND" end
		remove(record)
		return true, nil
	end
	function group:Has(member: any): boolean
		return not destroyed and type(member) == "table" and records[member] ~= nil
	end
	function group:Count(): number return count end
	function group:Step(dt: any): (boolean, Summary | string)
		if destroyed then return false, "DESTROYED" end
		if busy then return false, "BUSY" end
		if type(dt) ~= "number" or dt ~= dt or dt < 0 or dt >= math.huge then return false, "INVALID_DT" end
		busy = true
		local summary: Summary = {Attempted=0, Succeeded=0, Failed=0, Warnings=0, RemovedDestroyed=0, Issues={}}
		local boundary = #order
		for i = 1, boundary do
			local record = order[i]
			local member, step = record.Member, record.Step
			if member == nil or step == nil or records[member] ~= record then continue end
			summary.Attempted += 1
			local ok, code, detail = call(step, member, dt)
			if ok then summary.Succeeded += 1 else summary.Failed += 1 end
			if code ~= nil or not ok then
				if ok then summary.Warnings += 1 end
				table.insert(summary.Issues, {Member=member, Succeeded=ok, Code=code or "STEP_REJECTED", Detail=detail})
			end
			if not ok and code == "DESTROYED" and remove(record) then summary.RemovedDestroyed += 1 end
		end
		busy = false
		if #order ~= count and shouldCompact() then compact() end
		return true, summary
	end
	function group:Destroy(): (boolean, string?)
		if destroyed then return true, nil end
		if busy then return false, "BUSY" end
		destroyed = true
		order, records = {}, {}
		count = 0
		return true, nil
	end
	table.freeze(group)
	return group :: Group
end
return table.freeze(StateMachineGroup)
