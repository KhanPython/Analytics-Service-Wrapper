--!strict
-- Services
local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")

-- Dependencies
local Types = require(script.Parent.Types)
local createBucketKey = require(script.Parent.Util.createBucketKey)

-- Roblox AnalyticsService soft rate limit: ~120 + 20*CCU events per minute, server-wide.
local BASE_RATE_PER_MIN = 120
local PER_PLAYER_RATE_PER_MIN = 20
local ECONOMY_FLUSH_INTERVAL = 5
local DRAIN_INTERVAL = 0.25
local MAX_QUEUE_SIZE = 500

type EconomyBucket = {
	net: number,
	endingBalance: number?,
	transactionType: Types.EconomyTransactionType,
	itemSKU: string?,
	customFields: Types.CustomFields?,
}
type EconomyMap = { [Player]: { [string]: { [string]: EconomyBucket } } }

-- State (server-wide token bucket + bounded queue)
local tokens: number = BASE_RATE_PER_MIN
local lastRefill: number = os.clock()

-- Bounded FIFO backed by explicit head/tail indices so dequeue is O(1) instead of
-- the O(n) cost of table.remove(queue, 1). Occupied slots live in [queueHead, queueTail).
local queue: { Types.QueueObject } = {}
local queueHead: number = 1
local queueTail: number = 1
local pendingEconomy: EconomyMap = {}

-- Funnel step state is keyed by "<funnelName>|<funnelSessionId>" so distinct funnels
-- (or a re-used sessionId) cannot cross-contaminate step precedence.
local maxFunnelStep: { [Player]: { [string]: number } } = {}
local maxOnboardingStep: { [Player]: number } = {}
local drainActive: boolean = false
local economyFlushActive: boolean = false

-- Helpers
local function serverCap(): number
	return BASE_RATE_PER_MIN + PER_PLAYER_RATE_PER_MIN * #Players:GetPlayers()
end

local function refill()
	local now = os.clock()
	local dt = now - lastRefill
	lastRefill = now
	local cap = serverCap()
	tokens = math.min(tokens + dt * (cap / 60), cap)
end

local function tryConsumeToken(): boolean
	refill()
	local available = tokens >= 1
	tokens = available and (tokens - 1) or tokens
	return available
end

local function fire(item: Types.QueueObject)
	local ok, err = pcall(item.callBack)
	if not ok then
		warn(`[analytics-service] failed to log {item.eventType}: {err}`)
	end
end

local function resolveTransactionArg(tx: Types.EconomyTransactionType): string
	return (tx :: any).Name
end

local function fireBucket(player: Player, currencyType: string, bucket: EconomyBucket)
	local net = bucket.net
	if net == 0 then
		return
	end
	local flow = (net > 0) and Enum.AnalyticsEconomyFlowType.Source or Enum.AnalyticsEconomyFlowType.Sink
	local ok, err = pcall(
		AnalyticsService.LogEconomyEvent,
		AnalyticsService,
		player,
		flow,
		currencyType,
		math.abs(net),
		bucket.endingBalance or 0,
		resolveTransactionArg(bucket.transactionType),
		bucket.itemSKU,
		bucket.customFields
	)
	if not ok then
		warn(`[analytics-service] failed to log EconomyEvent: {err}`)
	end
end

local function flushEconomy()
	for player, playerMap in pendingEconomy do
		if not player:IsDescendantOf(Players) then
			pendingEconomy[player] = nil
			continue
		end

		for currencyType, bucketMap in playerMap do
			for key, bucket in bucketMap do
				if bucket.net == 0 then
					bucketMap[key] = nil
					continue
				end

				if not tryConsumeToken() then
					return
				end

				fireBucket(player, currencyType, bucket)
				bucketMap[key] = nil
			end

			if next(bucketMap) == nil then
				playerMap[currencyType] = nil
			end
		end

		if next(playerMap) == nil then
			pendingEconomy[player] = nil
		end
	end
end

-- Final-flush path (leave/shutdown): fires every pending bucket for a player
-- without consulting the token bucket, since the alternative is silent data loss.
-- AnalyticsService enforces its own soft limit server-side.
local function flushPlayerEconomy(player: Player)
	local playerMap = pendingEconomy[player]
	if not playerMap then
		return
	end
	for currencyType, bucketMap in playerMap do
		for _, bucket in bucketMap do
			fireBucket(player, currencyType, bucket)
		end
	end
	pendingEconomy[player] = nil
end

local function hasPendingEconomy(): boolean
	return next(pendingEconomy) ~= nil
end

local function scheduleEconomyFlush()
	if economyFlushActive then
		return
	end
	economyFlushActive = true
	task.delay(ECONOMY_FLUSH_INTERVAL, function()
		economyFlushActive = false
		flushEconomy()
		if hasPendingEconomy() then
			scheduleEconomyFlush()
		end
	end)
end

local function queueSize(): number
	return queueTail - queueHead
end

local function popQueueHead(): Types.QueueObject
	local item = queue[queueHead] :: Types.QueueObject
	queue[queueHead] = nil
	queueHead += 1
	-- Reset indices once empty so they don't grow unboundedly across a long session.
	if queueHead == queueTail then
		queueHead = 1
		queueTail = 1
	end
	return item
end

local function startDrain()
	if drainActive then
		return
	end
	drainActive = true
	task.spawn(function()
		while queueSize() > 0 do
			local item = queue[queueHead]
			if not item.player:IsDescendantOf(Players) then
				popQueueHead()
			elseif tryConsumeToken() then
				popQueueHead()
				fire(item)
			else
				task.wait(DRAIN_INTERVAL)
			end
		end
		drainActive = false
	end)
end

-- Module
local module = {}

function module:Add(data: Types.QueueObject)
	-- Step precedence for funnel events (reject earlier steps at enqueue time).
	if data.eventType == "FunnelStep" then
		local metaData = data.metaData :: Types.SteppedMetaData
		local player = data.player
		local funnelKey = `{metaData.funnelName}|{metaData.funnelSessionId}`
		local playerMap = maxFunnelStep[player]
		local prev = (playerMap and playerMap[funnelKey]) or 0

		if metaData.stepNumber <= prev then
			warn(
				`[analytics-service] skipped FunnelStep step {metaData.stepNumber} <= previous {prev} for funnel '{metaData.funnelName}' sessionId: {metaData.funnelSessionId}`
			)
			return
		end

		maxFunnelStep[player] = playerMap or {}
		maxFunnelStep[player][funnelKey] = metaData.stepNumber
	elseif data.eventType == "OnboardingFunnelStep" then
		local metaData = data.metaData :: Types.SteppedMetaData
		local player = data.player
		local prev = maxOnboardingStep[player] or 0

		if metaData.stepNumber <= prev then
			warn(`[analytics-service] skipped OnboardingFunnelStep step {metaData.stepNumber} <= previous {prev}`)
			return
		end

		maxOnboardingStep[player] = metaData.stepNumber
	end

	-- Bounded queue: drop the oldest item if we're full (rare under normal rates).
	if queueSize() >= MAX_QUEUE_SIZE then
		local dropped = popQueueHead()
		warn(`[analytics-service] queue overflow; dropped oldest event: {dropped.eventType}`)
	end

	queue[queueTail] = data
	queueTail += 1
	startDrain()
end

function module:AddEconomyEvent(data: Types.EconomyData)
	local player = data.player
	pendingEconomy[player] = pendingEconomy[player] or {}
	local currencyMap = pendingEconomy[player][data.currencyType]
	if not currencyMap then
		currencyMap = {}
		pendingEconomy[player][data.currencyType] = currencyMap
	end

	local key = createBucketKey(data.transactionType, data.itemSKU, data.customFields)
	local bucket = currencyMap[key]
	if not bucket then
		bucket = {
			net = 0,
			transactionType = data.transactionType,
			itemSKU = data.itemSKU,
			customFields = data.customFields,
		}
		currencyMap[key] = bucket
	end

	local delta = (data.flowType == Enum.AnalyticsEconomyFlowType.Source) and data.amount or -data.amount
	bucket.net += delta
	bucket.endingBalance = data.endingBalance

	scheduleEconomyFlush()
end

local function onPlayerAdded(player: Player)
	local connection: RBXScriptConnection
	connection = player.AncestryChanged:Connect(function()
		if player:IsDescendantOf(game) then
			return
		end
		connection:Disconnect()
		-- Flush coalesced economy events before discarding state; otherwise the
		-- last <=ECONOMY_FLUSH_INTERVAL seconds of activity is silently lost.
		flushPlayerEconomy(player)
		-- Compact the queue in place, skipping this player's events. O(size) but
		-- player-leave is cold path; keeps enqueue/dequeue O(1) everywhere else.
		local write = queueHead
		for read = queueHead, queueTail - 1 do
			local item = queue[read]
			if item.player ~= player then
				if write ~= read then
					queue[write] = item
				end
				write += 1
			end
		end
		for i = write, queueTail - 1 do
			queue[i] = nil
		end
		queueTail = write
		if queueHead == queueTail then
			queueHead = 1
			queueTail = 1
		end
		maxFunnelStep[player] = nil
		maxOnboardingStep[player] = nil
	end)
end

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)

local SHUTDOWN_FLUSH_GRACE = 2

game:BindToClose(function()
	-- Best-effort final flush: coalesced economy events first (most at-risk),
	-- then anything still waiting on tokens in the queue.
	for player in pendingEconomy do
		flushPlayerEconomy(player)
	end
	for i = queueHead, queueTail - 1 do
		fire(queue[i])
	end
	table.clear(queue)
	queueHead = 1
	queueTail = 1
	-- AnalyticsService batches events internally; yielding here keeps the server
	-- alive long enough for those batches to actually post before shutdown.
	-- Roblox grants BindToClose up to 30s; 2s is a conservative trade between
	-- shutdown latency and data integrity.
	task.wait(SHUTDOWN_FLUSH_GRACE)
end)

return module
