--!strict

local module = {}

module.MaxFunnelStep = {} :: { [Player]: { [string]: number } }
module.MaxOnboardingFunnelStep = {} :: { [Player]: number }

-- Checks whether the given `stepNumber` is the highest step under the given `funnelSessionId` in the FunnelStep Map
function module:ValidateFunnelStep(player: Player, stepNumber: number, funnelSessionId: string): boolean
	return module.MaxFunnelStep[player]
		and module.MaxFunnelStep[player][funnelSessionId]
		and stepNumber > module.MaxFunnelStep[player][funnelSessionId]
end

-- Checks whether the given `stepNumber` is the highest step in the onBoardingFunnelStep Map
function module:ValidateOnBoardingFunnelStep(player: Player, stepNumber: number): boolean
	return module.MaxOnboardingFunnelStep[player] and stepNumber > module.MaxOnboardingFunnelStep[player]
end

function module.InvalidFunnelStepErrorMessage(stepNumber: number, funnelSessionId: string)
	return `Step {stepNumber} is invalid because a step greater than or equal to this has already been logged for funnelSessionId: {funnelSessionId}.`
end

function module.InvalidOnboardingFunnelStepErrorMessage(stepNumber: number)
	return `Step {stepNumber} is invalid because a step greater than or equal to this has already been logged.`
end

return module
