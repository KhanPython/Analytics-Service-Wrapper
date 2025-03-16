--!strict

local Players = game:GetService("Players")
local module = {}

local Queue = require(script.Queue)
local Types = require(script.Parent.Types)

local MaxFunnelStep = {} :: { [Player]: { [string]: number } }
local MaxOnboardingFunnelStep = {} :: { [Player]: number }
local PlayerBudgets = {} :: { [Player]: number }
local LastRefreshTime: number = 0

local REFRESH_TIME = 30
local PROCESSING_TIME = 0.1

function getBudget(): number
	return 140 -- 120 + (20 * CCU)
end

function processObject(objectInQueue: Types.QueueObject)
	local actions = objectInQueue.actions
	if not actions then
		return
	end

	local player = objectInQueue.player
	assert(player and player:IsDescendantOf(Players), "`player` required")

	if not PlayerBudgets[player] then
		PlayerBudgets[player] = getBudget()
	end

	if PlayerBudgets[player] <= 0 then
		actions.reject(`Player {player.Name} has exceeded their analytics request budget.`)
		return
	end

	PlayerBudgets[player] -= 1

	local eventType = objectInQueue.eventType
	assert(eventType, "`eventType` required")

	-- Check for step precedence (Relevant for funnel events)
	if eventType == "FunnelStep" or eventType == "OnboardingFunnelStep" then
		local metaData = objectInQueue.metaData
		assert(metaData, "`metaData` required")

		local currentStep = metaData.stepNumber
		assert(currentStep, "`stepNumber` required")

		local maxStepNumber = 0
		if eventType == "FunnelStep" then
			local funnelSessionId = metaData.funnelSessionId
			assert(funnelSessionId, "`funnelSessionId` required")
			maxStepNumber = MaxFunnelStep[player] and MaxFunnelStep[player][funnelSessionId] or 0
		elseif eventType == "OnboardingFunnelStep" then
			maxStepNumber = MaxOnboardingFunnelStep[player] or 0
		end

		if metaData.stepNumber <= maxStepNumber then
			if eventType == "FunnelStep" then
				actions.reject(
					`Step {metaData.stepNumber} is invalid. Already logged for session: {metaData.funnelSessionId}.`
				)
			elseif eventType == "OnboardingFunnelStep" then
				actions.reject(`Step {metaData.stepNumber} is invalid. Already logged.`)
			end
			return
		end

		-- Update the highest step number
		if eventType == "FunnelStep" and metaData.funnelSessionId then
			if not MaxFunnelStep[player] then
				MaxFunnelStep[player] = {}
			end
			MaxFunnelStep[player][metaData.funnelSessionId] = metaData.stepNumber
		elseif eventType == "OnboardingFunnelStep" then
			MaxOnboardingFunnelStep[player] = metaData.stepNumber
		end
	end

	actions.callBack()
end

function module:Add(data: Types.QueueObject)
	assert(data and typeof(data) == "table", "Invalid parameter: `data` must be a table value.")
	assert(
		data.player and typeof(data.player) == "Instance" and data.player:IsDescendantOf(Players),
		"Invalid parameter: expected a Player."
	)

	local player = data.player
	if not PlayerBudgets[player] then
		PlayerBudgets[player] = getBudget()
	end

	local actions = data.actions
	assert(actions and typeof(actions) == "table", "Invalid parameter: `actions` must be a table value.")

	if PlayerBudgets[player] > 0 then
		PlayerBudgets[player] -= 1
		actions.callBack()
	else
		Queue:Enqueue(data)
		warn(`AnalyticsService request budget exceeded for Player: {player.Name}. Further requests will be queued.`)
	end
end

-- Queue processor
task.spawn(function()
	while true do
		local success, errMessage = pcall(function()
			if os.clock() - LastRefreshTime >= REFRESH_TIME then
				for player, _ in pairs(PlayerBudgets) do
					PlayerBudgets[player] = getBudget()
				end
				LastRefreshTime = os.clock()
			end

			local nextInQueue = Queue:Dequeue()
			if not nextInQueue then
				return true
			end

			processObject(nextInQueue)

			return true
		end)

		if not success then
			warn(`Unexpected error in queue processor: \n{errMessage}`)
		end

		task.wait(PROCESSING_TIME)
	end
end)

Players.PlayerAdded:Connect(function(player: Player)
	PlayerBudgets[player] = getBudget()

	local connection
	connection = player.AncestryChanged:Connect(function()
		if player:IsDescendantOf(game) then
			return
		end

		if connection and typeof(connection) == "RBXScriptConnection" then
			connection:Disconnect()
		end

		MaxFunnelStep[player] = nil
		MaxOnboardingFunnelStep[player] = nil
		PlayerBudgets[player] = nil

		-- Remove and reject queue items for the player
		for i = #Queue.Items, 1, -1 do
			local objectInQueue = Queue.Items[i]
			if objectInQueue.player ~= player then
				continue
			end

			table.remove(Queue.Items, i)
			pcall(function()
				objectInQueue.actions.reject("Player left before an event could be processed")
			end)
		end
	end)
end)

return module
