--!strict
--!native

local module = {}

module.HighestFunnelStep = {} :: { [Player]: { string: number } }
module.HighestOnboardingFunnelStep = {} :: { [Player]: number }

-- Checks whether the given `stepNumber` is the highest step under the given `funnelSessionId` in the FunnelStep Map
function module:ValidateFunnelStep(player: Player, stepNumber: number, funnelSessionId: string): boolean
	return module.HighestFunnelStep[player]
		and module.HighestFunnelStep[player][funnelSessionId]
		and stepNumber > module.HighestFunnelStep[player][funnelSessionId]
end

-- Checks whether the given `stepNumber` is the highest step in the onBoardingFunnelStep Map
function module:ValidateOnBoardingFunnelStep(player: Player, stepNumber: number): boolean
	return module.HighestOnboardingFunnelStep[player] and stepNumber > module.HighestOnboardingFunnelStep[player]
end

function module.InvalidFunnelStepErrorMessage(stepNumber: number, funnelSessionId: string)
	return `Step {stepNumber} is invalid because a step greater than or equal to this has already been logged for funnelSessionId: {funnelSessionId}.`
end

function module.InvalidOnboardingFunnelStepErrorMessage(stepNumber: number)
	return `Step {stepNumber} is invalid because a step greater than or equal to this has already been logged.`
end

return module
