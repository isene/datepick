require 'bundler/gem_tasks'

desc 'Run datepick'
task :run do
  exec 'ruby -Ilib bin/datepick'
end

desc 'Install gem locally'
task :install_local do
  system 'gem build datepick.gemspec'
  system 'gem install datepick-*.gem'
  system 'rm datepick-*.gem'
end

desc 'Clean up build artifacts'
task :clean do
  system 'rm -f *.gem'
end

task default: :run