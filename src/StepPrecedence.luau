--!strict

local Types = require(script.Parent.Types)

local module = {}

module.HighestFunnelStep = {} :: { [Player]: { string: number } }
module.HighestOnboardingFunnelStep = {} :: { [Player]: number }

function module:ValidateFunnelStep(player: Player, stepNumber: number, funnelSessionId: string): boolean
	return module.HighestFunnelStep[player]
		and module.HighestFunnelStep[player][funnelSessionId]
		and stepNumber > module.HighestFunnelStep[player][funnelSessionId]
end

function module:ValidateOnBoardingFunnelStep(player: Player, stepNumber: number): boolean
	return module.HighestOnboardingFunnelStep[player] and stepNumber > module.HighestOnboardingFunnelStep[player]
end

function module:PruneQueueAndGetMaxStep(
	queueKey: Types.SteppedMethodNames,
	queueData: { Types.QueueData },
	currentStepNumber: number,
	maxStepNumber: number
): number
	if not maxStepNumber then
		maxStepNumber = 0
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

		if stepNumber > maxStepNumber then
			maxStepNumber = stepNumber
		elseif stepNumber < currentStepNumber then
			local droppedData = table.remove(queueData, i)
			if not droppedData then
				continue
			end

			local actionsData = droppedData.actions
			if actionsData.reject and typeof(actionsData.resolve) == "function" then
				--! TO-DO REJECTION MESSAGE
				actionsData.reject("")
			end
		end
	end

	return maxStepNumber
end

function module.InvalidFunnelStepErrorMessage(stepNumber: number, funnelSessionId: string)
	return `Step {stepNumber} is invalid because a step greater than or equal to this has already been logged for funnelSessionId: {funnelSessionId}.`
end

function module.InvalidOnboardingFunnelStepErrorMessage(stepNumber: number)
	return `Step {stepNumber} is invalid because a step greater than or equal to this has already been logged.`
end

return module
