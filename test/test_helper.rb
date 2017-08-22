require 'acts_as_multi_tenant'
require 'minitest/autorun'
Dir.glob('./test/support/*.rb').each { |file| require file }
puts "Testing against ActiveRecord version #{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}"
