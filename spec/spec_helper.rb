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

def visit_local(file)
  visit ('file:' + ('/' * (Gem.win_platform? ? 3 : 4)) + File.expand_path(file))
end

RSpec.configure do |config|
  config.include Marmara
  config.include Capybara::DSL
end
