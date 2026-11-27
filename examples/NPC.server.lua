-- Server Script under an NPC model. Put StateMachine in ServerScriptService.
local RunService=game:GetService("RunService")
local StateMachine=require(game.ServerScriptService.StateMachine)
local npc=script.Parent
local machine=StateMachine.new({
	Initial="Idle", Context=npc,
	States={
		Idle={Transitions={Alert=true},Update=function(model)
			if model:GetAttribute("Alert")==true then return "Alert" end
		end},
		Alert={Transitions={Idle=true},Update=function(model)
			if model:GetAttribute("Alert")~=true then return "Idle" end
		end},
	},
	OnChanged=function(model,old,new) model:SetAttribute("AIState",new) end,
})
npc:SetAttribute("AIState",machine:GetState())
local heartbeat=RunService.Heartbeat:Connect(function(dt)
	local ok,code=machine:Step(dt)
	if code then warn("State machine:",ok,code) end
end)
npc.Destroying:Once(function()
	heartbeat:Disconnect()
	machine:Destroy()
end)
