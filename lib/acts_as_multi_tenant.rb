require 'active_record'
require_relative 'multi_tenant/version'
require_relative 'multi_tenant/acts_as_tenant'
require_relative 'multi_tenant/proxies_to_tenant'
require_relative 'multi_tenant/belongs_to_tenant'
require_relative 'multi_tenant/belongs_to_tenant_through'
require_relative 'multi_tenant/middleware'

module MultiTenant
  NotImplemented = Class.new(StandardError)

  class TenantsNotFound < RuntimeError
    attr_reader :tenant_class

    def initialize(tenant_class, identifiers, found_records)
      @tenant_class = tenant_class
      @identifiers = identifiers
      @found_records = found_records
    end

    # Returns an array of the tenant identifiers that could not be found
    def not_found
      @not_found ||= @identifiers.map(&:to_s) - @found_records.map { |tenant|
        tenant.send(@tenant_class.tenant_identifier).to_s
      }
    end

    def to_s
      message
    end

    def message
      "The following #{@tenant_class.name} tenants could not be found: #{not_found.join ", "}"
    end
  end
end
