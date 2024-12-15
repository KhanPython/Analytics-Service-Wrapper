local Players = game:GetService("Players")
local Packages = script.Packages
local AnalyticsServiceWrapper = require(Packages["analytics-service"])

Players.PlayerAdded:Connect(function(player)
	warn("Started:")

	task.delay(10, function()
		for i = 1, 500 do
			AnalyticsServiceWrapper:LogCustomEvent(player, "Test", 1)
				:andThen(function()
					warn("Resolved CustomEvent")
				end)
				:catch(function(err)
					warn(err)
				end)
		end
	end)
end)
