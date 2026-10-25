# frozen_string_literal: true

require "json"
require "net/http"
require "securerandom"
require "time"
require "uri"

require_relative "version"

module Letterapp
  DEFAULT_BASE_URL = "https://api.letter.app"

  # Raised for client misconfiguration and non-retryable API errors.
  #
  # +code+ is the API's machine-readable error code (bad_request, forbidden,
  # ...). +reason+ is the finer-grained cause when a send was refused
  # (suppressed, account_suspended, email_quota_exceeded, daily_cap,
  # billing_required, provider_rejected), which is what tells "this one
  # recipient is unreachable" apart from "our account is blocked".
  class Error < StandardError
    attr_reader :status, :body, :code, :reason

    def initialize(message, status: nil, body: nil, payload: nil)
      super(message)
      @status = status
      @body = body
      error = payload.is_a?(Hash) ? (payload["error"] || {}) : {}
      @code = error["code"]
      @reason = error["reason"]
    end
  end

  # A Letter client.
  #
  # Long-running server (default): identify / group / track enqueue calls that a
  # background thread auto-batches and flushes every 100ms or 50 events. Call
  # +close+ before the process exits.
  #
  # Serverless: pass flush_at: 1 and call +flush+ at the end of each invocation.
  #
  # +send_email+ (transactional) sits outside that machinery: it always performs
  # the request and returns the result. Batching a password reset would be a
  # bug, not an optimization.
  class Client
    # @param api_key   [String] API key (Dashboard -> Settings -> API keys).
    # @param base_url  [String] API origin. Defaults to https://api.letter.app.
    # @param flush_at  [Integer] Flush after this many queued events (1 = serverless).
    # @param flush_interval [Float] Seconds between background flushes.
    # @param max_retries [Integer] Max retry attempts per request.
    # @param on_error   [#call] Callback for background transport errors.
    def initialize(api_key:, base_url: DEFAULT_BASE_URL, flush_at: 50,
                   flush_interval: 0.1, max_retries: 3, open_timeout: 10,
                   read_timeout: 10, on_error: nil)
      raise Error, "api_key is required" if api_key.nil? || api_key.to_s.empty?

      @api_key = api_key
      @base_url = (base_url || DEFAULT_BASE_URL).sub(%r{/+\z}, "")
      @flush_at = [1, flush_at.to_i].max
      @flush_interval = flush_interval.to_f
      @max_retries = max_retries.to_i
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @on_error = on_error || ->(err) { warn("[letter] #{err.message}") }

      @uri = URI.parse(@base_url)
      @queue = []
      @mutex = Mutex.new
      @cond = ConditionVariable.new
      @send_mutex = Mutex.new
      @closed = false

      @thread = Thread.new { loop_run }
      at_exit { close }
    end

    # Queue an identify call (creates or updates a contact).
    def identify(user_id:, email: nil, traits: nil, timezone: nil,
                 timestamp: nil, message_id: nil)
      enqueue(serialize_identify(user_id, email, traits, timezone, timestamp, message_id))
    end

    # Queue a group call (associates a contact with an account).
    def group(user_id:, account_id:, name: nil, traits: nil,
              timestamp: nil, message_id: nil)
      enqueue(serialize_group(user_id, account_id, name, traits, timestamp, message_id))
    end

    # Queue a track call (records an event).
    def track(user_id:, event:, properties: nil, timestamp: nil, message_id: nil)
      enqueue(serialize_track(user_id, event, properties, timestamp, message_id))
    end

    # Send one transactional email and return the parsed result Hash
    # ("id", "messageId", "status", "replayed", ...).
    #
    # Named +send_email+ rather than +send+ because Object#send is Ruby's
    # dynamic dispatch: shadowing it on a client object would break every
    # +client.send(:private_method)+ and metaprogramming call in the host app.
    #
    # Never queued: the call performs the request and returns once the provider
    # has accepted the message. Pass +idempotency_key+ wherever the call can be
    # retried (a job with retries, a webhook handler): a replay returns the
    # original send rather than mailing the recipient twice, and it is what
    # makes retrying a 5xx safe. Without one this method does not retry,
    # because a duplicate email is worse than a failed one.
    #
    # +from+ defaults to the project's sender and must be on a verified domain.
    def send_email(to:, subject:, html: nil, text: nil, from: nil, from_name: nil,
                   reply_to: nil, headers: nil, tag: nil, metadata: nil,
                   idempotency_key: nil)
      raise Error, "send_email: to is required" if missing?(to)
      raise Error, "send_email: subject is required" if missing?(subject)
      raise Error, "send_email: provide html, text, or both" if missing?(html) && missing?(text)

      body = { "to" => to, "subject" => subject }
      {
        "html" => html, "text" => text, "from" => from, "fromName" => from_name,
        "replyTo" => reply_to, "headers" => headers, "tag" => tag,
        "metadata" => metadata, "idempotencyKey" => idempotency_key
      }.each { |key, value| body[key] = value unless value.nil? }

      request("/v1/send", body, max_retries: idempotency_key ? @max_retries : 0) || {}
    end

    # Send everything currently queued and block until it completes.
    def flush
      loop do
        batch = take_batch
        break if batch.nil?

        @send_mutex.synchronize { send_batch(batch) }
      end
    end

    # Flush, stop the background thread, and block until drained.
    def close
      @mutex.synchronize do
        return if @closed

        @closed = true
        @cond.broadcast
      end
      @thread&.join(@read_timeout * (@max_retries + 2))
      flush
    end

    private

    def enqueue(item)
      @mutex.synchronize do
        if @closed
          @on_error.call(Error.new("Letter client is closed."))
          return
        end
        @queue << item
        @cond.signal
      end
    end

    def take_batch
      @mutex.synchronize do
        return nil if @queue.empty?

        @queue.shift([@queue.length, 100].min)
      end
    end

    def loop_run
      loop do
        @mutex.synchronize do
          @cond.wait(@mutex) while @queue.empty? && !@closed
          return if @closed && @queue.empty?

          # Below the size threshold: wait briefly to batch more before sending.
          @cond.wait(@mutex, @flush_interval) if @queue.length < @flush_at && !@closed
        end
        flush
      end
    end

    def send_batch(batch)
      request("/v1/batch", { "batch" => batch })
    rescue StandardError => e
      @on_error.call(e.is_a?(Error) ? e : Error.new(e.message))
    end

    # POST +body+ to +path+, returning the decoded JSON response (or nil for an
    # empty one). +max_retries+ defaults to the client setting; callers pass 0
    # for requests that are not replay-safe (see +send_email+).
    def request(path, body, max_retries: @max_retries)
      data = JSON.generate(body)
      last_err = nil

      (0..max_retries).each do |attempt|
        begin
          res = post(path, data)
          code = res.code.to_i
          return decode_json(res.body) if code >= 200 && code < 300

          if code == 429 && attempt < max_retries
            sleep(retry_after(res))
            next
          end
          if code >= 500 && attempt < max_retries
            sleep(backoff(attempt))
            next
          end

          payload = decode_json(res.body)
          message = payload&.dig("error", "message") || res.body
          raise Error.new(
            "Request failed with #{code}: #{message}",
            status: code, body: res.body, payload: payload
          )
        rescue Timeout::Error, IOError, SystemCallError, SocketError => e
          last_err = Error.new("Network error: #{e.message}")
          raise last_err if attempt >= max_retries

          sleep(backoff(attempt))
        end
      end

      raise(last_err || Error.new("Request failed for unknown reason"))
    end

    def decode_json(raw)
      return nil if raw.nil? || raw.empty?

      parsed = JSON.parse(raw)
      parsed.is_a?(Hash) ? parsed : nil
    rescue JSON::ParserError
      nil
    end

    def post(path, data)
      http = Net::HTTP.new(@uri.host, @uri.port)
      http.use_ssl = (@uri.scheme == "https")
      http.open_timeout = @open_timeout
      http.read_timeout = @read_timeout

      req = Net::HTTP::Post.new(path)
      req["Content-Type"] = "application/json"
      req["Authorization"] = "Bearer #{@api_key}"
      req["User-Agent"] = "letterapp-ruby/#{Letterapp::VERSION}"
      req.body = data
      http.request(req)
    end

    def serialize_identify(user_id, email, traits, timezone, timestamp, message_id)
      raise Error, "identify: user_id is required" if missing?(user_id)

      item = {
        "type" => "identify",
        "userId" => user_id,
        "traits" => traits || {},
        "messageId" => message_id || SecureRandom.uuid
      }
      item["email"] = email unless email.nil?
      item["timezone"] = timezone unless timezone.nil?
      iso = to_iso(timestamp)
      item["timestamp"] = iso unless iso.nil?
      item
    end

    def serialize_group(user_id, account_id, name, traits, timestamp, message_id)
      raise Error, "group: user_id is required" if missing?(user_id)
      raise Error, "group: account_id is required" if missing?(account_id)

      item = {
        "type" => "group",
        "userId" => user_id,
        "accountId" => account_id,
        "traits" => traits || {},
        "messageId" => message_id || SecureRandom.uuid
      }
      item["name"] = name unless name.nil?
      iso = to_iso(timestamp)
      item["timestamp"] = iso unless iso.nil?
      item
    end

    def serialize_track(user_id, event, properties, timestamp, message_id)
      raise Error, "track: user_id is required" if missing?(user_id)
      raise Error, "track: event is required" if missing?(event)

      item = {
        "type" => "track",
        "userId" => user_id,
        "event" => event,
        "properties" => properties || {},
        "messageId" => message_id || SecureRandom.uuid
      }
      iso = to_iso(timestamp)
      item["timestamp"] = iso unless iso.nil?
      item
    end

    def to_iso(value)
      return nil if value.nil?
      return value.iso8601 if value.respond_to?(:iso8601)

      value.to_s
    end

    # Not named +blank?+: Active Support defines Object#blank?, and its
    # +present?+ and +presence+ call it, so a private blank?(value) here would
    # shadow it and make +client.present?+ raise ArgumentError in a Rails app.
    def missing?(value)
      value.nil? || value.to_s.empty?
    end

    def retry_after(res)
      raw = res["retry-after"]
      Float(raw)
    rescue ArgumentError, TypeError
      1.0
    end

    def backoff(attempt)
      (0.25 * (2**attempt)) + (rand * 0.1)
    end
  end
end
