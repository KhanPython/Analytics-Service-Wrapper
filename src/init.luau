--!strict

local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Types = require(script.Types)
local Processor = require(script.Processor)

local CUSTOM_FIELD_KEYS = { "CustomField01", "CustomField02", "CustomField03" }

local playerFunnelSessionIds: { [Player]: { [string]: string } } = {}

local function trackFunnelSession(player: Player)
	local connection: RBXScriptConnection
	connection = player.AncestryChanged:Connect(function()
		if player:IsDescendantOf(game) then
			return
		end
		connection:Disconnect()
		playerFunnelSessionIds[player] = nil
	end)
end

for _, player in Players:GetPlayers() do
	trackFunnelSession(player)
end
Players.PlayerAdded:Connect(trackFunnelSession)

local function isValidPlayer(player: Player?): boolean
	return player ~= nil and typeof(player) == "Instance" and (player :: Player):IsDescendantOf(Players)
end

local function validateCustomFields(customFields: Types.CustomFields?): boolean
	if not customFields then
		return true
	end
	for key, value in customFields do
		if not table.find(CUSTOM_FIELD_KEYS, key) then
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

local module = {}

function module:LogCustomEvent(
	player: Player,
	eventName: string,
	value: number?,
	customFields: Types.CustomFields?
)
	assert(isValidPlayer(player), "Invalid parameter: `player` must be a valid Player.")
	assert(typeof(eventName) == "string", "Invalid parameter: `eventName` must be a string.")
	assert(value == nil or typeof(value) == "number", "Invalid parameter: `value` must be a number.")
	assert(validateCustomFields(customFields), "Invalid `customFields`.")

	Processor:Add({
		player = player,
		eventType = "CustomEvent",
		callBack = function()
			AnalyticsService:LogCustomEvent(player, eventName, value or 1, customFields)
		end,
	})
end

function module:LogEconomyEvent(
	player: Player,
	flowType: Enum.AnalyticsEconomyFlowType,
	currencyType: string,
	amount: number,
	endingBalance: number,
	transactionType: Types.EconomyTransactionType,
	itemSKU: string?,
	customFields: Types.CustomFields?
)
	assert(isValidPlayer(player), "Invalid parameter: `player` must be a valid Player.")
	assert(typeof(flowType) == "EnumItem", "Invalid parameter: `flowType` must be an Enum.AnalyticsEconomyFlowType.")
	assert(typeof(currencyType) == "string", "Invalid parameter: `currencyType` must be a string.")
	assert(typeof(amount) == "number", "Invalid parameter: `amount` must be a number.")
	assert(
		typeof(endingBalance) == "number" and endingBalance >= 0,
		"Invalid parameter: `endingBalance` must be a non-negative number."
	)
	assert(
		typeof(transactionType) == "EnumItem"
			or (typeof(transactionType) == "table" and (transactionType :: any).Name ~= nil),
		"Invalid parameter: `transactionType` must be an Enum.AnalyticsEconomyTransactionType or `{ Name = string }`."
	)
	assert(validateCustomFields(customFields), "Invalid `customFields`.")

	Processor:AddEconomyEvent({
		player = player,
		flowType = flowType,
		currencyType = currencyType,
		amount = math.abs(amount),
		endingBalance = math.max(endingBalance, 0),
		transactionType = transactionType,
		itemSKU = itemSKU,
		customFields = customFields,
	})
end

function module:LogFunnelStepEvent(
	player: Player,
	funnelName: string,
	funnelSessionId: string?,
	stepNumber: number,
	stepName: string?,
	customFields: Types.CustomFields?
)
	assert(isValidPlayer(player), "Invalid parameter: `player` must be a valid Player.")
	assert(typeof(funnelName) == "string", "Invalid parameter: `funnelName` must be a string.")
	assert(
		funnelSessionId == nil or typeof(funnelSessionId) == "string",
		"Invalid parameter: `funnelSessionId` must be a string."
	)
	assert(
		typeof(stepNumber) == "number" and stepNumber >= 1 and stepNumber <= 100,
		"Invalid parameter: `stepNumber` must be between 1-100."
	)
	assert(stepName == nil or typeof(stepName) == "string", "Invalid parameter: `stepName` must be a string.")
	assert(validateCustomFields(customFields), "Invalid `customFields`.")

	local perFunnel = playerFunnelSessionIds[player]
	local cached = perFunnel and perFunnel[funnelName]
	local sessionId = funnelSessionId or cached or HttpService:GenerateGUID(false)
	if not funnelSessionId and not cached then
		perFunnel = perFunnel or {}
		perFunnel[funnelName] = sessionId
		playerFunnelSessionIds[player] = perFunnel
	end

	Processor:Add({
		player = player,
		eventType = "FunnelStep",
		callBack = function()
			AnalyticsService:LogFunnelStepEvent(player, funnelName, sessionId, stepNumber, stepName or "", customFields)
		end,
		metaData = {
			stepNumber = stepNumber,
			funnelName = funnelName,
			funnelSessionId = sessionId,
		},
	})
end

function module:LogOnboardingFunnelStepEvent(
	player: Player,
	stepNumber: number,
	stepName: string?,
	customFields: Types.CustomFields?
)
	assert(isValidPlayer(player), "Invalid parameter: `player` must be a valid Player.")
	assert(
		typeof(stepNumber) == "number" and stepNumber >= 1 and stepNumber <= 100,
		"Invalid parameter: `stepNumber` must be between 1-100."
	)
	assert(stepName == nil or typeof(stepName) == "string", "Invalid parameter: `stepName` must be a string.")
	assert(validateCustomFields(customFields), "Invalid `customFields`.")

	Processor:Add({
		player = player,
		eventType = "OnboardingFunnelStep",
		callBack = function()
			AnalyticsService:LogOnboardingFunnelStepEvent(player, stepNumber, stepName or "", customFields)
		end,
		metaData = {
			stepNumber = stepNumber,
		},
	})
end

return module
