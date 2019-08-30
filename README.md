# acts_as_multi_tenant

Keep multiple tenants in a single ActiveRecord database and keep their data separate.

Let's say the `Client` AR model represents your "tenants". Rack middleware will keep track of the current client in the request cycle (in a thread-safe way) which will automatically filter *all ActiveRecord queries* by that client. New records will automatically be associated to that client as well.

There are 3 main components:

* `MultiTenant::Middleware` Rack middleware to wrap the request with the current tenant
* `acts_as_tenant` ActiveRecord macro to specify which model houses all those tenants
* `belongs_to_tenant` Extention of the ActiveRecord `belongs_to` macro to specify that a model belongs to a tenant

## MultiTenant::Middleware

Add the middleware in **config.ru** or wherever you add middleware.

```ruby
use MultiTenant::Middleware,
  # (required) The tenant model we want to set "current" on.
  # Can be the class String name, a Proc, the class itself, or the class + a scope.
  model: -> { Client.active },

  # (required) Fetch the identifier of the current tenant from a Rack::Request object.
  # In this example it's the subdomain, but it could be anything.
  identifier: ->(req) { req.host.split(/\./)[0] },

  # (optional) A Hash of fake identifiers that should be allowed through. Each identifier will have a
  # Hash of Regex paths with Symbol http methods (or arrays thereof), or :any. These path & method combos
  # will be allowed through when the identifier matches. All others will be blocked.
  # IMPORTANT Tenant.current will be nil!
  globals: {
    "global" => {
      %r{\A/api/widgets/} => :any,
      %r{\A/api/splines/} => [:get, :post]
    }
  },

  # (optional) Returns a Rack response when a tenant couldn't be found in the db (excluding globals),
  # or when a tenant isn't given. This example contains the default response.
  not_found: ->(x) {
    body = {errors: ["'%s' is not a valid tenant!" % x]}.to_json
    [400, {'Content-Type' => 'application/json', 'Content-Length' => body.size.to_s}, [body]]
  }
```

## acts_as_tenant

Let's say that your tenants are stored with the `Client` model, and the `code` column stores each client's unique lookup/identifier value.

```ruby
class Client < ActiveRecord::Base
  acts_as_tenant using: :code
end
```

## belongs_to_tenant

Now tell your models that they belong to a tenant. You can use all the normal ActiveRecord `belongs_to` arguments, including the scope `Proc` and the options `Hash`.

```ruby
class Widget < ActiveRecord::Base
  belongs_to_tenant :client
end

class Spline < ActiveRecord::Base
  belongs_to_tenant :client
end
```

That's it! As long as the Rack middlware is set up, and your code is running within the request/response cycle, your queries will automatically filter by the current Client, and new records will automatically be assiciated to it.

**Manual usage**

For code that doesn't run during the request/response cycle, there are manual ways to get and set the current tenant.

```ruby
# Get the current client
client = Client.current_tenant

# Set the current client
Client.current_tenant = client
# Or
Client.current_tenant = "the client's code"

Client.with_tenant "code" do
  # Client.current_tenant will be set in this block,
  # then set back to whatever it was before
end

Client.without_tenant do
  # Client.current_tenant will be UNset in this block,
  # then set back to whatever it was before
end

Client.with_each_tenant do
  # The block will be called N times, one for each
  # tenant. Client.current_tenant will be set to that
  # client.
end
```

## Multiple current tenants

Some applications may need to allow multiple current tenants at once. For example, a single user may have access to multiple clients. `acts_as_multi_tenant` has an API that allows getting and setting of multiple tenants. Queries will be filtered by ANY of them. Keep in mind that when creating new records the tenant_id column cannot automatically be set, since it doesn't know which tenant to use.

When you add your middleware, the `identifiers` option must return an array:

```ruby
use MultiTenant::Middleware,
  model: -> { Client.active },

  identifiers: ->(req) {
    req.params["clients"] || []
  }
```

In application code, use the following pluralized methods instead of their singularized counterparts:

```ruby
Client.current_tenants = ["acme", "foo"]

Client.with_tenants ["acme", "foo"] do
  # do stuff
end

Client.without_tenants do
  # do stuff
end
```

## Testing

    bundle install
    bundle exec rake test

By default, bundler will install the latest (supported) version of ActiveRecord. To specify a version to test against, run:

    AR=4.2 bundle update activerecord
    bundle exec rake test

Look inside `Gemfile` to see all testable versions.
