<div align="center">
	<h1>Analytics Service Wrapper</h1>
  <p>A promise-based Analytics Service wrapper for Roblox.</p>
</div>


### Features:

- **Queuing System:** Ensures all analytics events are processed without throttling (FIFO-basis).
- **Promise-Based API:** Handles unexpected errors during execution, logging problems while maintaining overall service functionality.
- **Type Safe-Guarding**: Protects against invalid or malformed inputs, such as empty lists or incorrect data types, with strict validation mechanisms.

---

### Installation via Wally:

1. Ensure you have the [Wally package manager](https://github.com/UpliftGames/wally) installed on your system.
2. Add the following line to your `wally.toml` file under the `[dependencies]` section:
   ```toml
   analytics-service-wrapper = "khanpython/analytics-service@0.0.2"
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

This wrapper includes all methods provided by the default Analytics Service, with the exception of ProgressionEvents. For detailed information on the available parameters, visit the official [Analytics Service Documentation](https://create.roblox.com/docs/reference/engine/classes/AnalyticsService#summary).

- **`LogCustomEvent(player, eventName, value?, customFields?)`**
  - Logs a custom event with optional value and custom fields.
- **`LogEconomyEvent(player, flowType, currencyType, amount, endingBalance, transactionType, itemSKU?, customFields?)`**
  - Logs an economic event, such as purchases or earnings.
- **`LogFunnelStep(player, funnelName, funnelSessionId?, stepNumber, stepName?, customFields?)`**
  - Logs a step in the funnel. If no funnelSessionId is provided, then a GUID will be generated.
- **`LogOnboardingFunnelStep(player, stepNumber, stepName?, customFields?)`**
  - Logs a step in the onboarding funnel.
- **`AnalyticsWrapper:ForValues(callback, playerList)`**
  - Iterates through a list of players, executing a callback function for each. The callback must return a promise. Promise rejection here will not throw a rejection to the overall operation.
---

### Example Usage:

#### 1. Log a Funnel Step

```lua
AnalyticsWrapper:LogFunnelStep(player, "LevelProgression", 2, "LevelStart")
    :andThen(function()
        print("Funnel step logged successfully.")
    end)
    :catch(function(errMessage)
        warn("Error logging funnel step: " .. tostring(errMessage))
    end)
```

#### 2. Log Events for Multiple Players

```lua
AnalyticsWrapper:ForValues(function(player: Player)
        return AnalyticsWrapper:LogFunnelStep(player, "RoundProgression", 1, "Lobby")
    end, Players:GetPlayers())
    :catch(function(errMessage)
        warn("Unable to log funnel step: " .. tostring(errMessage))
    end)
```

---
### FAQ (WIP):
1. **How are actions processed from the queue?**
   
   A background loop runs continuously ensuring that For each player and event type:
   - The system checks if the cooldown for the event type has expired.
   - If the cooldown has expired, the first action in the queue is removed using table.remove.
   - The action is executed, and any success or failure is handled through the `resolve` or `reject` callbacks.
---
2. **How does rate-limiting work in the queue?**
   
    It attempts to adhere to the limits imposed by Roblox using `120 + (20 * CCU)`. The global CCU is retrieved using [`MessagingService`](https://create.roblox.com/docs/reference/cloud/messaging-service/v1) API. 

3. **What happens if a funnel step is logged out of sequence?**

    The wrapper ensures that funnel steps are logged in order of precedence. If a step number is less than or equal to the highest previously logged step for a specific `funnelSessionId` (if relevant), the wrapper will reject the action with an error message indicating the issue. This safeguard prevents duplicate or incorrect step logging. Read more on [Repeated steps](https://create.roblox.com/docs/production/analytics/funnel-events#repeated-steps) and [Skipped steps](https://create.roblox.com/docs/production/analytics/funnel-events#skipping-steps).
---
### Resources:

- [Promises and Why You Should Use Them](https://devforum.roblox.com/t/promises-and-why-you-should-use-them/350825)
- [Official Analytics Service Documentation](https://create.roblox.com/docs/reference/engine/classes/AnalyticsService#summary)