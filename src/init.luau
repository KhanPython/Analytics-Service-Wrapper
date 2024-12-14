--!nonstrict
--!native

local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Promise = require(script.Parent.promise)
local Types = require(script.Types)
local Queue = require(script.Queue)

local PlayerFunnelSessionIds: { [Player]: string } = {}

local module = {}

local function validateCustomFields(customFields: Types.CustomFields?): boolean
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

function module:LogCustomEvent(player: Player, eventName: string, value: number?, customFields: Types.CustomFields?)
	return Promise.new(function(resolve, reject)
		assert(
			player and typeof(player) == "Instance" and player:IsDescendantOf(Players),
			"Invalid parameter: `player` must be provided."
		)
		assert(type(eventName) == "string", "Invalid parameter: `eventName` must be a string.")
		assert(value == nil or typeof(value) == "number", "Invalid parameter: `value` must be a number.")
		assert(validateCustomFields(customFields), "Invalid `customFields`.")

		Queue:AddToQueue(player, "CustomEvent", {
			callBack = function()
				AnalyticsService:LogCustomEvent(player, eventName, value or 1, customFields)
			end,
			resolve = resolve,
			reject = reject,
		})
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
	return Promise.new(function(resolve, reject)
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

		Queue:AddToQueue(player, "EconomyEvent", {
			callBack = function()
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
			end,
			resolve = resolve,
			reject = reject,
		})
	end)
end

function module:LogFunnelStep(
	player: Player,
	funnelName: string,
	funnelSessionId: string?,
	stepNumber: number,
	stepName: string?,
	customFields: Types.CustomFields?
)
	return Promise.new(function(resolve, reject)
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

		-- Create a new funnel sessionId, if none was provided
		if not funnelSessionId then
			funnelSessionId = PlayerFunnelSessionIds[player]

			if not funnelSessionId then
				funnelSessionId = HttpService:GenerateGUID(false)
				PlayerFunnelSessionIds[player] = funnelSessionId
			end
		end

		Queue:AddToQueue(player, "FunnelStep", {
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
		}, {
			stepNumber = stepNumber,
			funnelSessionId = funnelSessionId,
		})
	end)
end

function module:LogOnboardingFunnelStep(
	player: Player,
	stepNumber: number,
	stepName: string?,
	customFields: Types.CustomFields?
)
	return Promise.new(function(resolve, reject)
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

		Queue:AddToQueue(player, "OnboardingFunnelStep", {
			callBack = function()
				AnalyticsService:LogOnboardingFunnelStepEvent(player, stepNumber, stepName or "", customFields)
			end,
			resolve = resolve,
			reject = reject,
		}, {
			stepNumber = stepNumber,
		})
	end)
end

return module
