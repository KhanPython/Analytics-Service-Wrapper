--!strict

local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")

local module = {}

module.GlobalPlayerCount = 0

function module:Get(): number
	return module.GlobalPlayerCount or 0
end

function module:BroadcastPlayerCount()
	local playerCount = #Players:GetPlayers()

	local success, errMessage = pcall(function()
		MessagingService:PublishAsync("ASW_PlayerCount", playerCount)
	end)

	if not success then
		warn(`Unable to broadcast player count due to a MessagingService error: \n {errMessage}`)
	end
end

task.spawn(function()
	MessagingService:SubscribeAsync("ASW_PlayerCount", function(message)
		local receivedCount = tonumber(message.Data) or 0
		module.GlobalPlayerCount = module.GlobalPlayerCount + receivedCount
	end)

	module:BroadcastPlayerCount()
end)

return module
