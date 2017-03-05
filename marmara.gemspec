# -*- encoding: utf-8 -*-

Gem::Specification.new do |gem|
  gem.name          = "marmara"
  gem.authors       = ["Godwin"]
  gem.email         = ["goodgodwin@hotmail.com"]
  gem.description   = "Generates a CSS coverage report"
  gem.summary       = "Analyses your css for code coverage"
  gem.homepage      = "http://bikecollectives.org"
  gem.licenses      = ["MIT"]

  gem.files         = Dir["{lib}/**/*", "MIT-LICENSE", "Rakefile", "README.rdoc"]
  gem.require_paths = ["lib"]
  gem.version       = '1.0'

  gem.add_dependency('css_parser', '>= 1.4.7')
  # gem.add_dependency "diffy"
end
