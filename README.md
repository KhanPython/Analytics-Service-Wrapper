<div align="center">
	<h1>Analytics Service Wrapper</h1>
  <p>A promise-based Analytics Service wrapper for Roblox.</p>
</div>


### Features:

- **Queuing System:** Ensures all analytics events are processed without throttling.
- **Promise-Based API:** Handles unexpected errors during execution, logging problems while maintaining overall service functionality.
- **Type Safe-Guarding**: Protects against invalid or malformed inputs, such as empty lists or incorrect data types, with strict validation mechanisms.

---

### Installation via Wally:

1. Ensure you have the [Wally package manager](https://github.com/UpliftGames/wally) installed on your system.
2. Add the following line to your `wally.toml` file under the `[dependencies]` section:
   ```toml
   analytics-service-wrapper = "khanpython/analytics-service-wrapper@1.2.0"
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
- **`LogOnboardingFunnelStep(player, stepNumber, stepName, customFields?)`**
  - Logs a step in the onboarding funnel.
- **`LogEconomyEvent(player, flowType, currencyType, amount, endingBalance, transactionType, itemSKU?, customFields?)`**
  - Logs an economic event, such as purchases or earnings.
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
### Resources:

- [Promises and Why You Should Use Them](https://devforum.roblox.com/t/promises-and-why-you-should-use-them/350825)
- [Official Analytics Service Documentation](https://create.roblox.com/docs/reference/engine/classes/AnalyticsService#summary)