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

## Transactional email

`send_email` mails one person right now: a receipt, a password reset, a
verification link. It is never batched and never waits for `flush`.

```ruby
result = letter.send_email(
  to: "alice@example.com",
  subject: "Reset your password",
  html: "<p>Click <a href='https://...'>here</a> to reset.</p>",
  tag: "password-reset",
  idempotency_key: "password-reset:#{token}"
)

result["messageId"] # provider id, appears in delivery events
```

It's `send_email` and not `send` because `Object#send` is Ruby's dynamic
dispatch; shadowing it would break metaprogramming in the host app.

Only `to:`, `subject:` and one of `html:` / `text:` are required. `from:`
defaults to the project's sender and must be on a verified domain. A
plain-text part is derived from the HTML when you don't supply one.

Pass an `idempotency_key:` whenever the call can be retried (a job with
retries, a webhook handler): a replay returns the original send rather than
mailing the recipient twice, and it's what lets the SDK retry a `5xx` safely.

Failures raise `Letterapp::Error` with `#status`, `#code` and `#reason`. The
reason is what tells "this recipient is unreachable" apart from "our account
is blocked":

```ruby
begin
  letter.send_email(to: to, subject: subject, html: html)
rescue Letterapp::Error => e
  raise unless e.reason == "suppressed" # hard-bounced or complained; nothing to fix
end
```

Transactional mail ignores marketing unsubscribes (an opted-out user still
gets their password reset) but respects bounces, complaints, and addresses
suppressed by hand.

### Rails

The gem registers `:letter` as an ActionMailer delivery method, so switching
providers is two lines of config. Every existing mailer, view, and
`deliver_later` keeps working unchanged.

```ruby
# config/environments/production.rb
config.action_mailer.delivery_method = :letter
config.action_mailer.letter_settings = { api_key: ENV["LETTER_API_KEY"] }
```

HTML and text parts map straight through. A message with several recipients
becomes one send each, so everyone gets their own log row and bounce.
Attachments raise, rather than being dropped silently, since the transactional
API doesn't carry them.

## What it does

- **Auto-batching** - `identify` / `group` / `track` are queued and flushed
  every 100ms or 50 events by a background thread. `send_email` always goes out
  immediately.
- **Retries** - `429` waits `Retry-After`; `5xx` and network errors back off
  exponentially with jitter, up to `max_retries` (default 3). A `send_email`
  without an `idempotency_key` is never retried, since a duplicate email is
  worse than a failed one.
- **Idempotent** - every ingestion call gets a UUID `message_id` so retries are
  deduplicated server-side; `send_email` takes your own key.
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
letter.send_email(to:, subject:, html: nil, text: nil, from: nil, from_name: nil,
                  reply_to: nil, headers: nil, tag: nil, metadata: nil,
                  idempotency_key: nil) # => Hash, sent immediately
letter.flush # send queued calls now, block until done
letter.close # flush + stop the background thread (also runs at exit)
```

Configuration errors and non-retryable API responses raise `Letterapp::Error`
(with `#status`, `#code`, `#reason` and `#body`). Background transport errors
are passed to `on_error` instead, since they cannot be raised to the caller.

## Full documentation

- **SDK reference:** <https://letter.app/docs/ruby-sdk>
- **Ingestion API:** <https://letter.app/docs/api>
- **Transactional API:** <https://letter.app/docs/transactional>

## License

MIT - see [LICENSE](./LICENSE).
