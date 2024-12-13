local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")

local module = {}

module.GlobalPlayerCount = 0

function module:Get(): number
	return module.GlobalPlayerCount
end

local function broadcastPlayerCount()
	local playerCount = #Players:GetPlayers()

	pcall(function()
		MessagingService:PublishAsync("ASW_PlayerCount", playerCount)
	end)
end

task.spawn(function()
	broadcastPlayerCount()
end)

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

MessagingService:SubscribeAsync("ASW_PlayerCount", function(message)
	local receivedCount = tonumber(message.Data) or 0
	module.GlobalPlayerCount = module.GlobalPlayerCount + receivedCount
end)

return module
