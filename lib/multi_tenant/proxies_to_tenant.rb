module MultiTenant
  # An exception indicating a tenant with a missing or invalid proxy identifier
  NilProxyError = Class.new(RuntimeError)

  #
  # Helpers for setting a proxy model to your tenant model. So your records can `acts_as_tenant` to the proxy model instead of directly to the tenant.
  #
  # However, only certain types of associations are supported. (We could probably support all types, but since each type requires a special implementation, we've only added the ones we've needed so far.)
  #
  # Configuration I: has_many, inverse of belongs_to
  #
  #     # The tenant model that's hooked up to the Rack middleware and holds the "current" tenant
  #     class Client < ActiveRecord::Base
  #       belongs_to :license
  #       acts_as_tenant
  #     end
  #
  #     # The proxy model that's (potentially) associated with multiple tenants
  #     class License < ActiveRecord::Base
  #       has_many :clients, inverse_of: :license
  #       proxies_to_tenant :clients
  #     end
  #
  #     # Widets will be associated to a License (instead of a Client), therefore they are automatically
  #     # shared with all Clients who use that License.
  #     class Widget < ActiveRecord::Base
  #       belongs_to_tenant :license
  #       has_many :clients, through: :license # not required - just for clarity
  #     end
  #
  #     # Splines, on the other hand, still belong directly to individual Clients like normal.
  #     class Spline < ActiveRecord::Base
  #       belongs_to_tenant :client
  #     end
  #
  #     # This is what's going on behind the scenes. Not too complicated, all things considered.
  #     License.current == Client.current.license
  #
  # Configuration II: has_one, inverse of belongs_to:
  # License has_one Client, and Client belongs_to License.
  #
  # Configuration III: belongs_to, inverse of has_one:
  # License belongs_to Client, and Client has_one License.
  #
  module ProxiesToTenant
    #
    # Declare a model as a proxy to tenant model.
    #
    # @param association_name [Symbol] the association that's the *real* tenant. You must define the association yourself (e.g. belongs_to) along with the `:inverse_of` option.
    # @param scope [Proc] (optional) An AR scope that will be run *against the proxy model*, i.e. *this* model. Useful for when the association's `:inverse_of` is a `has_many` or `has_many_and_belongs_to`.
    #
    def proxies_to_tenant(association_name, scope = nil)
      ref = reflections[association_name.to_s]
      raise "`proxies_to_tenant :#{association_name}`: unable to find association `:#{association_name}`. Make sure you create the association *first*." if ref.nil?
      raise "`proxies_to_tenant :#{association_name}`: #{ref.klass.name} must use `acts_as_tenant`" if !ref.klass.acts_as_tenant?
      raise "`proxies_to_tenant :#{association_name}`: the `:#{association_name}` association must use the `:inverse_of` option." if ref.inverse_of.nil?

      cattr_accessor :proxied_tenant_class, :proxied_tenant_inverse_assoc, :proxied_tenant_inverse_scope
      self.proxied_tenant_class = ref.klass
      self.proxied_tenant_inverse_assoc = ref.inverse_of.name
      self.proxied_tenant_inverse_scope = scope

      extend MultiTenant::ActsAsTenant::TenantGetters
      extend TenantInterface
      extend case [ref.macro, ref.inverse_of.macro]
             when [:has_many, :belongs_to], [:has_one, :belongs_to], [:belongs_to, :has_one]
               ProxiesToTenantSingularInverseAssociation
             else
               raise MultiTenant::NotImplemented, "`proxies_to_tenant` does not currently support `#{ref.macro}` associations with `#{ref.inverse_of.macro} inverses."
               ProxiesToTenantPluralInverseAssociation
             end
    end

    #
    # Returns true if this model is proxying to a tenant.
    #
    # @return [Boolean]
    #
    def proxies_to_tenant?
      respond_to? :proxied_tenant_class
    end

    #
    # Class methods to give this the same interface as a "real" tenant class.
    #
    module TenantInterface
      # Returns the tenant_identifier from the proxied class
      def tenant_identifier
        self.proxied_tenant_class.tenant_identifier
      end
    end

    #
    # Class methods for tenant proxies that have a singular inverse association (i.e. belongs_to or has_one).
    #
    module ProxiesToTenantSingularInverseAssociation
      # Returns the current record of the proxy model
      def current_tenants
        proxied_tenant_class
          .current_tenants
          .map { |tenant|
            if (proxy = tenant.send(proxied_tenant_inverse_assoc))
              proxy
            else
              tenant_id = tenant.send(proxied_tenant_class.primary_key)
              raise ::MultiTenant::NilProxyError, "Missing proxy for tenant #{proxied_tenant_class.name}##{tenant_id}"
            end
          }
      end
    end

    #
    # Class methods for tenant proxies that have a plural inverse association (i.e. has_many).
    # NOTE These are just some thoughts on *maybe* how to support this if we ever need it.
    #
    module ProxiesToTenantPluralInverseAssociation
      # Returns the current record of the proxy model
      def current_tenant
        raise MultiTenant::NotImplemented, "needs confirmed"
        if (tenant = proxied_tenant_class.current_tenant)
          tenant.send(proxied_tenant_inverse_assoc).instance_eval(&proxied_tenant_inverse_scope).first
        end
      end
    end
  end
end

ActiveRecord::Base.extend MultiTenant::ProxiesToTenant
