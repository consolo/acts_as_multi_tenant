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
  #     # A Proc that returns the tenant identifier that's used to look up the tenant. (i.e. :using option passed to acts_as_tenant)
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
      [404, {'Content-Type' => 'text/html', 'Content-Length' => (33 + x.to_s.size).to_s}, ['<h1>\'%s\' is not a valid tenant</h1>' % x.to_s]]
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
      self.identifier = opts.fetch :identifier
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
      tenant_identifier = identifier.(request)

      if (allowed_paths = globals[tenant_identifier])
        allowed = path_matches?(request, allowed_paths)
        return allowed ? @app.call(env) : not_found.(tenant_identifier)

      elsif (tenant = tenant_class.where({tenant_class.tenant_identifier => tenant_identifier}).first)
        tenant_class.current = tenant
        return @app.call env

      else
        return not_found.(tenant_identifier)
      end
    ensure
      tenant_class.current = nil
    end

    def path_matches?(req, paths)
      paths.any? { |(path, methods)|
        (path == req.path || path =~ req.path) && (methods == :any || methods.include?(req.request_method))
      }
    end

    # Infers and returns the tenant model class this middleware is handling
    def tenant_class
      @tenant_class ||= if self.model.respond_to?(:call)
        self.model.call
      elsif self.model.respond_to?(:constantize)
        self.model.constantize
      else
        self.model
      end
    end
  end
end
