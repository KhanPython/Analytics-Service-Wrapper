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

function invalidFunnelStepErrorMessage(stepNumber: number, funnelSessionId: string): string
	return `Step {stepNumber} is invalid because a step greater than or equal to this has already been logged for funnelSessionId: {funnelSessionId}.`
end

function invalidOnboardingFunnelStepErrorMessage(stepNumber: number): string
	return `Step {stepNumber} is invalid because a step greater than or equal to this has already been logged.`
end

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

		-- Skip processing and reject if the current step is not the greater step in the queue
		if metaData.stepNumber <= maxStepNumber then
			if eventType == "FunnelStep" then
				actions.reject(invalidFunnelStepErrorMessage(metaData.stepNumber, metaData.funnelSessionId :: string))
			elseif eventType == "OnboardingFunnelStep" then
				actions.reject(invalidOnboardingFunnelStepErrorMessage(metaData.stepNumber))
			end

			return
		end

		-- Update the highest step number
		if eventType == "FunnelStep" and metaData.funnelSessionId then
			if not MaxFunnelStep[player] then
				MaxFunnelStep[player] = {} :: { [string]: number }
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
	assert(
		data.eventType and typeof(data.eventType) == "string" and data.eventType == "CustomEvent"
			or data.eventType == "EconomyEvent"
			or data.eventType == "FunnelStep"
			or data.eventType == "OnboardingFunnelStep",
		"Invalid parameter: `queueKey` must be either of the `AnalyticsMethodNames` string types."
	)

	local actions = data.actions
	assert(actions and typeof(actions) == "table", "Invalid parameter: `actions` must be a table value.")
	assert(
		actions.callBack and typeof(actions.callBack) == "function",
		"Invalid `actions` index: `callBack` must be a function."
	)
	assert(
		actions.reject and typeof(actions.reject) == "function",
		"Invalid `actions` index: `reject` must be a function."
	)
	assert(
		actions.resolve and typeof(actions.resolve) == "function",
		"Invalid `actions` index: `resolve` must be a function."
	)

	if data.eventType == "FunnelStep" or data.eventType == "OnboardingFunnelStep" then
		assert(
			data.metaData and typeof(data.metaData) == "table",
			"Invalid parameter: `FunnelStep` and `OnboardingFunnelStep` events expect `metaData` as a table value."
		)

		assert(
			data.metaData.stepNumber and typeof(data.metaData.stepNumber) == "number",
			"Invalid `metaData` index: `FunnelStep` and `OnboardingFunnelStep` events expect `stepNumber` as a number."
		)

		if data.eventType == "FunnelStep" then
			assert(
				data.metaData.funnelSessionId and typeof(data.metaData.funnelSessionId) == "string",
				"Invalid `metaData` index: `OnboardingFunnelStep` event expects `funnelSessionId` as a string."
			)

			if MaxFunnelStep[data.player] and MaxFunnelStep[data.player][data.metaData.funnelSessionId] then
				assert(
					data.metaData.stepNumber > MaxFunnelStep[data.player][data.metaData.funnelSessionId],
					invalidFunnelStepErrorMessage(data.metaData.stepNumber, data.metaData.funnelSessionId)
				)
			end
		elseif data.eventType == "OnboardingFunnelStep" then
			if MaxOnboardingFunnelStep[data.player] then
				assert(
					data.metaData.stepNumber > MaxOnboardingFunnelStep[data.player],
					invalidOnboardingFunnelStepErrorMessage(data.metaData.stepNumber)
				)
			end
		end
	end

	local originalCallback = actions.callBack
	actions.callBack = function()
		originalCallback()

		-- Automatically resolve when the callback succeeds
		actions.resolve()
	end

	local player = data.player
	if not PlayerBudgets[player] then
		PlayerBudgets[player] = getBudget()
	end

	if PlayerBudgets[player] > 0 then
		PlayerBudgets[player] -= 1
		actions.callBack()

		local metaData = data.metaData :: Types.MetaData
		if data.eventType == "FunnelStep" and metaData.funnelSessionId then
			if not MaxFunnelStep[data.player] then
				MaxFunnelStep[data.player] = {}
			end

			MaxFunnelStep[data.player][metaData.funnelSessionId] = metaData.stepNumber
		elseif data.eventType == "OnboardingFunnelStep" then
			MaxOnboardingFunnelStep[data.player] = metaData.stepNumber
		end
	else
		Queue:Enqueue(data :: Types.QueueObject)
		warn(`AnalyticsService request budget exceeded for Player: {player.Name}. Further requests will be queued.`)
	end
end

function module:TryRemove(data: Types.QueueObject)
	Queue:Remove(data)
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
				return false
			end

			local success, errMessage = pcall(function()
				processObject(nextInQueue)
			end)

			if not success then
				nextInQueue.actions.reject(
					`Unexpected error whilst trying to processes an object in queue: \n{errMessage}`
				)
			end

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
