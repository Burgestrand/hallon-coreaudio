require "bundler/gem_tasks"

task :compile do
  Dir.chdir('ext/hallon') do
    sh 'ruby extconf.rb'
    sh 'make'
  end
end

task :console do
  exec 'irb -Ilib -Iext -rhallon/coreaudio'
end

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new

task :default => [:compile, :spec]
