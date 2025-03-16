--!strict

local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Promise = require(script.Parent.promise)
local Types = require(script.Types)
local Processor = require(script.Processor)

local PlayerFunnelSessionIds: { [Player]: string } = {}

local module = {}

function validateCustomFields(customFields: Types.CustomFields?): boolean
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

function module:LogCustomEvent(player: Player, eventName: string, value: number?, customFields: Types.CustomFields?)
	return Promise.new(function(resolve, reject, onCancel)
		assert(
			player and typeof(player) == "Instance" and player:IsDescendantOf(Players),
			"Invalid parameter: `player` must be provided."
		)
		assert(type(eventName) == "string", "Invalid parameter: `eventName` must be a string.")
		assert(value == nil or typeof(value) == "number", "Invalid parameter: `value` must be a number.")
		assert(validateCustomFields(customFields), "Invalid `customFields`.")

		local data = {
			player = player,
			eventType = "CustomEvent",
			actions = {
				callBack = function()
					AnalyticsService:LogCustomEvent(player, eventName, value or 1, customFields)
				end,
				resolve = resolve,
				reject = reject,
			},
		} :: Types.QueueObject

		onCancel(function()
			Processor:TryRemove(data)
		end)

		Processor:Add(data)
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
	customFields: Types.CustomFields?
)
	return Promise.new(function(resolve, reject, onCancel)
		assert(
			player and typeof(player) == "Instance" and player:IsDescendantOf(Players),
			"Invalid parameter: `player` must be provided."
		)
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

		local data = {
			player = player,
			eventType = "EconomyEvent",
			actions = {
				callBack = function()
					AnalyticsService:LogEconomyEvent(
						player,
						flowType,
						currencyType,
						amount,
						endingBalance,
						transactionType.Name,
						itemSKU,
						customFields
					)
				end,
				resolve = resolve,
				reject = reject,
			},
		} :: Types.QueueObject

		onCancel(function()
			Processor:TryRemove(data)
		end)

		Processor:Add(data)
	end)
end

function module:LogFunnelStepEvent(
	player: Player,
	funnelName: string,
	funnelSessionId: string?,
	stepNumber: number,
	stepName: string?,
	customFields: Types.CustomFields?
)
	return Promise.new(function(resolve, reject, onCancel)
		assert(
			player and typeof(player) == "Instance" and player:IsDescendantOf(Players),
			"Invalid parameter: `player` must be provided."
		)
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

		-- Retrieve or create a `funnelSessionId`, if none was provided
		if not funnelSessionId then
			funnelSessionId = PlayerFunnelSessionIds[player]

			if not funnelSessionId then
				funnelSessionId = HttpService:GenerateGUID(false)
				PlayerFunnelSessionIds[player] = funnelSessionId
			end
		end

		local data = {
			player = player,
			eventType = "FunnelStep",
			actions = {
				callBack = function()
					AnalyticsService:LogFunnelStepEvent(
						player,
						funnelName,
						funnelSessionId,
						stepNumber,
						stepName or "",
						customFields
					)
				end,
				resolve = resolve,
				reject = reject,
			},
			metaData = {
				stepNumber = stepNumber,
				funnelSessionId = funnelSessionId,
			},
		} :: Types.QueueObject

		onCancel(function()
			Processor:TryRemove(data)
		end)

		Processor:Add(data)
	end)
end

function module:LogOnboardingFunnelStepEvent(
	player: Player,
	stepNumber: number,
	stepName: string?,
	customFields: Types.CustomFields?
)
	return Promise.new(function(resolve, reject, onCancel)
		assert(
			player and typeof(player) == "Instance" and player:IsDescendantOf(Players),
			"Invalid parameter: `player` must be provided."
		)
		assert(
			typeof(stepNumber) == "number" and (stepNumber >= 1 and stepNumber <= 100),
			"Invalid parameter: `stepNumber` must be a positive number between 1-100."
		)
		assert(stepName == nil or typeof(stepName) == "string", "Invalid parameter: `stepName` must be a string.")
		assert(validateCustomFields(customFields), "Invalid `customFields`.")

		local data = {
			player = player,
			eventType = "OnboardingFunnelStep",
			actions = {
				callBack = function()
					AnalyticsService:LogOnboardingFunnelStepEvent(player, stepNumber, stepName or "", customFields)
				end,
				resolve = resolve,
				reject = reject,
			},
			metaData = {
				stepNumber = stepNumber,
			},
		} :: Types.QueueObject

		onCancel(function()
			Processor:TryRemove(data)
		end)

		Processor:Add(data)
	end)
end

return module
