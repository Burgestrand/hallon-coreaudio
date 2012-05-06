# -*- encoding: utf-8 -*-
require File.expand_path('../lib/hallon/coreaudio/version', __FILE__)

Gem::Specification.new do |gem|
  gem.name          = "hallon-coreaudio"

  gem.authors       = ["Kim Burgestrand"]
  gem.email         = ["kim@burgestrand.se"]
  gem.summary       = %q{CoreAudio audio drivers for Hallon: http://rubygems.org/gems/hallon}

  gem.files         = `git ls-files`.split("\n")
  gem.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  gem.require_paths = ["lib", "ext"]
  gem.extensions    = ["ext/hallon/extconf.rb"]
  gem.version       = Hallon::CoreAudio::VERSION

  gem.add_dependency 'hallon', '~> 0.13'
  gem.add_development_dependency 'rspec', '~> 2.7'
end
