-- Example: tag NPC models with "StateMachineNPC". No pathfinding is included.
-- Install StateMachine and optional StateMachineGroup next to this script.
local CollectionService=game:GetService("CollectionService")
local RunService=game:GetService("RunService")
local StateMachine=require(script.Parent.StateMachine)
local StateMachineGroup=require(script.Parent.StateMachineGroup)
local graph=StateMachine.compile({
	Initial="Idle",
	States={
		Idle={Transitions={Alert=true},Update=function(model)
			if model:GetAttribute("Alert")==true then return "Alert" end
		end},
		Alert={Transitions={Idle=true},Update=function(model)
			if model:GetAttribute("Alert")~=true then return "Idle" end
		end},
	},
})
local group=StateMachineGroup.new()
local active={}
local tag="StateMachineNPC"
local function remove(model)
	local record=active[model]
	if not record then return end
	active[model]=nil
	record.connection:Disconnect()
	group:Remove(record.machine)
	local ok,code=record.machine:Destroy()
	if not ok and code=="BUSY" then
		task.defer(function() record.machine:Destroy() end)
	end
end
local function add(model)
	if not model:IsA("Model") or active[model] then return end
	local machine=graph:Create(model,function(context,old,new)
		context:SetAttribute("AIState",new)
	end)
	model:SetAttribute("AIState",machine:GetState())
	local record={machine=machine,connection=model.Destroying:Once(function() remove(model) end)}
	active[model]=record
	assert(group:Add(machine))
end
local added=CollectionService:GetInstanceAddedSignal(tag):Connect(add)
local removed=CollectionService:GetInstanceRemovedSignal(tag):Connect(remove)
for _,model in CollectionService:GetTagged(tag) do add(model) end
local heartbeat=RunService.Heartbeat:Connect(function(dt)
	local ok,result=group:Step(dt)
	if not ok then warn(result); return end
	for _,issue in result.Issues do warn("NPC update",issue.Code) end
end)
script.Destroying:Once(function()
	heartbeat:Disconnect(); added:Disconnect(); removed:Disconnect()
	local models={}; for model in pairs(active) do table.insert(models,model) end
	for _,model in ipairs(models) do remove(model) end
	group:Destroy()
end)
