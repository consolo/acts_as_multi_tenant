require_relative 'lib/multi_tenant/version'

Gem::Specification.new do |s|
  s.name = 'acts_as_multi_tenant'
  s.version = MultiTenant::VERSION
  s.licenses = ['MIT']
  s.summary = "An ActiveRecord plugin for multi-tenant databases"
  s.description = "An ActiveRecord plugin for multi-tenant databases"
  s.date = '2019-06-23'
  s.authors = ['Jordan Hollinger', 'Andrew Coleman', 'Taylor Redden']
  s.email = 'jordan.hollinger@gmail.com'
  s.homepage = 'https://github.com/consolo/acts_as_multi_tenant'
  s.require_paths = ['lib']
  s.files = [Dir.glob('lib/**/*'), 'LICENSE', 'README.md'].flatten
  s.required_ruby_version = '>= 2.1.0'
  s.add_runtime_dependency 'activerecord', ['>= 4.2', '< 6.0']
  s.add_runtime_dependency 'rack'
end
