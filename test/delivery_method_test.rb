# frozen_string_literal: true

require "minitest/autorun"
require "letterapp"

class DeliveryMethodTest < Minitest::Test
  # The parts of a Mail::Message that DeliveryMethod reads: one recipient,
  # plain text, no attachments or custom headers.
  class FakeMail
    Body = Struct.new(:decoded)
    Header = Struct.new(:fields)

    attr_reader :to, :subject, :body

    def initialize(to:, subject:, text:)
      @to = to
      @subject = subject
      @body = Body.new(text)
    end

    def multipart? = false
    def mime_type = "text/plain"
    def attachments = []
    def cc = nil
    def bcc = nil
    def from = ["app@example.com"]
    def reply_to = nil
    def [](_name) = nil
    def header = Header.new([])
  end

  # What ActionMailer does for every message: Mail builds a new delivery
  # method, which builds a new client, and calls deliver! once. Nothing closes
  # those clients, and up to 0.2.1 each one left a thread running.
  def test_repeated_deliveries_leave_no_threads
    before = Thread.list

    paths = 5.times.flat_map do |i|
      delivery = Letterapp::DeliveryMethod.new(api_key: "test")
      sent = stub_request(delivery.send(:client))
      delivery.deliver!(FakeMail.new(to: "user#{i}@example.com", subject: "Hi", text: "Hi"))
      sent
    end

    assert_equal ["/v1/send"] * 5, paths
    assert_empty Thread.list - before
  end

  private

  # Replaces the client's HTTP call; returns the paths it is called with.
  def stub_request(client)
    paths = []
    client.define_singleton_method(:request) do |path, _body, **|
      paths << path
      { "id" => "em_123" }
    end
    paths
  end
end
