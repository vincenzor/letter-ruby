# Changelog

## 0.2.3 - 2026-11-03

### Fixed

- A Rails app configured as the README says now boots.
  `config.action_mailer.letter_settings = { ... }` raised
  `NoMethodError: undefined method 'letter_settings=' for class
  ActionMailer::Base` as soon as ActionMailer::Base loaded: during boot with
  eager loading (production, `assets:precompile`), otherwise on the first
  mail sent. The gem added `:letter` from a Railtie initializer that ran
  after Action Mailer's own, so the settings were applied before
  `letter_settings=` existed. The gem now registers the delivery method when
  it is required, ahead of Action Mailer's initializer, and the Railtie is
  gone. Apps that worked around this by dropping `letter_settings` and
  relying on `ENV["LETTER_API_KEY"]` keep working.

## 0.2.2 - 2026-10-25

### Fixed

- Sending mail through the `:letter` ActionMailer delivery method no longer
  leaks a thread per message. `Client.new` started the batching thread, and
  registered an `at_exit` hook holding the client, even for a client that
  only calls `send_email`; Mail builds a new delivery method, and so a new
  client, for every message. A long-running process kept one idle thread and
  one client per email sent. The thread now starts with the first `identify`,
  `group` or `track` call.
- A client created before a fork (a Rails initializer under Puma cluster mode
  or Solid Queue) now sends from the forked process as usual. The child
  inherited a dead copy of the parent's thread, so its `identify`, `group` and
  `track` calls waited in the queue until the process exited. The client now
  starts a new thread when the old one is dead.

## 0.2.1 - 2026-10-25

### Fixed

- `Letterapp::Client` no longer breaks Active Support's `present?`, `blank?`
  and `presence`. 0.2.0 had a private `blank?(value)` helper that shadowed
  `Object#blank?`, so in a Rails app `client.present?` and `client.presence`
  raised `ArgumentError: wrong number of arguments (given 0, expected 1)`, and
  `client.blank?` raised `NoMethodError`. The helper is now named `missing?`.

## 0.2.0 - 2026-08-20

### Added

- `send_email` for transactional email (`POST /v1/send`), with
  `idempotency_key:` for replay-safe retries.
- `Letterapp::DeliveryMethod`, registered as `:letter` with ActionMailer in a
  Rails app.
- `Letterapp::Error#code` and `#reason`, from the API's error body.

## 0.1.0 - 2026-05-29

- First release: `identify`, `group` and `track`, auto-batched in the
  background, with retries and idempotent message IDs.
