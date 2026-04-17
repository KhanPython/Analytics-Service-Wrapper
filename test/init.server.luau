local Players = game:GetService("Players")
local AnalyticsService = require(script.AnalyticsService)

Players.PlayerAdded:Connect(function(player: Player)
	task.wait(5) -- Otherwise will throttle the AS
	warn("Started:")

	for i = 1, 120 do
		local ok, err = pcall(function()
			AnalyticsService:LogCustomEvent(player, "test", 1)
		end)
		warn(ok and "Done" or err)
		task.wait()
	end

	for i = 1, 100 do
		local ok, err = pcall(function()
			AnalyticsService:LogFunnelStepEvent(player, "LevelProgression", nil, i, "LevelStart")
		end)
		warn(ok and "Done" or err)
		task.wait()
	end

	-- Distinct funnel name -> independent step tracking. Should accept all 100
	-- steps (would be rejected as duplicates if the (funnelName, sessionId) keying
	-- were broken).
	for i = 1, 100 do
		local ok, err = pcall(function()
			AnalyticsService:LogFunnelStepEvent(player, "TutorialQuest", nil, i, "QuestStep")
		end)
		warn(ok and "Done" or err)
		task.wait()
	end
end)
