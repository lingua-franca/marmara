require 'bundler/setup'
Bundler.setup

require 'marmara'
require 'rspec'

RSpec.configure do |config|
  config.include Marmara
end
