require 'bundler/setup'
require 'rake/testtask'
require 'yard'

YARD::Rake::YardocTask.new do |t|
  t.files = %w(lib/**/*.rb)
  t.options = %w(-o ./docs)
  t.stats_options = %w(--list-undoc)
end

Rake::TestTask.new do |t|
  t.libs << 'lib' << 'test'
  t.test_files = FileList['test/**/*_test.rb']
  t.verbose = false
end
