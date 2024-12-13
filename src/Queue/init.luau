local Players = game:GetService("Players")
local module = {}

local GlobalCCU = require(script.GlobalCCU)
local Types = require(script.Parent.Types)

local Queue: Types.Queue = {}
local LastExecutionTime: { [Player]: { [Types.AnalyticsMethodNames]: number } } = {}
local CurrentRequestCount: number = 0
local LastResetTime: number = 0

function module:GetRequestCapacity(): number
	local currentCCU = GlobalCCU:Get()

	return math.max(1, 120 + (20 * currentCCU) - #Players:GetPlayers())
end

function module:TryResetReqeusts()
	--? Reset the global requests counter every minute
	if os.clock() - LastResetTime >= 60 then
		CurrentRequestCount = 0
		LastResetTime = os.clock()
	end
end

function module:AddToQueue(
	player: Player,
	queueKey: Types.AnalyticsMethodNames,
	action: () -> (),
	resolve: (() -> ())?,
	reject: ((string) -> ())?
)
	assert(
		player and typeof(player) == "Instance" and player:IsDescendantOf(Players),
		"Invalid parameter: `player` must be provided."
	)

	local capacity = self:GetRequestCapacity()
	-- Check if the action can be executed immediately, otherwise add to queue
	if self.CurrentRequestCount < capacity then
		self.CurrentRequestCount += 1
		local success, result = pcall(action)
		if success then
			if resolve then
				resolve()
			end
		else
			if reject then
				reject(result)
			end
		end
	else
		if not Queue[player] then
			Queue[player] = {}
		end

		local actions: Types.Actions = {
			action = action,
			resolve = resolve,
			reject = reject,
		}

		if not Queue[player][queueKey] then
			Queue[player][queueKey] = {}
		end

		table.insert(Queue[player][queueKey], actions)
	end
end

-- Queue processor
task.spawn(function()
	game.Loaded:Wait() -- Wait until the experience is loaded, otherwise a throttling error will be issued

	while true do
		module:TryResetReqeusts()

		local now = tick()

		for player, playerQueues in pairs(Queue) do
			for queueKey, actions in pairs(playerQueues) do
				if #actions <= 0 then
					continue
				end

				-- Allow at least 1 second per queue key, per event
				local lastExecution = (LastExecutionTime[player] and LastExecutionTime[player][queueKey]) or 0
				if now - lastExecution < 1 then
					continue
				end

				-- Check global capacity
				local capacity = module:GetRequestCapacity()
				if CurrentRequestCount >= capacity then
					continue
				end

				-- Remove first from queue
				local actionData = table.remove(actions, 1)
				if not actionData then
					continue
				end

				-- Execute action
				do
					local success, result = pcall(function()
						actionData.action()
					end)

					if success then
						if actionData.resolve then
							actionData.resolve()
						end
						CurrentRequestCount += 1
					else
						if actionData.reject then
							actionData.reject(result)
						end
					end
				end

				-- Update last execution time
				do
					if not LastExecutionTime[player] then
						LastExecutionTime[player] = {}
					end

					LastExecutionTime[player][queueKey] = now
				end
			end
		end

		task.wait(0.1)
	end
end)

return module
