local Players = game:GetService("Players")
local AnalyticsService = require(script.AnalyticsService)

Players.PlayerAdded:Connect(function(player: Player)
	task.wait(5) -- Otherwise will throttle the AS
	warn("Started:")

	for i = 1, 120 do
		AnalyticsService:LogCustomEvent(player, "test", 1)
			:andThen(function()
				warn("Done")
			end)
			:catch(function(errMessage)
				warn(errMessage)
			end)

		task.wait()
	end

	for i = 1, 101 do
		AnalyticsService:LogFunnelStepEvent(player, "LevelProgression", nil, i, "LevelStart")
			:andThen(function()
				warn("Done")
			end)
			:catch(function(errMessage)
				warn(errMessage)
			end)

		task.wait()
	end

	for i = 1, 101 do
		AnalyticsService:LogFunnelStepEvent(player, "LevelProgression", nil, i, "LevelStart")
			:andThen(function()
				warn("Done")
			end)
			:catch(function(errMessage)
				warn(errMessage)
			end)

		task.wait()
	end
end)
