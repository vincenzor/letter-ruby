# frozen_string_literal: true

require_relative "letterapp/version"
require_relative "letterapp/client"

# Official Ruby client for letter.app.
#
#   require "letterapp"
#
#   letter = Letterapp::Client.new(api_key: ENV["LETTER_API_KEY"])
#   letter.identify(user_id: "user_123", email: "alice@example.com")
#   letter.track(user_id: "user_123", event: "Signed Up")
#   letter.close
module Letterapp
  # Convenience: Letterapp.new(...) == Letterapp::Client.new(...)
  def self.new(**kwargs)
    Client.new(**kwargs)
  end
end
