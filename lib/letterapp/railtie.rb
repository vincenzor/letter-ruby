# frozen_string_literal: true

require "rails/railtie"

require_relative "delivery_method"

module Letterapp
  # Registers `:letter` as an ActionMailer delivery method so a Rails app only
  # has to pick it:
  #
  #   config.action_mailer.delivery_method = :letter
  #   config.action_mailer.letter_settings = { api_key: ENV["LETTER_API_KEY"] }
  #
  # Loaded from letterapp.rb only when Rails is present, so the gem stays
  # dependency-free everywhere else.
  class Railtie < ::Rails::Railtie
    initializer "letterapp.add_delivery_method" do
      ActiveSupport.on_load(:action_mailer) do
        add_delivery_method :letter, Letterapp::DeliveryMethod
      end
    end
  end
end
