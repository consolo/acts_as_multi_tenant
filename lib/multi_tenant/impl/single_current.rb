module MultiTenant
  module Impl
    #
    # An implementation where Tenant.current is set to the current tenant, or nil. 
    #
    class SingleCurrent
      attr_reader :tenant_class

      def initialize(tenant_class)
        @tenant_class = tenant_class
      end

      def acts_as_tenant_class_methods
        ActsAsTenantClassMethods
      end

      def belongs_to_tenant_instance_methods
        BelongsToTenantInstanceMethods
      end

      def belongs_to_tenant_default_scope(model)
        -> {
          current = model.tenant_class.current
          current ? model.where({model.tenant_foreign_key => current.send(model.tenant_primary_key)}) : model.where('1=1')
        }
      end

      def belongs_to_tenant_through_default_scope(model, ref)
        -> {
          tenant = model.delegate_class.tenant_class.current
          next model.where('1=1') if tenant.nil?

          # Using straight sql so we can JOIN against two columns. Otherwise one must go into "WHERE", and Arel would apply it to UPDATEs and DELETEs.
          quoted_tenant_id = model.connection.quote tenant.send model.delegate_class.tenant_primary_key
          model.joins("INNER JOIN #{ref.klass.table_name} ON #{ref.klass.table_name}.#{ref.foreign_key}=#{model.table_name}.#{ref.association_primary_key} AND #{ref.klass.table_name}.#{ref.klass.tenant_foreign_key}=#{quoted_tenant_id}").
            readonly(false) # using "joins" makes records readonly, which we don't want
        }
      end

      def proxies_to_tenant_class_methods(ref)
        case [ref.macro, ref.inverse_of.macro]
        when [:has_many, :belongs_to], [:has_one, :belongs_to], [:belongs_to, :has_one]
          ProxiesToTenantSingularInverseAssociation
        else
          raise MultiTenant::Impl::NotImplemented, "`proxies_to_tenant` does not currently support `#{ref.macro}` associations with `#{ref.inverse_of.macro} inverses."
          ProxiesToTenantPluralInverseAssociation
        end
      end

      def matching_globals(record_or_identifier, globals)
        id = record_or_identifier.is_a?(tenant_class) ? record_or_identifier.send(tenant_class.tenant_identifier) : record_or_identifier
        globals.has_key?(id) ? [globals[id]] : []
      end

      #
      # Class methods given to the tenant model.
      #
      module ActsAsTenantClassMethods
        def current?
          !current.nil?
        end

        def resolve_tenant(record_or_identifier)
          if record_or_identifier.is_a? self
            record_or_identifier
          elsif record_or_identifier
            where({tenant_identifier => record_or_identifier}).first
          else
            nil
          end
        end
      end

      #
      # Instance methods given to tenant-owned models.
      #
      module BelongsToTenantInstanceMethods
        def self.included(model)
          model.class_eval do
            before_validation :assign_to_tenant
          end
        end

        private

        #
        # Assign this model to the current tenant (if any)
        #
        def assign_to_tenant
          if self.class.tenant_class.current
            current_tenant_id = self.class.tenant_class.current.send(self.class.tenant_primary_key)
            send "#{self.class.tenant_foreign_key}=", current_tenant_id
          end
        end
      end

      #
      # Class methods for tenant proxies that have a singular inverse association (i.e. belongs_to or has_one).
      #
      module ProxiesToTenantSingularInverseAssociation
        # Returns the current record of the proxy model
        def current
          if (tenant = proxied_tenant_class.current)
            tenant.send proxied_tenant_inverse_assoc
          end
        end
      end

      #
      # Class methods for tenant proxies that have a plural inverse association (i.e. has_many).
      # NOTE These are just some thoughts on *maybe* how to support this if we ever need it.
      #
      module ProxiesToTenantPluralInverseAssociation
        # Returns the current record of the proxy model
        def current
          raise MultiTenant::Impl::NotImplemented, "needs confirmed"
          if (tenant = proxied_tenant_class.current)
            tenant.send(proxied_tenant_inverse_assoc).instance_eval(&proxied_tenant_inverse_scope).first
          end
        end
      end
    end
  end
end
