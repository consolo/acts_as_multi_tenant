module MultiTenant
  module Impl
    #
    # An implementation where Tenant.current is an array of tenants. All queries will be scoped to ANY of these
    # tenants.
    #
    class MultipleCurrent
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
          current = tenant_class.current.map(&model.tenant_primary_key)
          current.any? ? model.where({model.tenant_foreign_key => current}) : model.where('1=1')
        }
      end

      def belongs_to_tenant_through_default_scope(model, ref)
        -> {
          tenants = model.delegate_class.tenant_class.current
          next model.where('1=1') if tenants.empty?

          # Using straight sql so we can JOIN against two columns. Otherwise one must go into "WHERE", and Arel would apply it to UPDATEs and DELETEs.
          quoted_tenant_ids = tenants.map { |t| model.connection.quote t.send model.delegate_class.tenant_primary_key }
          model.joins("INNER JOIN #{ref.klass.table_name} ON #{ref.klass.table_name}.#{ref.foreign_key}=#{model.table_name}.#{ref.association_primary_key} AND #{ref.klass.table_name}.#{ref.klass.tenant_foreign_key} IN (#{quoted_tenant_ids.join(',')})").
            distinct.
            readonly(false) # using "joins" makes records readonly, which we don't want
        }
      end

      def proxies_to_tenant_class_methods(_ref)
        raise MultiTenant::Impl::NotImplemented, "`proxies_to_tenant` is not currently supported for impl `:multiple`."
      end

      def matching_globals(records_or_identifiers, globals)
        records_or_identifiers.reduce([]) { |a, rec_or_id|
          id = rec_or_id.is_a?(tenant_class) ? rec_or_id.send(tenant_class.tenant_identifier) : rec_or_id
          a << globals[id] if globals.has_key? id
          a
        }
      end

      #
      # Class methods given to the tenant model.
      #
      module ActsAsTenantClassMethods
        def current?
          !current.nil? && current.any?
        end

        def resolve_tenant(records_or_identifiers)
          if records_or_identifiers.nil?
            []
          elsif records_or_identifiers.any? { |x| x.is_a? self }
            records_or_identifiers
          elsif records_or_identifiers.any?
            where({tenant_identifier => records_or_identifiers}).to_a
          else
            []
          end
        end
      end

      #
      # Instance methods given to tenant-owned models.
      #
      module BelongsToTenantInstanceMethods
        def self.included(model)
          model.class_eval do
            validate :ensure_assigned_to_current_tenants
          end
        end

        private

        #
        # If the tenant_id is set, make sure it's one of the current ones.
        #
        def ensure_assigned_to_current_tenants
          _tenants = self.class.tenant_class.current.map(&:id)
          _tenant_id = send self.class.tenant_foreign_key
          if _tenants.any? and _tenant_id.present? and !_tenants.include?(_tenant_id.to_s)
            errors.add(self.class.tenant_foreign_key, "is incorrect")
          end
        end
      end
    end
  end
end
