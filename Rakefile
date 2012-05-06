begin
  require "bundler/gem_tasks"
rescue LoadError
end

task :extconf do
  Dir.chdir('ext/hallon') do
    sh 'ruby extconf.rb'
  end
end

task :compile => :extconf do
  Dir.chdir('ext/hallon') do
    sh 'make'
  end
end

task :console do
  exec 'irb -Ilib -Iext -rhallon/coreaudio'
end
