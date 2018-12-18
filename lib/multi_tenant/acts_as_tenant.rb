#
# The main acts_as_multi_tenant module.
#
module MultiTenant
  #
  # Contains helpers to turn an ActiveRecord model into the tenant source.
  #
  module ActsAsTenant
    #
    # Use this ActiveRecord model as the tenant source.
    #
    # @param using [String] (optional) column that contains the unique lookup identifier. Defaults to :code.
    #
    def acts_as_tenant(using: :code)
      cattr_accessor :tenant_identifier, :tenant_thread_var
      self.tenant_identifier = using
      self.tenant_thread_var = "current_tenant_#{object_id}".freeze # allows there to be multiple tenant classes
      self.extend MultiTenant::ActsAsTenant::TenantGetters
      self.extend MultiTenant::ActsAsTenant::TenantSetters
      self.extend MultiTenant::ActsAsTenant::TenantHelpers
    end

    #
    # Returns true if this model is being used as a tenant.
    #
    # @return [Boolean]
    #
    def acts_as_tenant?
      respond_to? :tenant_identifier
    end

    module TenantGetters
      #
      # Returns true if there are any current tenants set, false if not.
      #
      # @return [Boolean]
      #
      def current_tenants?
        current_tenants.any?
      end
      alias_method :current?, :current_tenants?
      alias_method :current_tenant?, :current_tenants?

      #
      # Returns the array of current tenants. Thread-safe.
      #
      # @return the array of tenant records
      #
      def current_tenants
        Thread.current.thread_variable_get(tenant_thread_var) || []
      end

      #
      # Return the current tenant record, if any. Thread-safe. If there are MULTIPLE current tenants set this will
      # raise a RuntimeError.
      #
      # @return the current tenant record
      #
      def current_tenant
        tenants = current_tenants
        if tenants.size > 1
          raise "#{self.name}.current/current_tenant was called when multiple current tenants were present?. Did you mean to call #{self.name}.current_tenants?"
        else
          tenants[0]
        end
      end
      alias_method :current, :current_tenant
    end

    #
    # Class methods applied to the tenant model.
    #
    #   class Client < ActiveRecord::Base
    #     acts_as_tenant using: :code
    #   end
    #
    #   Client.current
    #   => # the current client set by the middleware, or nil
    #
    #   # Manually set the current client, where 'acme' is in the 'code' col in the db
    #   Client.current = 'acme'
    #
    #   # Manually set the current client to an AR record
    #   Client.current 
    #
    module TenantSetters
      #
      # Set the current tenant record. You may either pass an ActiveRecord Client record, OR the value
      # of the `:using` option you passed to `acts_as_tenant`. Thread-safe.
      #
      # @param record_or_identifier the record or the identifier in the 'tenant_identifier' column.
      #
      def current_tenant=(record_or_identifier)
        self.current_tenants = Array(record_or_identifier)
      end
      alias_method :current=, :current_tenant=

      #
      # Set the array of current tenant records. You may either pass an ActiveRecord Client record, OR the value
      # of the `:using` option you passed to `acts_as_tenant`. Thread-safe.
      #
      # @param records_or_identifiers array of the records or identifiers in the 'tenant_identifier' column.
      #
      def current_tenants=(records_or_identifiers)
        records, identifiers = Array(records_or_identifiers).partition { |x|
          x.class.respond_to?(:table_name) && x.class.table_name == self.table_name
        }
        tenants = if identifiers.any?
                    records + where({tenant_identifier => identifiers}).to_a
                  else
                    records
                  end
        Thread.current.thread_variable_set tenant_thread_var, tenants
      end
    end

    module TenantHelpers
      #
      # Loops through each tenant, sets it as current, and yields to any given block.
      # At the end, current is always set back to what it was originally.
      #
      def with_each_tenant
        old_tenants = self.current_tenants
        all.each do |tenant|
          self.current_tenant = tenant
          yield if block_given?
        end
      ensure
        self.current_tenants = old_tenants
      end

      #
      # Sets the given tenant as the current one and yields to a given block.
      # At the end, current is always set back to what it was originally.
      #
      def with_tenant(record_or_identifier)
        old_tenants = self.current_tenants
        self.current_tenant = record_or_identifier
        yield if block_given?
      ensure
        self.current_tenants = old_tenants
      end

      #
      # Sets the given array of tenants as the current one and yields to a given block.
      # At the end, current is always set back to what it was originally.
      #
      def with_tenants(records_or_identifiers)
        old_tenants = self.current_tenants
        self.current_tenants = records_or_identifiers
        yield if block_given?
      ensure
        self.current_tenants = old_tenants
      end

      #
      # Sets current to nil and yields to the block.
      # At the end, current is always set back to what it was originally.
      #
      def without_tenant
        old_tenants = self.current_tenants
        self.current_tenant = nil
        yield if block_given?
      ensure
        self.current_tenants = old_tenants
      end

      alias_method :without_tenants, :without_tenant
    end
  end
end

ActiveRecord::Base.extend MultiTenant::ActsAsTenant
