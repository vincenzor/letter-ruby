# frozen_string_literal: true

require_relative "client"

module Letterapp
  # ActionMailer delivery method backed by Letter's transactional API.
  #
  # Register it and every existing mailer, view and `deliver_later` keeps
  # working unchanged - Rails builds the same Mail::Message it always did, and
  # this class is only responsible for putting it on the wire:
  #
  #   # config/initializers/letter.rb
  #   ActionMailer::Base.add_delivery_method :letter, Letterapp::DeliveryMethod
  #
  #   # config/environments/production.rb
  #   config.action_mailer.delivery_method = :letter
  #   config.action_mailer.letter_settings = { api_key: ENV["LETTER_API_KEY"] }
  #
  # Multipart mail maps cleanly: Letter takes an HTML part and a text part, and
  # a Mail::Message carries exactly those two. Attachments and inline images do
  # not map, and we raise rather than silently dropping them, since a receipt
  # that arrives without its PDF looks delivered but isn't.
  #
  # One recipient per API call. A mail addressed to several people becomes
  # several sends, which is also what you want: each recipient gets their own
  # log row, their own bounce, and can't see the others.
  #
  # To make a delivery replay-safe, set the idempotency key in the mailer:
  #
  #   headers["X-Letter-Idempotency-Key"] = "password-reset:#{token}"
  #
  # The header is consumed here, not forwarded. It has to come from the mailer
  # because it must be derived from what you are sending about; Message-ID
  # can't stand in for it, since ActionMailer rebuilds the message (and so
  # generates a fresh Message-ID) every time a `deliver_later` job retries.
  class DeliveryMethod
    IDEMPOTENCY_HEADER = "X-Letter-Idempotency-Key"

    # ActionMailer instantiates this with the configured settings hash and
    # reads `#settings` back when merging defaults.
    attr_accessor :settings

    def initialize(settings = {})
      @settings = settings || {}
    end

    def deliver!(mail)
      html, text = bodies(mail)
      if html.nil? && text.nil?
        raise Error, "Letter delivery: message has no text or HTML body"
      end

      unless mail.attachments.empty?
        raise Error,
              "Letter delivery: attachments are not supported by the " \
              "transactional API (#{mail.attachments.map(&:filename).join(', ')})"
      end

      recipients = Array(mail.to) + Array(mail.cc) + Array(mail.bcc)
      raise Error, "Letter delivery: message has no recipients" if recipients.empty?

      base_key = mail[IDEMPOTENCY_HEADER]&.value&.to_s
      headers = custom_headers(mail)

      recipients.map do |to|
        client.send_email(
          to: to,
          subject: mail.subject.to_s,
          html: html,
          text: text,
          from: address_of(mail.from),
          from_name: display_name_of(mail[:from]),
          reply_to: address_of(mail.reply_to),
          headers: headers,
          tag: settings[:tag],
          # Scoped per recipient: the same message to three people is three
          # distinct sends, not one replayed twice.
          idempotency_key: base_key && !base_key.empty? ? "#{base_key}:#{to}" : nil
        )
      end
    end

    private

    # Mail builds a new delivery method for every message, so this client
    # lives for one message. That's cheap: it only calls send_email, which
    # bypasses the queue, so the client never starts its batching thread.
    def client
      @client ||= Client.new(
        api_key: settings.fetch(:api_key) { ENV.fetch("LETTER_API_KEY") },
        base_url: settings[:base_url] || ENV["LETTER_BASE_URL"] || DEFAULT_BASE_URL
      )
    end

    def bodies(mail)
      if mail.multipart?
        [mail.html_part&.decoded, mail.text_part&.decoded]
      elsif mail.mime_type == "text/html"
        [mail.body.decoded, nil]
      else
        [nil, mail.body.decoded]
      end
    end

    # Headers Rails or Mail generate for the envelope, which Letter sets itself
    # from the fields above. Passing them through would be rejected as reserved
    # or would produce duplicates.
    ENVELOPE_HEADERS = %w[
      from to cc bcc subject reply-to date message-id mime-version
      content-type content-transfer-encoding
    ].freeze

    def custom_headers(mail)
      skip = ENVELOPE_HEADERS + [IDEMPOTENCY_HEADER.downcase]
      headers = {}
      mail.header.fields.each do |field|
        name = field.name.to_s
        next if skip.include?(name.downcase)

        headers[name] = field.value.to_s
      end
      headers.empty? ? nil : headers
    end

    def address_of(field)
      Array(field).first
    end

    def display_name_of(field)
      field&.display_names&.compact&.first
    end
  end
end
