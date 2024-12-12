--!nonstrict

-- Services
local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

-- Dependencies
local Promise = require(script.Parent.promise)

-- Types
export type FunnelSessions = { [number]: string }
export type CustomFieldNames = "CustomField01" | "CustomField02" | "CustomField03"
export type CustomFields = { [CustomFieldNames]: string }
export type AnalyticsMethodNames = "CustomEvent" | "FunnelStep" | "EconomyEvent" | "OnboardingFunnelStep"

-- Queues and Analytics Cooldowns
local Queue: { [Player]: { [AnalyticsMethodNames]: { { action: () -> (), resolve: (() -> ())?, reject: ((string) -> ())? } } } } =
	{}

local AnalyticsCooldowns: { [AnalyticsMethodNames]: number } = {
	CustomEvent = 0.5, -- 2 events per second, per player
	FunnelStep = 1, -- 1 event per second, per player
	EconomyEvent = 1,
	OnboardingFunnelStep = 1,
}

local LastExecutionTime: { [Player]: { [AnalyticsMethodNames]: number } } = {}
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
	queueName: AnalyticsMethodNames,
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

	if not Queue[player][queueName] then
		Queue[player][queueName] = {}
	end

	table.insert(Queue[player][queueName], {
		action = action,
		resolve = resolve,
		reject = reject,
	})
end

-- Initialize a new funnel session for a player
function module:_StartFunnelSession(player: Player): string?
	assert(
		player and typeof(player) == "Instance" and player:IsDescendantOf(Players),
		"Invalid parameter: `player` must be provided."
	)

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
		assert(type(promiseCallback) == "function", "Invalid `promiseCallback` provided.")
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
		self:_AddToQueue(player, "CustomEvent", function()
			assert(
				player and typeof(player) == "Instance" and player:IsDescendantOf(Players),
				"Invalid parameter: `player` must be provided."
			)

			assert(type(eventName) == "string", "Invalid parameter: `eventName` must be a string.")
			assert(validateCustomFields(customFields), "Invalid `customFields`.")

			AnalyticsService:LogCustomEvent(player, eventName, value or 1, customFields)
		end, resolve, reject)
	end)
end

function module:LogOnboardingFunnelStep(
	player: Player,
	stepNumber: number,
	stepName: string,
	customFields: CustomFields?
)
	return Promise.new(function(resolve, reject)
		self:_AddToQueue(player, "OnboardingFunnelStep", function()
			assert(type(stepNumber) == "number", "Invalid parameter: `stepNumber` must be a number.")
			assert(type(stepName) == "string", "Invalid parameter: `stepName` must be a string.")
			assert(validateCustomFields(customFields), "Invalid `customFields`.")

			AnalyticsService:LogOnboardingFunnelStepEvent(player, stepNumber, stepName, customFields)
		end, resolve, reject)
	end)
end

function module:LogFunnelStep(
	player: Player,
	funnelName: string,
	stepNumber: number,
	stepName: string,
	customFields: CustomFields?
)
	return Promise.new(function(resolve, reject)
		self:_AddToQueue(player, "FunnelStep", function()
			assert(type(funnelName) == "string", "Invalid parameter: `funnelName` must be a string.")
			assert(type(stepNumber) == "number", "Invalid parameter: `stepNumber` must be a number.")
			assert(type(stepName) == "string", "Invalid parameter: `stepName` must be a string.")
			assert(validateCustomFields(customFields), "Invalid `customFields`.")

			local funnelSessionId = self:_GetFunnelSession(player)
			if not funnelSessionId then
				funnelSessionId = self:_StartFunnelSession(player)
			end

			AnalyticsService:LogFunnelStepEvent(player, funnelName, funnelSessionId, stepNumber, stepName, customFields)
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
		self:_AddToQueue(player, "EconomyEvent", function()
			assert(
				flowType == nil or typeof(flowType) == "EnumItem",
				"Invalid parameter: `flowType` must be an Enum.AnalyticsEconomyFlowType or nil for default dynamic determination."
			)
			assert(type(currencyType) == "string", "Invalid parameter: `currencyType` must be a string.")
			assert(
				type(amount) == "number" and amount >= 0,
				"Invalid parameter: `amount` must be a non-negative number."
			)
			assert(
				type(endingBalance) == "number" and endingBalance >= 0,
				"Invalid parameter: `endingBalance` must be a non-negative number."
			)
			assert(
				type(transactionType) == "table" and transactionType.Name ~= nil
					or typeof(transactionType) == "EnumItem",
				"Invalid parameter: `transactionType` must be an Enum.AnalyticsEconomyTransactionType or a table with a `Name` field."
			)
			assert(validateCustomFields(customFields), "Invalid `customFields`.")

			if not flowType then
				flowType = amount < 0 and Enum.AnalyticsEconomyFlowType.Sink or Enum.AnalyticsEconomyFlowType.Source
			end
			amount = math.abs(amount)
			endingBalance = math.max(endingBalance, 0)

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

-- Queue processor
task.spawn(function()
	game.Loaded:Wait() --? Experience needs to be loaded, otherwise will throw throttling error

	while true do
		for player, playerQueues in pairs(Queue) do
			for queueName, actions in pairs(playerQueues) do
				if #actions <= 0 then
					continue
				end

				local now = tick()
				local lastExecution = (LastExecutionTime[player] and LastExecutionTime[player][queueName]) or 0
				local cooldown = AnalyticsCooldowns[queueName] or 0

				if now - lastExecution < cooldown then
					continue
				end

				local actionData = table.remove(actions, 1)
				if not actionData then
					continue
				end

				local success, result = pcall(function()
					actionData.action()
				end)

				if success then
					if actionData.resolve then
						actionData.resolve()
					end
				else
					if actionData.reject then
						actionData.reject(result)
					end
				end

				-- Update the last execution time
				if not LastExecutionTime[player] then
					LastExecutionTime[player] = {}
				end
				LastExecutionTime[player][queueName] = now
			end
		end

		task.wait(0.1)
	end
end)

return module
