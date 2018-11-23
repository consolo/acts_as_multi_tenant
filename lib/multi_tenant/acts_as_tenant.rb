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
    # The "current" option allows you to specify whether Client.current is a single record (the default) or an array of records.
    #
    # @param using [String] (optional) column that contains the unique lookup identifier. Defaults to :code.
    # @param current [Symbol] :single | :multiple
    #
    def acts_as_tenant(using: :code, current: :single)
      cattr_accessor :tenant_identifier, :tenant_thread_var, :multi_tenant_impl
      self.tenant_identifier = using
      self.tenant_thread_var = "current_tenant_#{object_id}".freeze # allows there to be multiple tenant classes
      self.multi_tenant_impl = case current
                               when :single then MultiTenant::Impl::SingleCurrent.new(self)
                               when :multiple then MultiTenant::Impl::MultipleCurrent.new(self)
                               else raise ArgumentError, "Unknown current option '#{current}'"
                               end
      self.extend MultiTenant::ActsAsTenant::ClassMethods
      self.extend self.multi_tenant_impl.acts_as_tenant_class_methods
    end

    #
    # Returns true if this model is being used as a tenant.
    #
    # @return [Boolean]
    #
    def acts_as_tenant?
      respond_to? :tenant_identifier
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
    module ClassMethods
      #
      # Return the current tenant record, if any. Thread-safe.
      #
      # @return the current tenant record
      #
      def current
        Thread.current.thread_variable_get(tenant_thread_var) || resolve_tenant(nil)
      end

      #
      # Set the current tenant record. You may either pass an ActiveRecord Client record, OR the value
      # of the `:using` option you passed to `acts_as_tenant`. Thread-safe.
      #
      # @param record_or_identifier the record or the identifier in the 'tenant_identifier' column.
      #
      def current=(record_or_identifier)
        obj = resolve_tenant record_or_identifier
        Thread.current.thread_variable_set tenant_thread_var, obj
      end

      #
      # Loops through each tenant, sets it as current, and yields to any given block.
      # At the end, current is always set back to what it was originally.
      #
      def with_each_tenant
        old_current = self.current
        all.each do |tenant|
          self.current = tenant
          yield if block_given?
        end
      ensure
        self.current = old_current
      end

      #
      # Sets the given tenant as the current one and yields to a given block.
      # At the end, current is always set back to what it was originally.
      #
      def with_tenant(record_or_identifier)
        old_current = self.current
        self.current = record_or_identifier
        yield if block_given?
      ensure
        self.current = old_current
      end

      #
      # Sets current to nil and yields to the block.
      # At the end, current is always set back to what it was originally.
      #
      def without_tenant
        old_current = self.current
        self.current = resolve_tenant nil
        yield if block_given?
      ensure
        self.current = old_current
      end
    end
  end
end

ActiveRecord::Base.extend MultiTenant::ActsAsTenant
