# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "json"
require "rbconfig"
require "tmpdir"

class RailtieTest < Minitest::Test
  LIB = File.expand_path("../lib", __dir__)

  # A production-like Rails app configured the way the README says. Order
  # matters: config/application.rb requires the frameworks, then
  # Bundler.require loads the gem, then the app is defined and initialized.
  # Eager loading loads ActionMailer::Base during boot, which runs the
  # :action_mailer load hooks and applies config.action_mailer.*.
  APP = <<~RUBY
    require "rails"
    require "action_mailer/railtie"
    require "letterapp"

    class LetterApp < Rails::Application
      config.root = Dir.pwd
      config.eager_load = true
      config.logger = Logger.new(nil)
      config.secret_key_base = "test"
      config.action_mailer.delivery_method = :letter
      config.action_mailer.letter_settings = { api_key: "from-settings" }
    end
    LetterApp.initialize!

    class WelcomeMailer < ActionMailer::Base
      def welcome
        mail(to: "alice@example.com", from: "app@example.com", subject: "Hi", body: "Hi")
      end
    end

    delivery = WelcomeMailer.welcome.message.delivery_method
    puts JSON.generate(
      delivery_method: ActionMailer::Base.delivery_method,
      letter_settings: ActionMailer::Base.letter_settings,
      delivery_class: delivery.class.name,
      api_key: delivery.settings[:api_key]
    )
  RUBY

  def setup
    missing = %w[railties actionmailer].select { |name| Gem::Specification.find_all_by_name(name).empty? }
    skip "needs #{missing.join(' and ')} installed" unless missing.empty?
  end

  # Up to 0.2.2 the Railtie added the delivery method from an initializer that
  # ran after Action Mailer's own, so the hook applying config.action_mailer.*
  # ran first and boot failed with NoMethodError on letter_settings=.
  def test_letter_settings_configures_the_delivery_method
    result = boot(APP)

    assert_equal "letter", result["delivery_method"]
    assert_equal({ "api_key" => "from-settings" }, result["letter_settings"])
    assert_equal "Letterapp::DeliveryMethod", result["delivery_class"]
    assert_equal "from-settings", result["api_key"]
  end

  private

  # Boots in a child process: an initialized Rails app can't be torn down, and
  # the other tests run as plain Ruby. LETTER_API_KEY is cleared so the key can
  # only come from letter_settings.
  def boot(script)
    env = { "RAILS_ENV" => "production", "LETTER_API_KEY" => nil }
    out, err, status = Dir.mktmpdir do |root|
      Open3.capture3(env, RbConfig.ruby, "-I", LIB, "-e", script, chdir: root)
    end
    assert status.success?, "Rails app failed to boot:\n#{err}"
    JSON.parse(out.lines.last)
  end
end
