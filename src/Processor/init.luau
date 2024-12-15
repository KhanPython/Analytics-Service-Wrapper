--!strict

local Players = game:GetService("Players")
local module = {}

local StepPrecedence = require(script.StepPrecedence)
local GlobalCCU = require(script.GlobalCCU)
local Queue = require(script.Queue)
local Types = require(script.Parent.Types)

local CurrentRequestCount: number = 0
local LastRefreshTime: number = 0

local REFRESH_TIME = 60
local PROCESSING_TIME = 0.1

function getBudget(): number
	local currentCCU = GlobalCCU:Get()

	return math.max(1, 120 + (20 * currentCCU))
end

function processObject(objectInQueue: Types.QueueObject)
	local actions = objectInQueue.actions
	if not actions then
		return
	end

	local player = objectInQueue.player
	assert(player and player:IsDescendantOf(Players), "`player` required")

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
			maxStepNumber = StepPrecedence.MaxFunnelStep[player]
					and StepPrecedence.MaxFunnelStep[player][funnelSessionId]
				or 0
		elseif eventType == "OnboardingFunnelStep" then
			maxStepNumber = StepPrecedence.MaxOnboardingFunnelStep[player]
		end

		-- Skip processing and reject if the current step is not the greater step in the queue
		if metaData.stepNumber <= maxStepNumber then
			if eventType == "FunnelStep" then
				actions.reject(
					StepPrecedence.InvalidFunnelStepErrorMessage(
						metaData.stepNumber,
						metaData.funnelSessionId :: string
					)
				)
			elseif eventType == "OnboardingFunnelStep" then
				actions.reject(StepPrecedence.InvalidOnboardingFunnelStepErrorMessage(metaData.stepNumber))
			end

			return
		end

		-- Update the highest step number
		if eventType == "FunnelStep" and metaData.funnelSessionId then
			if not StepPrecedence.MaxFunnelStep[player] then
				StepPrecedence.MaxFunnelStep[player] = {} :: { [string]: number }
			end
			StepPrecedence.MaxFunnelStep[player][metaData.funnelSessionId] = metaData.stepNumber
		elseif eventType == "OnboardingFunnelStep" then
			StepPrecedence.MaxOnboardingFunnelStep[player] = metaData.stepNumber
		end
	end

	CurrentRequestCount += 1
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
			assert(
				StepPrecedence:ValidateFunnelStep(data.player, data.metaData.stepNumber, data.metaData.funnelSessionId),
				StepPrecedence.InvalidFunnelStepErrorMessage(data.metaData.stepNumber, data.metaData.funnelSessionId)
			)
		elseif data.eventType == "OnboardingFunnelStep" then
			assert(
				StepPrecedence:ValidateOnBoardingFunnelStep(data.player, data.metaData.stepNumber),
				StepPrecedence.InvalidOnboardingFunnelStepErrorMessage(data.metaData.stepNumber)
			)
		end
	end

	local originalCallback = actions.callBack
	actions.callBack = function()
		originalCallback()

		-- Automatically resolve when the callback succeeds
		actions.resolve()
	end

	-- Check if the action can be executed immediately, otherwise add to queue
	if CurrentRequestCount < getBudget() then
		CurrentRequestCount += 1

		actions.callBack()

		local metaData = data.metaData :: Types.MetaData
		if data.eventType == "FunnelStep" and metaData.funnelSessionId then
			if not StepPrecedence.MaxFunnelStep[data.player] then
				StepPrecedence.MaxFunnelStep[data.player] = {}
			end

			StepPrecedence.MaxFunnelStep[data.player][metaData.funnelSessionId] = metaData.stepNumber
		elseif data.eventType == "OnboardingFunnelStep" then
			StepPrecedence.MaxOnboardingFunnelStep[data.player] = metaData.stepNumber
		end
	else
		Queue:Enqueue(data :: Types.QueueObject)

		warn(
			`AnalyticsService request budget exceeded for Player: {data.player.Name}. Further requests will be queued.`
		)
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
				CurrentRequestCount = 0
				LastRefreshTime = os.clock()
			end

			if CurrentRequestCount >= getBudget() then
				return false
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
	local connection
	connection = player.AncestryChanged:Connect(function()
		if player:IsDescendantOf(game) then
			return
		end

		if connection and typeof(connection) == "RBXScriptConnection" then
			connection:Disconnect()
		end

		task.defer(function()
			GlobalCCU:BroadcastPlayerCount()
		end)

		StepPrecedence.MaxFunnelStep[player] = nil
		StepPrecedence.MaxOnboardingFunnelStep[player] = nil

		-- Remove and reject
		for i = #Queue.Items, 1, -1 do
			local objectInQueue = Queue.Items[i]
			if objectInQueue.player ~= player then
				continue
			end

			table.remove(Queue.Items, i)
			pcall(function()
				objectInQueue.actions.reject(`Player left before an event could be processed`)
			end)
		end
	end)

	GlobalCCU:BroadcastPlayerCount()
end)

return module
