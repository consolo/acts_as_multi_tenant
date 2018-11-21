# acts_as_multi_tenant

Keep multiple tenants in a single ActiveRecord database, and keep their data separate. Let's say the `Client` AR model represents your "tenants". Rack middleware will keep track of the "current" client in the request cycle which will automatically filter *all ActiveRecord queries* by that client. New records will automatically be associated to that client as well.

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

  # (required) Fetch the identifier of the current tenant from a Rack::Request object
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
  # or when a tenant isn't given.
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

## belongs_to_tenant_through

Maybe you have a model that indirectly belongs to several tenants. For example, a User may have multiple Memberships, each of which belongs to a different Client.

```ruby
class User < ActiveRecord::Base
  has_many :memberships
  belongs_to_tenant_through :memberships
end

class Membership < ActiveRecord::Base
  belongs_to_tenant :client
  belongs_to :user
end
```

## proxies_to_tenant

Let's say you need a layer of indirection between clients and their records, to allow multiple clients to all share their records. Let's call it a License: several clients can be signed onto a single license, and records are associated to the license itself. Therefore, all clients with that license will share a single pool of records.

See the full documenation for MultiTenant::ProxiesToTenant for a list of compatible association configurations. But here's on example of a valid configuration:

```ruby
# The tenant model that's hooked up to the Rack middleware and holds the "current" tenant
class Client < ActiveRecord::Base
  belongs_to :license
  acts_as_tenant
end

# The proxy model that's (potentially) associated with multiple tenants
class License < ActiveRecord::Base
  has_many :clients, inverse_of: :license
  proxies_to_tenant :clients
end

# Widets will be associated to a License (instead of a Client), therefore they are automatically
# shared with all Clients who use that License.
class Widget < ActiveRecord::Base
  belongs_to_tenant :license
  has_many :clients, through: :license # not required - just for clarity
end

# Splines, on the other hand, still belong directly to individual Clients like normal.
class Spline < ActiveRecord::Base
  belongs_to_tenant :client
end

# This is how it works behind the scenes
License.current == Client.current.license
```

## Multiple current tenants

Some applications may need to allow multiple current tenants at once. For example, a single user account may have access to multiple clients. `acts_as_multi_tenant` supports this with the `current: :multiple` option. When this is set, `Client.current` will be an array of clients. Queries will be filtered to ANY of those clients.

```ruby
class Client < ActiveRecord::Base
  acts_as_tenant using: :code, current: :multiple
end
```

When you add your middleware, your `identifier` option must also return an array:

```ruby
use MultiTenant::Middleware,
  model: -> { Client.active },

  identifier: ->(req) {
    req.params["clients"] || []
  }
```

## Testing

    bundle install
    bundle exec rake test

By default, bundler will install the latest (supported) version of ActiveRecord. To specify a version to test against, run:

    AR=4.2 bundle update activerecord
    bundle exec rake test

Look inside `Gemfile` to see all testable versions.
