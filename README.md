# letterapp (Ruby)

[![Gem Version](https://img.shields.io/gem/v/letterapp)](https://rubygems.org/gems/letterapp)
[![License: MIT](https://img.shields.io/badge/License-MIT-green)](./LICENSE)

Official Ruby client for **[letter.app](https://letter.app)** - onboarding
email drip campaigns for product teams.

```bash
bundle add letterapp
# or: gem install letterapp
```

Requires Ruby **3.0+**. Zero runtime dependencies (standard library only).

## Quick start

```ruby
require "letterapp"

letter = Letterapp::Client.new(api_key: ENV["LETTER_API_KEY"]) # Dashboard -> Settings -> API keys

# Tell Letter who your user is (call where users sign up or log in).
letter.identify(
  user_id: "user_123",
  email: "alice@example.com",
  traits: { name: "Alice", plan: "free" }
)

# Report something they did.
letter.track(user_id: "user_123", event: "Signed Up", properties: { source: "web" })

# Required before the process exits so no events are lost.
letter.close
```

## Serverless (Lambda, Cloud Functions)

There is no background time to flush in a serverless handler, so set
`flush_at: 1` and `flush` at the end of each invocation:

```ruby
letter = Letterapp::Client.new(api_key: ENV["LETTER_API_KEY"], flush_at: 1)

def handler(event:, context:)
  letter.track(user_id: "user_123", event: "Checkout Started")
  letter.flush
end
```

## What it does

- **Auto-batching** - calls are queued and flushed every 100ms or 50 events by
  a background thread.
- **Retries** - `429` waits `Retry-After`; `5xx` and network errors back off
  exponentially with jitter, up to `max_retries` (default 3).
- **Idempotent** - every call gets a UUID `message_id` so retries are
  deduplicated server-side.
- **No dependencies** - HTTP over the standard library `net/http`.

## API

```ruby
Letterapp::Client.new(
  api_key:,
  base_url: "https://api.letter.app", # only set for self-hosted / local
  flush_at: 50,                        # 1 for serverless
  flush_interval: 0.1,                 # seconds
  max_retries: 3,
  open_timeout: 10,
  read_timeout: 10,
  on_error: nil                        # ->(error) for background errors
)

letter.identify(user_id:, email: nil, traits: nil, timezone: nil, timestamp: nil, message_id: nil)
letter.group(user_id:, account_id:, name: nil, traits: nil, timestamp: nil, message_id: nil)
letter.track(user_id:, event:, properties: nil, timestamp: nil, message_id: nil)
letter.flush # send queued calls now, block until done
letter.close # flush + stop the background thread (also runs at exit)
```

Configuration errors and non-retryable API responses raise `Letterapp::Error`
(with `#status` and `#body`). Background transport errors are passed to
`on_error` instead, since they cannot be raised to the caller.

## Full documentation

- **SDK reference:** <https://letter.app/docs/ruby-sdk>
- **Ingestion API:** <https://letter.app/docs/api>

## License

MIT - see [LICENSE](./LICENSE).
