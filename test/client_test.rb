# frozen_string_literal: true

require "minitest/autorun"
require "letterapp"

class ClientTest < Minitest::Test
  # What `require "active_support/core_ext"` (8.1) adds to every Object,
  # public and private. A method of the same name on one of our classes
  # shadows it inside a Rails app: 0.2.0's private blank?(value) made
  # client.present? raise ArgumentError.
  ACTIVE_SUPPORT_OBJECT_METHODS = %i[
    acts_like? as_json blank? class_eval deep_dup duplicable? html_safe? in?
    instance_values instance_variable_names presence presence_in present?
    to_json to_param to_query to_yaml try try! with with_options
    concern enable_warnings silence_warnings suppress with_warnings
  ].freeze

  def setup
    @client = Letterapp::Client.new(api_key: "test", flush_at: 1)
  end

  def teardown
    @client.close
  end

  def test_does_not_shadow_active_support_object_methods
    [Letterapp::Client, Letterapp::DeliveryMethod].each do |klass|
      own = klass.instance_methods(false) + klass.private_instance_methods(false)
      assert_empty own & ACTIVE_SUPPORT_OBJECT_METHODS, "#{klass} shadows Active Support"
    end
  end

  def test_present_and_blank_work_under_active_support
    with_active_support_blank do
      assert_predicate @client, :present?
      refute_predicate @client, :blank?
      assert_same @client, @client.presence
    end
  end

  def test_required_arguments_are_still_checked
    assert_raises_message("send_email: to is required") do
      @client.send_email(to: "", subject: "Hi", text: "Hi")
    end
    assert_raises_message("send_email: subject is required") do
      @client.send_email(to: "alice@example.com", subject: nil, text: "Hi")
    end
    assert_raises_message("send_email: provide html, text, or both") do
      @client.send_email(to: "alice@example.com", subject: "Hi", html: "")
    end
    assert_raises_message("identify: user_id is required") { @client.identify(user_id: "") }
    assert_raises_message("group: account_id is required") do
      @client.group(user_id: "user_123", account_id: nil)
    end
    assert_raises_message("track: event is required") { @client.track(user_id: "user_123", event: "") }
  end

  def test_send_email_accepts_text_only
    sent = stub_request(@client)

    result = @client.send_email(to: "alice@example.com", subject: "Hi", text: "Hi")

    assert_equal({ "id" => "em_123" }, result)
    assert_equal [["/v1/send", { "to" => "alice@example.com", "subject" => "Hi", "text" => "Hi" }]], sent
  end

  # Mail builds a new delivery method, and so a new client, for every message.
  # Up to 0.2.1 each of those clients started a thread that never exited.
  def test_send_email_never_starts_a_thread
    before = Thread.list
    client = Letterapp::Client.new(api_key: "test")
    stub_request(client)

    client.send_email(to: "alice@example.com", subject: "Hi", text: "Hi")

    assert_empty Thread.list - before
  ensure
    client&.close
  end

  def test_queued_calls_start_one_thread_and_are_sent
    sent = stub_request(@client)
    before = Thread.list

    @client.identify(user_id: "user_123", email: "alice@example.com")
    @client.track(user_id: "user_123", event: "Signed Up")

    assert_equal 1, (Thread.list - before).size
    @client.close
    assert_empty Thread.list - before
    assert_equal %w[identify track], sent_items(sent).map { |item| item["type"] }
  end

  # A forked child gets the parent's client with a dead copy of its thread.
  def test_restarts_a_dead_thread
    client = Letterapp::Client.new(api_key: "test", flush_interval: 10)
    sent = stub_request(client)
    before = Thread.list

    client.track(user_id: "user_123", event: "First")
    (Thread.list - before).each { |thread| thread.kill.join }
    client.track(user_id: "user_123", event: "Second")

    assert_equal 1, (Thread.list - before).size
    client.close
    assert_equal %w[First Second], sent_items(sent).map { |item| item["event"] }
  ensure
    client&.close
  end

  private

  # Replaces the client's HTTP call; returns the [path, body] pairs it receives.
  def stub_request(client)
    sent = []
    client.define_singleton_method(:request) do |path, body, **|
      sent << [path, body]
      { "id" => "em_123" }
    end
    sent
  end

  def sent_items(sent)
    sent.flat_map { |_path, body| body["batch"] }
  end

  def assert_raises_message(message, &block)
    error = assert_raises(Letterapp::Error, &block)
    assert_equal message, error.message
  end

  # Active Support's own Object#blank?, #present? and #presence (8.1), defined
  # on Object only for the block so the other tests run as plain Ruby.
  def with_active_support_blank
    Object.class_eval do
      def blank?
        respond_to?(:empty?) ? !!empty? : false
      end

      def present?
        !blank?
      end

      def presence
        self if present?
      end
    end
    yield
  ensure
    Object.class_eval { remove_method :blank?, :present?, :presence }
  end
end
