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

      default_scope {
        tenants = delegate_class.tenant_class.current_tenants
        next where('1=1') if tenants.empty?

        # Using straight sql so we can JOIN against two columns. Otherwise one must go into "WHERE", and Arel would apply it to UPDATEs and DELETEs.
        quoted_tenant_ids = tenants.map { |t| connection.quote t.send delegate_class.tenant_primary_key }
        joins("INNER JOIN #{ref.klass.table_name} ON #{ref.klass.table_name}.#{ref.foreign_key}=#{table_name}.#{ref.association_primary_key} AND #{ref.klass.table_name}.#{ref.klass.tenant_foreign_key} IN (#{quoted_tenant_ids.join(',')})").
          distinct.
          readonly(false) # using "joins" makes records readonly, which we don't want
      }
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
