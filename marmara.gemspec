# -*- encoding: utf-8 -*-

Gem::Specification.new do |gem|
  gem.name          = "marmara"
  gem.authors       = ["Godwin"]
  gem.email         = ["goodgodwin@hotmail.com"]
  gem.description   = "Generates a CSS coverage report"
  gem.summary       = "Analyses your css for code coverage"
  gem.homepage      = "http://bikecollectives.org"
  gem.licenses      = ["MIT"]

  gem.files         = Dir["{lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  gem.require_paths = ["lib"]
  gem.version       = '1.0.1'

  gem.add_dependency('css_parser', '>= 1.5.0.pre')

  gem.add_development_dependency 'bundler'
  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'rspec'
  gem.add_development_dependency 'yard'
  gem.add_development_dependency 'capybara'
  gem.add_development_dependency 'poltergeist'
end
