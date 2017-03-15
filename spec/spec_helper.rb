require 'bundler/setup'
Bundler.setup

require 'marmara'
require 'rspec'
require 'capybara'
require 'capybara/dsl'
require 'capybara/poltergeist'

Capybara.register_driver :poltergeist do |app|
  Capybara::Poltergeist::Driver.new(app, inspector: true)
end

Capybara.current_driver = :poltergeist
Capybara.javascript_driver = :poltergeist
# Capybara.run_server = false
# Capybara.app_host = 'https://www.google.com'

RSpec.configure do |config|
  config.include Marmara
  # config.include Capybara
  config.include Capybara::DSL
end
