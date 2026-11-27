-- Example server-side ability lifecycle. This script demonstrates the API only.
-- Wire requests to your own validated server-side gameplay logic.
local RunService=game:GetService("RunService")
local StateMachine=require(script.Parent.StateMachine)
local context={Stamina=100}
local ability=StateMachine.new({
	Initial="Ready", Context=context,
	States={
		Ready={
			Events={Use="Casting"},
			Transitions={Casting=function(c) return c.Stamina>=20 end},
		},
		Casting={
			Enter=function(c) c.Stamina-=20 end,
			Transitions={Cooldown=true},
			Events={Cancel="Cooldown"},
			After={Seconds=0.4,Target="Cooldown"},
		},
		Cooldown={Transitions={Ready=true},After={Seconds=3,Target="Ready"}},
	},
})
local connection=RunService.Heartbeat:Connect(function(dt)
	local ok,code=ability:Step(dt)
	if code then warn("Ability",ok,code) end
end)
local function useAbility()
	return ability:Send("Use") -- validate ownership/request on your server first
end
useAbility()
script.Destroying:Once(function() connection:Disconnect(); ability:Destroy() end)
