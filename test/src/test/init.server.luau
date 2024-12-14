local Players = game:GetService("Players")
local Packages = script.Packages
local AnalyticsServiceWrapper = require(Packages["analytics-service"])

Players.PlayerAdded:Connect(function(player)
	warn("Started 2:")

	task.delay(10, function()
		for i = 1, 100 do
			AnalyticsServiceWrapper:LogFunnelStep(player, "RoundProgression", nil, i, "In the game")
				:andThen(function()
					warn("Resolved FunnelStep")
				end)
				:catch(function(err)
					warn(err)
				end)
		end

		for i = 1, 100 do
			AnalyticsServiceWrapper:LogOnboardingFunnelStep(player, i)
				:andThen(function()
					warn("Resolved OnboardingFunnelStep")
				end)
				:catch(function(err)
					warn(err)
				end)
		end
	end)
end)
