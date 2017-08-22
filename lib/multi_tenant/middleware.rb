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
  #     # (optional) Array of tentants that don't exist in the database, but should be allowed through anyway.
  #     # IMPORTANT For these, Tenant.current will be nil!
  #     global_identifiers: %w(global),
  #
  #     # (optional) Array of Strings or Regexps for paths that don't require a tenant. Only applies 
  #     # when the tenant isn't specified in the request - not when a given tenant can't be found.
  #     global_paths: [
  #       '/about',
  #       %r{^/api/v\d+/login$},
  #     ],
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

    # @return [Set<String>] array of "fake" identifiers that will be allowed through, but without setting a current tentant
    attr_accessor :global_identifiers

    # @return [Set<String>] An array of path strings that don't requite a tenant to be given
    attr_accessor :global_strings

    # @return [Set<String>] An array of path regexes that don't requite a tenant to be given
    attr_accessor :global_regexes

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
    # @param opts [Hash] Required: :model, :identifier. Optional: :global_identifiers, :global_paths, :not_found.
    #
    def initialize(app, opts)
      @app = app
      self.model = opts.fetch :model
      self.identifier = opts.fetch :identifier
      self.global_identifiers = Set.new(Array(opts[:global_identifiers]))
      self.global_strings = Set.new(Array(opts[:global_paths]).select { |x| x.is_a? String })
      self.global_regexes = Array(opts[:global_paths]).select { |x| x.is_a? Regexp }
      self.not_found = opts[:not_found] || DEFAULT_NOT_FOUND
    end

    # Rack request call
    def call(env)
      request = Rack::Request.new env
      tenant_identifier = identifier.(request)

      if tenant_identifier.blank?
        if global_strings.include? request.path or global_regexes.any? { |x| x =~ request.path }
          tenant_class.current = nil
          return @app.call env
        else
          return not_found.(tenant_identifier)
        end
      end

      tenant_record = tenant_identifier.present? ? tenant_class.where({tenant_class.tenant_identifier => tenant_identifier}).first : nil
      if tenant_record
        tenant_class.current = tenant_record
        return @app.call env
      elsif global_identifiers.include? tenant_identifier
        tenant_class.current = nil
        return @app.call env
      else
        return not_found.(tenant_identifier)
      end
    ensure
      tenant_class.current = nil
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
