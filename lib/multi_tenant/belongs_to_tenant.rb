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

      include MultiTenant::BelongsToTenant::InstanceMethods

      before_validation :assign_to_current_tenant
      validates_presence_of tenant_foreign_key
      validate :ensure_assigned_to_current_tenants

      default_scope {
        current = tenant_class.current_tenants.map(&tenant_primary_key)
        if current.size == 1
          where({tenant_foreign_key => current.first})
        elsif current.any?
          where({tenant_foreign_key => current})
        else
          where("1=1")
        end
      }
    end

    #
    # Returns true if this model belongs to a tenant.
    #
    # @return [Boolean]
    #
    def belongs_to_tenant?
      respond_to? :tenant_class
    end

    module InstanceMethods
      private

      #
      # Assign this model to the current tenant (if any). If there are multiple current tenants this is a no-op.
      #
      def assign_to_current_tenant
        code_col = self.class.tenant_class.tenant_identifier
        current = self.class.tenant_class.current_tenants

        if current.size == 1 or current.map(&code_col).uniq.size == 1
          tenant_fkey = self.class.tenant_foreign_key
          if send(tenant_fkey).nil? or !current.map(&self.class.tenant_primary_key).include? send(tenant_fkey)
            current_tenant_id = self.class.tenant_class.current_tenants.first.send(self.class.tenant_primary_key)
            send "#{tenant_fkey}=", current_tenant_id
          end
        end
      end

      #
      # If the tenant_id is set, make sure it's one of the current ones.
      #
      def ensure_assigned_to_current_tenants
        _tenants_ids = self.class.tenant_class.current_tenants.map { |t|
          t.send(self.class.tenant_primary_key).to_s
        }
        _current_id = send self.class.tenant_foreign_key
        if _tenants_ids.any? and _current_id.present? and !_tenants_ids.include?(_current_id.to_s)
          errors.add(self.class.tenant_foreign_key, "is incorrect")
        end
      end
    end
  end
end

ActiveRecord::Base.extend MultiTenant::BelongsToTenant
