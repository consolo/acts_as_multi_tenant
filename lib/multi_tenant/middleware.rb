require 'set'
require 'rack'

module MultiTenant
  #
  # Rack middleware that sets the current tenant during each request (in a thread-safe manner). During a request,
  # you can access the current tenant from "Tenant.current", where 'Tenant' is name of the ActiveRecord model.
  #
  #   use MultiTenant::Middleware,
  #     # The ActiveRecord model that represents the tenants. Or a Proc returning it, or it's String name.
  #     model: -> { Tenant },
  #
  #     # A Proc that returns the tenant identifier that's used to look up the tenant. (i.e. :using option passed to acts_as_tenant).
  #     # Also aliased as "identifiers".
  #     identifier: ->(req) { req.host.split(/\./)[0] },
  #
  #     # (optional) A Hash of fake identifiers that should be allowed through. Each identifier will have a
  #     # Hash of Regex paths with Symbol http methods (or arrays thereof), or :any. These path & method combos
  #     # will be allowed through when the identifier matches. All others will be blocked.
  #     # IMPORTANT Tenant.current will be nil!
  #     globals: {
  #       "global" => {
  #         %r{\A/api/widgets/} => :any,
  #         %r{\A/api/splines/} => [:get, :post]
  #       }
  #     },
  #
  #     # (optional) Returns a Rack response when a tenant couldn't be found in the db, or when
  #     # a tenant isn't given (and isn't in the `global_paths` list)
  #     not_found: ->(x) {
  #       body = {errors: ["'#{x}' is not a valid tenant. I'm sorry. I'm so sorry."]}.to_json
  #       [400, {'Content-Type' => 'application/json', 'Content-Length' => body.size.to_s}, [body]]
  #     }
  #
  class Middleware
    # @return [Proc|String|Class] The ActiveRecord model that holds all the tenants
    attr_accessor :model

    # @return [Proc] A Proc which accepts a Rack::Request and returns some identifier for tenant lookup
    attr_accessor :identifier

    # @return [Hash] Global identifiers and their allowed paths and methods
    attr_accessor :globals

    # @return [Proc] A Proc which accepts a (non-existent or blank) tenant identifier and returns a rack response describing
    # the error. Defaults to a 404 and some shitty html.
    attr_accessor :not_found

    # Default Proc for the not_found option
    DEFAULT_NOT_FOUND = ->(x) {
      body = "<h1>Invalid tenant: #{Array(x).map(&:to_s).join ', '}</h1>"
      [404, {'Content-Type' => 'text/html', 'Content-Length' => body.size.to_s}, [body]]
    }

    #
    # Initialize a new multi tenant Rack middleware.
    #
    # @param app the Rack app
    # @param opts [Hash] Required: :model, :identifier. Optional: :globals, :not_found.
    #
    def initialize(app, opts)
      @app = app
      self.model = opts.fetch :model
      self.identifier = opts[:identifier] || opts[:identifiers] || raise("Option :identifier or :identifiers is required")
      self.globals = (opts[:globals] || {}).reduce({}) { |a, (global, patterns)|
        a[global] = patterns.reduce({}) { |aa, (path, methods)|
          aa[path] = methods == :any ? :any : Set.new(Array(methods).map { |m| m.to_s.upcase })
          aa
        }
        a
      }
      self.not_found = opts[:not_found] || DEFAULT_NOT_FOUND
    end

    # Rack request call
    def call(env)
      tenant_class.current = nil

      request = Rack::Request.new env
      id_resp = identifier.(request)
      records_or_identifiers = Array(id_resp)

      if (matching = matching_globals(records_or_identifiers)).any?
        allowed = matching.any? { |allowed_paths|
          path_matches?(request, allowed_paths)
        }
        return @app.call(env) if allowed

        ids = identifiers records_or_identifiers
        return not_found.(id_resp.is_a?(Array) ? ids : ids[0])

      elsif (tenant_query.current_tenants = records_or_identifiers) and tenant_class.current?
        return @app.call env

      else
        ids = identifiers records_or_identifiers
        return not_found.(id_resp.is_a?(Array) ? ids : ids[0])
      end
    ensure
      tenant_class.current = nil
    end

    def path_matches?(req, paths)
      paths.any? { |(path, methods)|
        path === req.path && (methods == :any || methods.include?(req.request_method))
      }
    end

    def matching_globals(records_or_identifiers)
      identifiers(records_or_identifiers).reduce([]) { |a, id|
        a << globals[id] if globals.has_key? id
        a
      }
    end

    def identifiers(records_or_identifiers)
      records_or_identifiers.map { |x|
        if x.class.respond_to?(:model_name) and x.class.model_name.to_s == tenant_class.model_name.to_s
          x.send tenant_class.tenant_identifier
        else
          x.to_s
        end
      }
    end

    def tenant_class(m = self.model)
      @tenant_class ||= if m.respond_to?(:call)
        tenant_class m.call
      elsif m.respond_to? :constantize
        m.constantize
      elsif m.respond_to? :model
        m.model
      else
        m
      end
    end

    def tenant_query
      @tenant_query ||= if self.model.respond_to?(:call)
        self.model.call
      elsif self.model.respond_to? :constantize
        self.model.constantize
      else
        self.model
      end
    end
  end
end
