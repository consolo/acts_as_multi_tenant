module MultiTenant
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
      reflection = reflections[association_name.to_s]
      raise "`proxies_to_tenant :#{association_name}`: unable to find association `:#{association_name}`. Make sure you create the association *first*." if reflection.nil?
      raise "`proxies_to_tenant :#{association_name}`: #{reflection.klass.name} must use `acts_as_tenant`" if !reflection.klass.acts_as_tenant?
      raise "`proxies_to_tenant :#{association_name}`: the `:#{association_name}` association must use the `:inverse_of` option." if reflection.inverse_of.nil?

      cattr_accessor :proxied_tenant_class, :proxied_tenant_inverse_assoc, :proxied_tenant_inverse_scope
      self.proxied_tenant_class = reflection.klass
      self.proxied_tenant_inverse_assoc = reflection.inverse_of.name
      self.proxied_tenant_inverse_scope = scope

      impl = self.proxied_tenant_class.multi_tenant_impl
      self.extend impl.proxies_to_tenant_class_methods(reflection)
      self.extend ClassMethods
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
    # Class methods given to proxies.
    #
    module ClassMethods
      def multi_tenant_impl
        proxied_tenant_class.multi_tenant_impl
      end
    end
  end
end

ActiveRecord::Base.extend MultiTenant::ProxiesToTenant
