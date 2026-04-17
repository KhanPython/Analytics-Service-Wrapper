# Changelog

## 1.0.0

### Breaking Changes
- API is now fire-and-forget. Methods no longer return Promises
- Removed `evaera/promise` dependency
- Replaced per-player budget system with a server-wide token bucket rate limiter (`120 + 20 * CCU` per minute, continuous refill)

### Added
- Economy event coalescing. Now it batches identical economy events (same player, currency, transaction type, SKU, custom fields) into net deltas that are flushed every 5 seconds
- Bounded queue (500 max) with self-stopping drain loop that exits when empty
- `EconomyTransactionType` now accepts `{ Name: string }` tables in addition to the enum
- `game:BindToClose` handler that flushes pending economy buckets and remaining queued events on shutdown
- New utility modules: `createBucketKey`, `serializeCustomFields`

### Changed
- Processor rewritten from class-based Queue with periodic budget reset to token bucket with continuous drain
- Funnel step precedence checks moved to enqueue time with `warn` instead of Promise rejection
- Funnel step precedence is now keyed by `(funnelName, funnelSessionId)` so distinct funnels can no longer reject each other's steps
- Auto-generated `funnelSessionId`s are cached per `(player, funnelName)` instead of one cache slot per player
- Economy bucket keys now discriminate `Enum.AnalyticsEconomyTransactionType` from `{ Name = "..." }` tables, so matching `.Name` strings across the two forms don't collide into one bucket
- Drain loop checks player descendancy before consuming a token, so events for a departed player don't waste budget
- Queue is now backed by explicit head/tail indices, making enqueue and dequeue O(1) (was O(n) on dequeue via `table.remove(queue, 1)`)
- Player-leave now flushes any coalesced-but-unsent economy buckets for that player before discarding state, preventing silent data loss for the last <=5s of activity
- Queue overflow warning now reports the dropped event type
