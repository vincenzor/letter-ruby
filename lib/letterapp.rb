# frozen_string_literal: true

require_relative "letterapp/version"
require_relative "letterapp/client"
require_relative "letterapp/delivery_method"

# In a Rails app, register `:letter` as an ActionMailer delivery method so the
# host only has to select it. Guarded so the gem keeps working (and stays
# dependency-free) outside Rails.
require_relative "letterapp/railtie" if defined?(::Rails::Railtie)

# Official Ruby client for letter.app.
#
#   require "letterapp"
#
#   letter = Letterapp::Client.new(api_key: ENV["LETTER_API_KEY"])
#   letter.identify(user_id: "user_123", email: "alice@example.com")
#   letter.track(user_id: "user_123", event: "Signed Up")
#   letter.send_email(to: "alice@example.com", subject: "Hi", html: "<p>Hi</p>")
#   letter.close
module Letterapp
  # Convenience: Letterapp.new(...) == Letterapp::Client.new(...)
  def self.new(**kwargs)
    Client.new(**kwargs)
  end
end
