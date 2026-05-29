# frozen_string_literal: true

require_relative "lib/letterapp/version"

Gem::Specification.new do |spec|
  spec.name = "letterapp"
  spec.version = Letterapp::VERSION
  spec.authors = ["letter.app"]

  spec.summary = "Official Ruby client for letter.app - onboarding email drip campaigns."
  spec.description = "Auto-batching Ruby client for letter.app: identify users, " \
                     "track events, and group accounts over the ingestion API. " \
                     "Retries, idempotency, zero runtime dependencies."
  spec.homepage = "https://letter.app/docs/ruby-sdk"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/vincenzor/letter-ruby",
    "bug_tracker_uri" => "https://github.com/vincenzor/letter-ruby/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb"] + ["README.md", "LICENSE"]
  spec.require_paths = ["lib"]
end
