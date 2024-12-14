--!strict
--!native

local Players = game:GetService("Players")
local module = {}

local StepPrecedence = require(script.StepPrecedence)
local GlobalCCU = require(script.GlobalCCU)
local Types = require(script.Parent.Types)

local Queue: Types.Queue = {}
local LastExecutionTime: { [Player]: { [Types.AnalyticsMethodNames]: number } } = {}
local CurrentRequestCount: number = 0
local LastResetTime: number = 0

function getRequestBudget(): number
	local currentCCU = GlobalCCU:Get()

	return math.max(1, 120 + (20 * currentCCU))
end

function reject(rejectCallback: (string) -> (), errorMessage: string)
	if rejectCallback and typeof(rejectCallback) == "function" then
		rejectCallback(errorMessage)
	end
end

function pruneQueueAndGetMaxStep(
	player: Player,
	queueKey: Types.SteppedMethodNames,
	lowestStepNumber: number,
	funnelSessionId: string
): number
	local highestStepNumber: number = 0
	if queueKey == "FunnelStep" then
		assert(funnelSessionId and typeof(funnelSessionId) == "string", "funnelSessionId required")
		highestStepNumber = StepPrecedence.HighestFunnelStep[player]
			and StepPrecedence.HighestFunnelStep[player][funnelSessionId]
	elseif queueKey == "OnboardingFunnelStep" then
		highestStepNumber = StepPrecedence.HighestOnboardingFunnelStep[player]
	end

	local queueData = Queue[player][queueKey]
	if #queueData == 0 then
		return highestStepNumber
	end

	for i = #queueData, 1, -1 do
		local data = queueData[i]
		local metaData = data.metaData

		if not metaData then
			continue
		end

		local stepNumber = metaData.stepNumber
		if not stepNumber then
			continue
		end

		if stepNumber > highestStepNumber then
			highestStepNumber = stepNumber
		elseif stepNumber < lowestStepNumber then
			local droppedData = table.remove(queueData, i)
			if not droppedData then
				continue
			end

			local actionsData = droppedData.actions
			if not actionsData then
				continue
			end

			if queueKey == "FunnelStep" then
				reject(
					actionsData.reject,
					StepPrecedence.InvalidFunnelStepErrorMessage(
						metaData.stepNumber,
						metaData.funnelSessionId :: string
					)
				)
			elseif queueKey == "OnboardingFunnelStep" then
				reject(actionsData.reject, StepPrecedence.InvalidOnboardingFunnelStepErrorMessage(metaData.stepNumber))
			end
		end
	end

	return highestStepNumber
end

function processItemInQueue(player: Player, queueKey: Types.AnalyticsMethodNames, itemInQueue: Types.QueueData)
	-- No point in processing if actions are absent
	local actionsData = itemInQueue.actions
	if not actionsData then
		return
	end

	-- Check for step precedence (Relevant for funnel and onboarding funnel calls)
	if queueKey == "FunnelStep" or queueKey == "OnboardingFunnelStep" then
		local metaData = itemInQueue.metaData
		assert(metaData, "`FunnelStep` and `OnboardingFunnelStep` events expect a `MetaData`")
		assert(
			metaData.stepNumber,
			"`FunnelStep` and `OnboardingFunnelStep` events expect a `stepNumber` in `MetaData`"
		)
		assert(
			queueKey == "FunnelStep" and metaData.funnelSessionId,
			"`FunnelStep` events expect a `funnelSessionId` in `MetaData`"
		)

		-- Determine maxStepNumber, remove and reject lower or equivalent steps in the queue
		local maxStepNumber = pruneQueueAndGetMaxStep(player, queueKey, metaData.stepNumber, metaData.funnelSessionId)

		-- Skip processing and reject if the current step is not the highest step in the queue
		if metaData.stepNumber <= maxStepNumber then
			if queueKey == "FunnelStep" then
				reject(
					actionsData.reject,
					StepPrecedence.InvalidFunnelStepErrorMessage(
						metaData.stepNumber,
						metaData.funnelSessionId :: string
					)
				)
			elseif queueKey == "OnboardingFunnelStep" then
				reject(actionsData.reject, StepPrecedence.InvalidOnboardingFunnelStepErrorMessage(metaData.stepNumber))
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

		LastExecutionTime[player][queueKey] = tick()
	end
end

function module:AddToQueue(
	player: Player,
	queueKey: Types.AnalyticsMethodNames,
	actions: Types.Actions,
	metaData: Types.MetaData?
)
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

		if queueKey == "FunnelStep" then
			assert(
				metaData.funnelSessionId and typeof(metaData.funnelSessionId) == "string",
				"Invalid `metaData` index: `OnboardingFunnelStep` event expects `funnelSessionId` as a string."
			)
			assert(
				StepPrecedence:ValidateFunnelStep(player, metaData.stepNumber, metaData.funnelSessionId),
				StepPrecedence.InvalidFunnelStepErrorMessage(metaData.stepNumber, metaData.funnelSessionId)
			)
		elseif queueKey == "OnboardingFunnelStep" then
			assert(
				StepPrecedence:ValidateOnBoardingFunnelStep(player, metaData.stepNumber),
				StepPrecedence.InvalidOnboardingFunnelStepErrorMessage(metaData.stepNumber)
			)
		end
	end

	local budget = getRequestBudget()

	-- Check if the action can be executed immediately, otherwise add to queue
	if CurrentRequestCount < budget then
		CurrentRequestCount += 1
		local success, result = pcall(function()
			actions.callBack()
		end)

		if success then
			if metaData then
				if queueKey == "FunnelStep" then
					if not StepPrecedence.HighestFunnelStep[player] then
						StepPrecedence.HighestFunnelStep[player] = {} :: { [string]: number }
					end

					StepPrecedence.HighestFunnelStep[player][metaData.funnelSessionId] = metaData.stepNumber
				elseif queueKey == "OnboardingFunnelStep" then
					StepPrecedence.HighestOnboardingFunnelStep[player] = metaData.stepNumber
				end
			end

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

		local currentTime = tick()

		for player, playerQueues in pairs(Queue) do
			for queueKey, queueData in pairs(playerQueues) do
				if #queueData == 0 then
					continue
				end

				-- Allow at least .1 second per queue key, per event
				local lastExecution = (
					LastExecutionTime[player] and LastExecutionTime[player][queueKey :: Types.AnalyticsMethodNames]
				) or 0
				if currentTime - lastExecution < 0.1 then
					continue
				end

				-- Check global capacity
				local budget = getRequestBudget()
				if CurrentRequestCount >= budget then
					continue
				end

				-- Remove first from queue
				local nextInQueue = table.remove(queueData, 1)
				if not nextInQueue then
					continue
				end

				local success, errMessage = pcall(function()
					processItemInQueue(player, queueKey :: Types.AnalyticsMethodNames, nextInQueue)
				end)

				if not success and nextInQueue.actions and nextInQueue.actions.reject then
					reject(nextInQueue.actions.reject, `Unable to process an event in the queue: \n{errMessage}`)
				end
			end
		end

		task.wait(0.1)
	end
end)

return module
