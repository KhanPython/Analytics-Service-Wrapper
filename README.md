<div align="center">
	<h1>Analytics Service Wrapper</h1>
  <p>A rate-limited Analytics Service wrapper for Roblox.</p>
</div>


### Features:

- **Server-wide token bucket:** Smoothly refills at Roblox's real rate limit (`120 + 20 * CCU` events/min) so bursts don't get dropped.
- **Self-stopping drain:** No permanent polling loop - a drain task only runs while the queue has work, then exits.
- **Economy event coalescing:** Identical economy events (same player/currency/transaction/SKU/fields) are summed and flushed every 5 seconds as a single call.
- **Funnel step precedence:** Out-of-order funnel steps are skipped with a warning instead of spamming AnalyticsService.
- **Fire-and-forget API:** Methods return nothing. Internal errors are logged via `warn`; validation errors surface as assertions.
- **Type-safe inputs:** Strict validation of custom fields, step numbers, and transaction types.

---

### Installation via Wally:

1. Ensure you have the [Wally package manager](https://github.com/UpliftGames/wally) installed on your system.
2. Add the following line to your `wally.toml` file under the `[dependencies]` section:
   ```toml
   analytics-service-wrapper = "khanpython/analytics-service@1.0.0"
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

This wrapper includes all methods provided by the default Analytics Service, with the exception to ProgressionEvents. For more detailed information on the available parameters, visit the official [Analytics Service Documentation](https://create.roblox.com/docs/reference/engine/classes/AnalyticsService#summary).

All methods are fire-and-forget - they return nothing. Invalid inputs raise an assertion (programmer error); runtime failures are logged internally with `warn`.

- **`LogCustomEvent(player, eventName, value?, customFields?)`**
  - Logs a custom event with optional value and custom fields.
- **`LogEconomyEvent(player, flowType, currencyType, amount, endingBalance, transactionType, itemSKU?, customFields?)`**
  - Logs an economy event, such as purchases or earnings. Coalesced and flushed in batches.
- **`LogFunnelStepEvent(player, funnelName, funnelSessionId?, stepNumber, stepName?, customFields?)`**
  - Logs a step in the funnel. If no `funnelSessionId` is provided, one is generated and cached per player.
- **`LogOnboardingFunnelStepEvent(player, stepNumber, stepName?, customFields?)`**
  - Logs a step in the onboarding funnel.
---

### Example Usage:

#### Log a custom event

```lua
AnalyticsWrapper:LogCustomEvent(player, "Item", nil, {
    CustomField01 = itemId,
})
```

#### Log a funnel step

```lua
-- Pass nil to auto-generate (and cache) a funnelSessionId per player.
AnalyticsWrapper:LogFunnelStepEvent(player, "LevelProgression", nil, 1, "LevelStart")
```

#### Log an economy event

```lua
AnalyticsWrapper:LogEconomyEvent(
    player,
    Enum.AnalyticsEconomyFlowType.Sink,
    "Coins",
    50,
    currentBalance - 50,
    Enum.AnalyticsEconomyTransactionType.Shop,
    "sword_001"
)
```

---
### FAQ:
1. **How are events processed?**

   Each event pulls a token from a server-wide bucket. If a token is available, the event fires immediately. Otherwise, it's queued and drained as tokens refill. The drain task stops as soon as the queue empties.

2. **How is rate limiting calculated?**

    The bucket follows Roblox's soft limit of `120 + (20 * CCU)` events per minute server-wide. Tokens refill continuously at `(120 + 20 * CCU) / 60` per second - no periodic "reset" that would cause bursts to fail.

3. **What happens under sustained overload?**

    The queue is bounded at 500 entries. If new events arrive past that, the oldest is dropped with a warning. In practice this should never trigger unless your project is firing events faster than the Roblox limit allows on average.

4. **How are economy events batched?**

    Events with the same `(player, currency, transactionType, itemSKU, customFields)` are summed into a single net delta and flushed every 5 seconds. This keeps a high-frequency economy from burning through the rate limit.

5. **What happens if a funnel step is logged out of sequence?**

    Only duplicate or backward steps are rejected. Any step `<=` the highest already logged for that `(funnelName, funnelSessionId)` pair (or for onboarding) is dropped with a warning. Skipping forward (e.g., `1` → `5`, then `5` → `50`) is accepted; the skipped numbers just show up as drop-off in the funnel report. Distinct funnels track step progression independently. See [Repeated steps](https://create.roblox.com/docs/production/analytics/funnel-events#repeated-steps) and [Skipped steps](https://create.roblox.com/docs/production/analytics/funnel-events#skipping-steps).

6. **What happens when a player leaves?**

    Pending economy buckets for that player are flushed best-effort (bypassing the token bucket) so the last <=5s of activity isn't silently lost. Any custom/funnel events still waiting in the queue for that player are dropped, and per-player state (funnel progress, cached session IDs) is cleared.

7. **What happens on server shutdown?**

    A `BindToClose` handler flushes all pending economy buckets and fires any remaining queued events best-effort before the server terminates. As with the leave path, the token bucket is bypassed since AnalyticsService enforces its own server-side soft limit.

---

### Resources:

- [Official Analytics Service Documentation](https://create.roblox.com/docs/reference/engine/classes/AnalyticsService#summary)
