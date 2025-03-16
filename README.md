<div align="center">
	<h1>Analytics Service Wrapper</h1>
  <p>A promise-based Analytics Service wrapper for Roblox.</p>
</div>


### Features:

- **Queuing System:** Ensures all analytics events are processed without exceeding Roblox's Analytics Service limits.
- **Promise-Based API:** Handles unexpected errors during execution, logging problems while maintaining overall service functionality.
- **Type Safe-Guarding**: Protects against invalid or malformed inputs, such as empty lists or incorrect data types, with strict validation mechanisms.

---

### Installation via Wally:

1. Ensure you have the [Wally package manager](https://github.com/UpliftGames/wally) installed on your system.
2. Add the following line to your `wally.toml` file under the `[dependencies]` section:
   ```toml
   analytics-service-wrapper = "khanpython/analytics-service@0.0.7"
   ```
3. Run the Wally install command to download and integrate the package:
    ```bash
    wally install
    ```
4. The package will be placed in your Packages folder. Use the following code snippet to require it in your project:
    ```lua
    local AnalyticsServiceWrapper = require(path-to-package)
    ```

---


### Methods:

This wrapper includes all methods provided by the default Analytics Service, with the exception to ProgressionEvents. For a more detailed information on the available parameters, visit the official [Analytics Service Documentation](https://create.roblox.com/docs/reference/engine/classes/AnalyticsService#summary).

- **`LogCustomEvent(player, eventName, value?, customFields?)`**
  - Logs a custom event with optional value and custom fields.
- **`LogEconomyEvent(player, flowType, currencyType, amount, endingBalance, transactionType, itemSKU?, customFields?)`**
  - Logs an economic event, such as purchases or earnings.
- **`LogFunnelStepEvent(player, funnelName, funnelSessionId?, stepNumber, stepName?, customFields?)`**
  - Logs a step in the funnel. If no funnelSessionId is provided, then a GUID will be generated.
- **`LogOnboardingFunnelStepEvent(player, stepNumber, stepName?, customFields?)`**
  - Logs a step in the onboarding funnel.
---

### Example Usage:

#### Log a Funnel Step

```lua
local yourFunnelSessionId = path or nil -- Leave nil if you want an automatically generated funnelSessionId assigned to the player
AnalyticsWrapper:LogFunnelStepEvent(player, "LevelProgression", nil, 1, "LevelStart")
    :andThen(function()
        print("Funnel step logged successfully.")
    end)
    :catch(function(errMessage)
        warn("Error logging funnel step: " .. tostring(errMessage))
    end)
```

---
### FAQ:
1. **How are events processed?**
   
   Events are processed immediately if the current request count is below the calculated budget (140 calls per player). If the request count exceeds the budget, the event is added to the queue.

2. **How does the queuing work?**
   
   A background task continuously processes events from the queue. At each step:
    - It refreshes the request count every 30 seconds.
    - If the budget allows, the next event in the queue is processed.
    - Errors during processing are caught and logged, and the event is rejected.

3. **How is the budgeting calculated in the queue?**
   
    It attempts to adhere to the limits imposed by Roblox using the `120 + (20 * CCU)` formula at `140` calls every 30 seconds. 

4. **What happens if a funnel step is logged out of sequence?**

    The wrapper ensures that funnel steps are logged in order of precedence. If a step number is less than or equal to the highest previously logged step for a specific `funnelSessionId` (if relevant), the wrapper will reject the action. Read more on [Repeated steps](https://create.roblox.com/docs/production/analytics/funnel-events#repeated-steps) and [Skipped steps](https://create.roblox.com/docs/production/analytics/funnel-events#skipping-steps).
---
### Resources:

- [Promises and Why You Should Use Them](https://devforum.roblox.com/t/promises-and-why-you-should-use-them/350825)
- [Official Analytics Service Documentation](https://create.roblox.com/docs/reference/engine/classes/AnalyticsService#summary)