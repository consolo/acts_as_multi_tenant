module MultiTenant
  #
  # Module with helpers for telling a model that it belongs to a tenant.
  #
  module BelongsToTenant
    #
    # Bind this models' records to a tenant. You *must* specify the association name, and you *may* follow it
    # up with any of the standard 'belongs_to' arguments (i.e. a scope and/or an options Hash).
    #
    #   class Widget < ActiveRecord::Base
    #     belongs_to_tenant :customer
    #   end
    #
    # @param association_name [Symbol] Name of the association to the tenant
    # @param scope [Proc] (optional) Proc holding an Arel scope for the lookup - same that the normal `belongs_to` method accepts.
    # @param options [Hash] (optional) Hash with association options - same that the normal `belongs_to` methods accepts.
    #
    def belongs_to_tenant(association_name, scope = nil, **options)
      belongs_to association_name, scope, **options
      reflection = reflections[association_name.to_s]
      unless reflection.klass.acts_as_tenant? or reflection.klass.proxies_to_tenant?
        raise "`belongs_to_tenant :#{association_name}` failed because #{reflection.klass.name} has not used `acts_as_tenant` or `proxies_to_tenant`."
      end

      cattr_accessor :tenant_class, :tenant_foreign_key, :tenant_primary_key
      self.tenant_class = reflection.klass
      self.tenant_foreign_key = reflection.foreign_key.to_sym
      self.tenant_primary_key = reflection.association_primary_key.to_sym

      before_validation :assign_to_tenant
      validates_presence_of tenant_foreign_key

      self.class_eval do
        include MultiTenant::BelongsToTenant::InstanceMethods

        default_scope {
          current = tenant_class.current
          current ? where({tenant_foreign_key => current.send(tenant_primary_key)}) : where('1=1')
        }
      end
    end

    #
    # Returns true if this model belongs to a tenant.
    #
    # @return [Boolean]
    #
    def belongs_to_tenant?
      respond_to? :tenant_class
    end

    #
    # Instance methods given to tenant-owned models.
    #
    module InstanceMethods
      private

      #
      # Assign this model to the current tenant (if any)
      #
      def assign_to_tenant
        if self.class.tenant_class.current and send(self.class.tenant_foreign_key).blank?
          send "#{self.class.tenant_foreign_key}=", self.class.tenant_class.current.send(self.class.tenant_primary_key)
        end
      end
    end
  end
end

ActiveRecord::Base.extend MultiTenant::BelongsToTenant
