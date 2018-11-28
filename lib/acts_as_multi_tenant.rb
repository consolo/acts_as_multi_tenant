require 'active_record'
require_relative 'multi_tenant/version'
require_relative 'multi_tenant/acts_as_tenant'
require_relative 'multi_tenant/proxies_to_tenant'
require_relative 'multi_tenant/belongs_to_tenant'
require_relative 'multi_tenant/belongs_to_tenant_through'
require_relative 'multi_tenant/middleware'

module MultiTenant
  NotImplemented = Class.new(StandardError)
end
