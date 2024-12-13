--!nonstrict

-- Services
local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

-- Dependencies
local Promise = require(script.Parent.promise)

-- Types
type FunnelSessions = { [number]: string }
type CustomFieldNames = "CustomField01" | "CustomField02" | "CustomField03"
type CustomFields = { [CustomFieldNames]: string }
type SteppedMethodNames = "FunnelStep" | "OnboardingFunnelStep"
type AnalyticsMethodNames = "CustomEvent" | "EconomyEvent" | SteppedMethodNames

type Actions = {
	action: () -> (),
	resolve: (() -> ())?,
	reject: ((string) -> ())?,
	stepNumber: number?,
}
type Queue = {
	[Player]: {
		[AnalyticsMethodNames]: { Actions },
	},
}

-- Queues and Analytics Cooldowns
local Queue: Queue = {}

local AnalyticsCooldowns: { [AnalyticsMethodNames]: number } = {
	CustomEvent = 0.5, -- 2 events per second, per player
	FunnelStep = 1, -- 1 event per second, per player
	EconomyEvent = 1,
	OnboardingFunnelStep = 1,
}

local LastExecutionTime: { [Player]: { [AnalyticsMethodNames]: number } } = {}
local HighestFunnelStep: { [Player]: { string: number } } = {}
local HighestOnboardingFunnelStep: { [Player]: number } = {}

local PlayerFunnelSessions: FunnelSessions = {}

local module = {}

local function validateCustomFields(customFields: CustomFields?): boolean
	if not customFields then
		return true
	end

	local include = { "CustomField01", "CustomField02", "CustomField03" }

	for key, value in customFields do
		if not table.find(include, key) then
			return false
		end

		if typeof(value) ~= "string" then
			return false
		end

		if #value:split(",") > 20 then
			return false
		end
	end

	return true
end

function module:_AddToQueue(
	player: Player,
	queueKey: AnalyticsMethodNames,
	action: () -> (),
	resolve: (() -> ())?,
	reject: ((string) -> ())?
)
	assert(
		player and typeof(player) == "Instance" and player:IsDescendantOf(Players),
		"Invalid parameter: `player` must be provided."
	)

	if not Queue[player] then
		Queue[player] = {}
	end

	local actions: Actions = {
		action = action,
		resolve = resolve,
		reject = reject,
	}

	if not Queue[player][queueKey] then
		Queue[player][queueKey] = {}
	end

	table.insert(Queue[player][queueKey], actions)
end

-- Initialize a new funnel session for a player
function module:_StartFunnelSession(player: Player): string?
	assert(
		player and typeof(player) == "Instance" and player:IsDescendantOf(Players),
		"Invalid parameter: `player` must be provided."
	)

	if PlayerFunnelSessions[player.UserId] then
		PlayerFunnelSessions[player.UserId] = nil
	end

	local funnelSessionId = HttpService:GenerateGUID(false)
	local _connection: RBXScriptConnection? = nil

	local _connection = player.AncestryChanged:Connect(function()
		if player:IsDescendantOf(game) then
			return
		end

		PlayerFunnelSessions[player.UserId] = nil

		if _connection ~= nil then
			_connection:Disconnect()
		end
	end)

	PlayerFunnelSessions[player.UserId] = funnelSessionId

	return funnelSessionId
end

function module:_GetFunnelSession(player: Player): string?
	assert(
		player and typeof(player) == "Instance" and player:IsDescendantOf(Players),
		"Invalid parameter: `player` must be provided."
	)

	return PlayerFunnelSessions[player.UserId]
end

function module:ForValues(promiseCallback: any, playerList: { Player })
	return Promise.new(function(resolve, reject)
		assert(typeof(promiseCallback) == "function", "Invalid `promiseCallback` provided.")
		assert(playerList and #playerList > 0, "`list` cannot be an empty table.")

		for _, player in pairs(playerList) do
			assert(
				typeof(player) == "Instance" and player:IsDescendantOf(Players),
				"Invalid parameter: `player` must be provided."
			)
		end

		local activePromises = {}

		for _, player in pairs(playerList) do
			table.insert(activePromises, promiseCallback(player))
		end

		Promise.allSettled(activePromises)
			:andThen(function(results)
				for _, result in pairs(results) do
					if result.status == "rejected" then
						warn("Function failed for value: " .. tostring(result.reason))
					end
				end
				resolve()
			end)
			:catch(function(errMessage)
				warn("Unexpected error during Promise.allSettled: " .. tostring(errMessage))
				reject(errMessage)
			end)
	end)
end

function module:LogCustomEvent(player: Player, eventName: string, value: number?, customFields: CustomFields?)
	return Promise.new(function(resolve, reject)
		assert(
			player and typeof(player) == "Instance" and player:IsDescendantOf(Players),
			"Invalid parameter: `player` must be provided."
		)
		assert(type(eventName) == "string", "Invalid parameter: `eventName` must be a string.")
		assert(value == nil or typeof(value) == "number", "Invalid parameter: `value` must be a number.")
		assert(validateCustomFields(customFields), "Invalid `customFields`.")

		self:_AddToQueue(player, "CustomEvent", function()
			AnalyticsService:LogCustomEvent(player, eventName, value or 1, customFields)
		end, resolve, reject)
	end)
end

function module:LogEconomyEvent(
	player: Player,
	flowType: Enum.AnalyticsEconomyFlowType,
	currencyType: string,
	amount: number,
	endingBalance: number,
	transactionType: Enum.AnalyticsEconomyTransactionType | { Name: string },
	itemSKU: string?,
	customFields: CustomFields?
)
	return Promise.new(function(resolve, reject)
		assert(
			flowType == nil or typeof(flowType) == "EnumItem",
			"Invalid parameter: `flowType` must be an Enum.AnalyticsEconomyFlowType or nil for default dynamic determination."
		)
		assert(typeof(currencyType) == "string", "Invalid parameter: `currencyType` must be a string.")
		assert(typeof(amount) == "number" and amount >= 0, "Invalid parameter: `amount` must be a non-negative number.")
		assert(
			typeof(endingBalance) == "number" and endingBalance >= 0,
			"Invalid parameter: `endingBalance` must be a non-negative number."
		)
		assert(
			(typeof(transactionType) == "table" and transactionType.Name ~= nil)
				or typeof(transactionType) == "EnumItem",
			"Invalid parameter: `transactionType` must be an Enum.AnalyticsEconomyTransactionType or a table with a `Name` field."
		)
		assert(validateCustomFields(customFields), "Invalid `customFields`.")

		if not flowType then
			flowType = amount < 0 and Enum.AnalyticsEconomyFlowType.Sink or Enum.AnalyticsEconomyFlowType.Source
		end
		amount = math.abs(amount)
		endingBalance = math.max(endingBalance, 0)

		self:_AddToQueue(player, "EconomyEvent", function()
			AnalyticsService:LogEconomyEvent(
				player,
				flowType,
				currencyType,
				amount,
				endingBalance,
				transactionType,
				itemSKU,
				customFields
			)
		end, resolve, reject)
	end)
end

function module:LogFunnelStep(
	player: Player,
	funnelName: string,
	funnelSessionId: string,
	stepNumber: number,
	stepName: string?,
	customFields: CustomFields?
)
	return Promise.new(function(resolve, reject)
		assert(
			funnelSessionId == nil or typeof(funnelSessionId) == "string",
			"Invalid parameter: `funnelSessionId` must be a string."
		)
		assert(
			typeof(stepNumber) == "number" and (stepNumber >= 1 and stepNumber <= 100),
			"Invalid parameter: `stepNumber` must be a positive number between 1-100."
		)
		assert(typeof(funnelName) == "string", "Invalid parameter: `funnelName` must be a string.")
		assert(stepName == nil or typeof(stepName) == "string", "Invalid parameter: `stepName` must be a string.")
		assert(validateCustomFields(customFields), "Invalid `customFields`.")

		if not funnelSessionId then
			local guidFunnelSessionId = self:_GetFunnelSession(player)
			if not guidFunnelSessionId then
				funnelSessionId = self:_StartFunnelSession(player)
			end
		end

		if
			HighestFunnelStep[player]
			and HighestFunnelStep[player][funnelSessionId]
			and stepNumber <= HighestFunnelStep[player][funnelSessionId]
		then
			reject(
				`Step {stepNumber} is invalid because a step greater than or equal to this has already been logged for funnelSessionId {funnelSessionId}.`
			)
			return
		end

		self:_AddToQueue(player, "FunnelStep", function()
			AnalyticsService:LogFunnelStepEvent(
				player,
				funnelName,
				funnelSessionId,
				stepNumber,
				stepName or "",
				customFields
			)
			HighestFunnelStep[player] = {
				[funnelSessionId] = stepNumber,
			}
		end, resolve, reject, stepNumber)
	end)
end

function module:LogOnboardingFunnelStep(
	player: Player,
	stepNumber: number,
	stepName: string?,
	customFields: CustomFields?
)
	return Promise.new(function(resolve, reject)
		assert(
			typeof(stepNumber) == "number" and (stepNumber >= 1 and stepNumber <= 100),
			"Invalid parameter: `stepNumber` must be a positive number between 1-100."
		)
		assert(stepName == nil or typeof(stepName) == "string", "Invalid parameter: `stepName` must be a string.")
		assert(validateCustomFields(customFields), "Invalid `customFields`.")

		if HighestOnboardingFunnelStep[player] and stepNumber <= HighestOnboardingFunnelStep[player] then
			reject(`Step {stepNumber} is invalid because a step greater than or equal to this has already been logged.`)
			return
		end

		self:_AddToQueue(player, "OnboardingFunnelStep", function()
			AnalyticsService:LogOnboardingFunnelStepEvent(player, stepNumber, stepName or "", customFields)
			HighestOnboardingFunnelStep[player] = stepNumber
		end, resolve, reject, stepNumber)
	end)
end

-- Queue processor
task.spawn(function()
	game.Loaded:Wait() --? Experience needs to be loaded, otherwise will throw throttling error

	while true do
		local now = tick()

		for player, playerQueues in pairs(Queue) do
			for queueKey, actions in pairs(playerQueues) do
				if #actions <= 0 then
					continue
				end

				-- Rate-limiting
				do
					local lastExecution = (LastExecutionTime[player] and LastExecutionTime[player][queueKey]) or 0
					local cooldown = AnalyticsCooldowns[queueKey] or 0

					if now - lastExecution < cooldown then
						continue
					end
				end

				-- Remove first from queue
				local actionData = table.remove(actions, 1)
				if not actionData then
					continue
				end

				-- Check for step precedence
				do
					local stepKey = queueKey == "FunnelStep" and "HighestFunnelStep"
						or queueKey == "OnboardingFunnelStep" and "HighestOnboardingFunnelStep"

					local highestStepMap = queueKey == "FunnelStep" and HighestFunnelStep
						or queueKey == "OnboardingFunnelStep" and HighestOnboardingFunnelStep

					if not stepKey or not highestStepMap then
						continue
					end

					local currentStepNumber = actionData.stepNumber
					local highestStepNumber = highestStepMap[player] or 0
					local maxStepNumber = highestStepNumber

					-- Scan actions to determine maxStepNumber and remove lower steps
					for i = #actions, 1, -1 do
						local stepNumber = actions[i].stepNumber
						if stepNumber then
							if stepNumber > maxStepNumber then
								maxStepNumber = stepNumber
							elseif stepNumber < currentStepNumber then
								local droppedActionData = table.remove(actions, i)
								if not droppedActionData then
									continue
								end

								if droppedActionData.reject and typeof(droppedActionData.resolve) == "function" then
									droppedActionData.reject(
										`Step {currentStepNumber} is invalid because a step greater than or equal to this has already been logged.`
									)
								end
							end
						end
					end

					-- Skip processing if the current step is not the highest step in the queue
					if currentStepNumber <= maxStepNumber then
						if actionData.reject and typeof(actionData.resolve) == "function" then
							actionData.reject(
								`Step {currentStepNumber} is invalid because a step greater than or equal to this has already been logged.`
							)
						end

						continue
					end

					-- Update the highest step number
					highestStepMap[player] = currentStepNumber
				end

				-- Execute actions
				do
					local success, result = pcall(function()
						actionData.action()
					end)
					if success then
						if actionData.resolve and typeof(actionData.resolve) == "function" then
							actionData.resolve()
						end
					else
						if actionData.reject and typeof(actionData.resolve) == "function" then
							actionData.reject(result)
						end
					end
				end

				-- Update the last execution time
				if not LastExecutionTime[player] then
					LastExecutionTime[player] = {}
				end

				LastExecutionTime[player][queueKey] = now
			end
		end

		task.wait(0.1)
	end
end)

return module
