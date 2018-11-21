module MultiTenant
  #
  # Module with helpers for telling a model that it belongs to a tenant through one of its associations.
  #
  module BelongsToTenantThrough
    #
    # Declare that this model has an association that belongs to a tenant. The assocation must be declared
    # BEFORE this is called.
    #
    #   class User < ActiveRecord::Base
    #     has_many :memberships
    #     belongs_to_tenant_through :memberships
    #   end
    #
    # @param association_name [Symbol] Name of the association to the tenant
    #
    def belongs_to_tenant_through(association_name)
      ref = reflections[association_name.to_s]
      raise "`belongs_to_tenant_through :#{association_name}` failed because the association `:#{association_name}` has not been declared" if ref.nil?
      raise "`belongs_to_tenant_through :#{association_name}` failed because #{ref.klass.name} has not used `belongs_to_tenant`" unless ref.klass.belongs_to_tenant?

      cattr_accessor :delegate_class
      self.delegate_class = ref.klass

      impl = self.delegate_class.tenant_class.multi_tenant_impl
      default_scope(&impl.belongs_to_tenant_through_default_scope(self, ref))
    end

    #
    # Returns true if this model belongs to a tenant through one of its associations.
    #
    # @return [Boolean]
    #
    def belongs_to_tenant_through?
      respond_to? :delegate_class
    end
  end
end

ActiveRecord::Base.extend MultiTenant::BelongsToTenantThrough
