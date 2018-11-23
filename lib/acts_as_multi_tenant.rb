require 'active_record'
require_relative 'multi_tenant/version'
require_relative 'multi_tenant/acts_as_tenant'
require_relative 'multi_tenant/proxies_to_tenant'
require_relative 'multi_tenant/belongs_to_tenant'
require_relative 'multi_tenant/belongs_to_tenant_through'
require_relative 'multi_tenant/middleware'

module MultiTenant
  module Impl
    NotImplemented = Class.new(StandardError)
    autoload :SingleCurrent, 'multi_tenant/impl/single_current'
    autoload :MultipleCurrent, 'multi_tenant/impl/multiple_current'
  end
end
