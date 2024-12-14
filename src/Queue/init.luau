--!strict

local Players = game:GetService("Players")
local module = {}

local GlobalCCU = require(script.GlobalCCU)
local Types = require(script.Parent.Types)
local StepPrecedence = require(script.Parent.StepPrecedence)

local Queue: Types.Queue = {}
local LastExecutionTime: { [Player]: { [Types.AnalyticsMethodNames]: number } } = {}
local CurrentRequestCount: number = 0
local LastResetTime: number = 0

function getRequestCapacity(): number
	local currentCCU = GlobalCCU:Get()

	return math.max(1, 120 + (20 * currentCCU) - #Players:GetPlayers())
end

function processItemInQueue(player: Player, queueKey: Types.AnalyticsMethodNames, queueData: { Types.QueueData })
	local currentTime = tick()

	-- Allow at least .1 second per queue key, per event
	local lastExecution = (LastExecutionTime[player] and LastExecutionTime[player][queueKey]) or 0
	if currentTime - lastExecution < 0.1 then
		return
	end

	-- Check global capacity
	local capacity = getRequestCapacity()
	if CurrentRequestCount >= capacity then
		return
	end

	-- Remove first from queue
	local nextInQueue = table.remove(queueData, 1)
	if not nextInQueue then
		return
	end

	-- No point in processing, if actions are absent
	local actionsData = nextInQueue.actions
	if not actionsData then
		return
	end

	local function reject(errorMessage: string)
		if nextInQueue.actions.reject and typeof(nextInQueue.actions.reject) == "function" then
			nextInQueue.actions.reject()
		end
	end

	-- Check for step precedence (Relevant funnel and onboarding funnel calls)
	if queueKey == "FunnelStep" or queueKey == "OnboardingFunnelStep" then
		local metaData = nextInQueue.metaData
		if not metaData then
			reject("`FunnelStep` and `OnboardingFunnelStep` events expect a `MetaData`")

			return
		else
			if queueKey == "FunnelStep" and not metaData.funnelSessionId then
				reject("`FunnelStep` events expect a `funnelSessionId` in `MetaData`")

				return
			end

			if not metaData.stepNumber then
				reject("`FunnelStep` and `OnboardingFunnelStep` events expect a `stepNumber` in `MetaData`")

				return
			end
		end

		local highestRecordedStepMap = 0
		if queueKey == "FunnelStep" then
			highestRecordedStepMap = StepPrecedence.HighestFunnelStep[player]
					and StepPrecedence.HighestFunnelStep[player][metaData.funnelSessionId]
				or 0
		elseif queueKey == "OnboardingFunnelStep" then
			highestRecordedStepMap = StepPrecedence.HighestOnboardingFunnelStep[player]
		end

		-- Determine maxStepNumber, remove and reject lower steps in the queue
		local maxStepNumber =
			StepPrecedence:PruneQueueAndGetMaxStep(queueKey, queueData, metaData.stepNumber, highestRecordedStepMap)

		-- Skip processing and reject if the current step is not the highest step in the queue
		if metaData.stepNumber <= maxStepNumber then
			if queueKey == "FunnelStep" then
				reject(
					StepPrecedence.InvalidFunnelStepErrorMessage(
						metaData.stepNumber,
						metaData.funnelSessionId :: string
					)
				)
			elseif queueKey == "OnboardingFunnelStep" then
				reject(StepPrecedence.InvalidOnboardingFunnelStepErrorMessage(metaData.stepNumber))
			end

			return
		end

		-- Update the highest step number
		if queueKey == "FunnelStep" then
			if not StepPrecedence.HighestFunnelStep[player] then
				StepPrecedence.HighestFunnelStep[player] = {} :: { [string]: number }
			end
			StepPrecedence.HighestFunnelStep[player][metaData.funnelSessionId] = metaData.stepNumber
		elseif queueKey == "OnboardingFunnelStep" then
			StepPrecedence.HighestOnboardingFunnelStep[player] = metaData.stepNumber
		end
	end

	-- Execute action
	do
		local success, result = pcall(function()
			actionsData.callBack()
		end)

		if success then
			if actionsData.resolve then
				actionsData.resolve()
			end
			CurrentRequestCount += 1
		else
			if actionsData.reject then
				actionsData.reject(result)
			end
		end
	end

	-- Update last execution time
	do
		if not LastExecutionTime[player] then
			LastExecutionTime[player] = {}
		end

		LastExecutionTime[player][queueKey] = currentTime
	end
end

function module:AddToQueue(
	player: Player,
	queueKey: Types.AnalyticsMethodNames,
	actions: Types.Actions,
	metaData: Types.MetaData?
)
	do
		assert(
			player and typeof(player) == "Instance" and player:IsDescendantOf(Players),
			"Invalid parameter: `player` must be provided."
		)
		assert(
			queueKey and typeof(queueKey) == "string" and queueKey == "CustomEvent"
				or queueKey == "EconomyEvent"
				or queueKey == "FunnelStep"
				or queueKey == "OnboardingFunnelStep",
			"Invalid parameter: `queueKey` must be either of the `AnalyticsMethodNames` string types."
		)

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

		if queueKey == "FunnelStep" or queueKey == "OnboardingFunnelStep" then
			assert(
				metaData and typeof(metaData) == "table",
				"Invalid parameter: `FunnelStep` and `OnboardingFunnelStep` events expect `metaData` as a table value."
			)

			assert(
				metaData.stepNumber and typeof(metaData.stepNumber) == "number",
				"Invalid `metaData` index: `FunnelStep` and `OnboardingFunnelStep` events expect `stepNumber` as a number."
			)

			if queueKey == "OnboardingFunnelStep" then
				assert(
					metaData.funnelSessionId and typeof(metaData.funnelSessionId) == "string",
					"Invalid `metaData` index: `OnboardingFunnelStep` event expects `funnelSessionId` as a string."
				)
			end
		end
	end
	local capacity = getRequestCapacity()

	-- Check if the action can be executed immediately, otherwise add to queue
	if CurrentRequestCount < capacity then
		CurrentRequestCount += 1
		local success, result = pcall(function()
			actions.callBack()
		end)

		if success then
			if actions.resolve then
				actions.resolve()
			end
		else
			if actions.reject then
				actions.reject(result)
			end
		end
	else
		if not Queue[player] then
			Queue[player] = {}
		end

		if not Queue[player][queueKey] then
			Queue[player][queueKey] = {}
		end

		table.insert(Queue[player][queueKey], {
			actions = actions,
			metaData = metaData,
		})
	end
end

-- Queue processor
task.spawn(function()
	while true do
		-- Reset the global requests counter every minute
		if os.clock() - LastResetTime >= 60 then
			CurrentRequestCount = 0
			LastResetTime = os.clock()
		end

		for player, playerQueues in pairs(Queue) do
			for queueKey, queueData in pairs(playerQueues) do
				if #queueData == 0 then
					continue
				end

				local success, errMessage = pcall(function()
					processItemInQueue(player, queueKey :: Types.AnalyticsMethodNames, queueData)
				end)

				if not success then
					warn(`Unable to process an item in the Queue processor: \n{errMessage}`)
				end
			end
		end

		task.wait(0.1)
	end
end)

return module
