--!strict
--!native

local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")

local module = {}

module.GlobalPlayerCount = 0

function module:Get(): number
	return module.GlobalPlayerCount
end

local function broadcastPlayerCount()
	local playerCount = #Players:GetPlayers()

	local success, errMessage = pcall(function()
		MessagingService:PublishAsync("ASW_PlayerCount", playerCount)
	end)

	if not success then
		warn(`Unable to broadcast player count due to a MessagingService error: \n {errMessage}`)
	end
end

Players.PlayerAdded:Connect(function(player: Player)
	local connection
	connection = player.AncestryChanged:Connect(function()
		if player:IsDescendantOf(game) then
			return
		end

		if connection and typeof(connection) == "RBXScriptConnection" then
			connection:Disconnect()
		end

		broadcastPlayerCount()
	end)

	broadcastPlayerCount()
end)

task.spawn(function()
	MessagingService:SubscribeAsync("ASW_PlayerCount", function(message)
		local receivedCount = tonumber(message.Data) or 0
		module.GlobalPlayerCount = module.GlobalPlayerCount + receivedCount
	end)

	broadcastPlayerCount()
end)

return module
