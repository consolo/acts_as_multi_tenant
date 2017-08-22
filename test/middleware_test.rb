require 'test_helper'

class MiddlewareTest < Minitest::Test
  class Client < ActiveRecord::Base
    acts_as_tenant
    scope :active, -> { where(active: true) }
  end

  class Widget < ActiveRecord::Base
    belongs_to_tenant :client
  end

  def setup
    Client.with_tenant Client.create!(code: 'acme', name: 'ACME') do
      Widget.create!(name: 'Widget A')
    end
    Client.with_tenant Client.create!(code: 'corp', name: 'Corp') do
      Widget.create!(name: 'Widget B')
      Widget.create!(name: 'Widget C')
      Widget.create!(name: 'Widget D')
    end
  end

  def teardown
    Client.current = nil
    DatabaseCleaner.clean
  end

  def test_model_works_as_class
    ware = MultiTenant::Middleware.new(->(env) {}, {
      model: Client,
      identifier: ->(req) { 'foo' }
    })
    assert_equal Client, ware.tenant_class
  end

  def test_model_works_as_scope
    ware = MultiTenant::Middleware.new(->(env) {}, {
      model: Client.active,
      identifier: ->(req) { 'foo' }
    })
    assert_equal Client.active, ware.tenant_class
  end

  def test_model_works_as_string
    ware = MultiTenant::Middleware.new(->(env) {}, {
      model: 'MiddlewareTest::Client',
      identifier: ->(req) { 'foo' }
    })
    assert_equal Client, ware.tenant_class
  end

  def test_model_works_as_proc
    ware = MultiTenant::Middleware.new(->(env) {}, {
      model: -> { Client },
      identifier: ->(req) { 'foo' }
    })
    assert_equal Client, ware.tenant_class
  end

  def test_default_not_found
    ware = MultiTenant::Middleware.new(->(env) {}, {
      model: Client,
      identifier: ->(req) { 'foo' }
    })
    status, _, body = ware.call({})
    assert_equal 404, status
    assert_match (/'foo' is not a valid tenant/i), body.join('')
  end

  def test_custom_not_found
    ware = MultiTenant::Middleware.new(->(env) {}, {
      model: Client,
      identifier: ->(req) { 'foo' },
      not_found: ->(x) {
        [400, {'Content-Type' => 'application/json'}, [{errors: ["Invalid client '#{x}'!"]}.to_json]]
      }
    })
    status, headers, body = ware.call({})
    assert_equal 400, status
    assert_equal 'application/json', headers['Content-Type']
    assert_match (/Invalid client 'foo'!/i), body.join('')
  end

  def test_global_identifiers_match
    app = ->(env) {
      [200, {'Content-Type' => 'text/plain'}, ["Current client = #{Client.current || 'NULL'}"]]
    }
    ware = MultiTenant::Middleware.new(app, {
      model: Client,
      identifier: ->(req) { 'api' },
      global_identifiers: %w(api)
    })
    status, _header, body = ware.call({})
    assert_equal 200, status
    assert_equal "Current client = NULL", body[0]
  end

  def test_global_identifiers_dont_mismatch
    app = ->(env) {
      [200, {'Content-Type' => 'text/plain'}, ["junk"]]
    }
    ware = MultiTenant::Middleware.new(app, {
      model: Client,
      identifier: ->(req) { 'foo' },
      global_identifiers: %w(api)
    })
    status, _header, body = ware.call({})
    assert_equal 404, status
    assert_match (/'foo' is not a valid tenant/i), body.join('')
  end

  def test_global_path_strings
    app = ->(env) {
      [200, {'Content-Type' => 'text/plain'}, ['Yay!']]
    }
    ware = MultiTenant::Middleware.new(app, {
      model: Client,
      identifier: ->(req) { nil },
      global_paths: ['/about']
    })
    status, headers, body = ware.call({'PATH_INFO' => '/about'})
    assert_equal 200, status
    assert_equal 'text/plain', headers['Content-Type']
    assert_match (/yay/i), body.join('')
  end

  def test_global_path_regexes
    app = ->(env) {
      [200, {'Content-Type' => 'text/plain'}, ['Yay!']]
    }
    ware = MultiTenant::Middleware.new(app, {
      model: Client,
      identifier: ->(req) { nil },
      global_paths: [%r{^/v\d+/about$}]
    })
    status, headers, body = ware.call({'PATH_INFO' => '/v2/about'})
    assert_equal 200, status
    assert_equal 'text/plain', headers['Content-Type']
    assert_match (/yay/i), body.join('')
  end

  def test_global_paths_fail
    app = ->(env) {
      [200, {'Content-Type' => 'text/plain'}, ['Yay!']]
    }
    ware = MultiTenant::Middleware.new(app, {
      model: Client,
      identifier: ->(req) { nil },
      global_paths: ['/about', %r{^/v\d+/about$}]
    })
    status, _, _ = ware.call({'PATH_INFO' => '/foo/about'})
    assert_equal 404, status
  end

  def test_tenant_isolation
    app = ->(env) {
      refute_nil Client.current
      assert_equal 'acme', Client.current.code
      assert_equal 1, Widget.count
      [200, {'Content-Type' => 'text/plain'}, ["Current is #{Client.current.code}"]]
    }
    ware = MultiTenant::Middleware.new(app, {
      model: Client,
      identifier: ->(req) { 'acme' }
    })
    status, _, body = ware.call({})
    assert_equal 200, status
    assert_match (/Current is acme/i), body.join('')
  end

  def test_tenant_isolation_in_sequence
    app = ->(env) {
      [200, {'Content-Type' => 'text/plain'}, ["#{Client.current.try(:code)}:#{Widget.count}"]]
    }
    ware = MultiTenant::Middleware.new(app, {
      model: Client,
      identifier: ->(req) { req.env['CLIENT_CODE'] }
    })

    status, headers, body = ware.call({'CLIENT_CODE' => 'acme'})
    assert_equal 200, status
    assert_equal "acme:1", body.join('')
    assert_nil Client.current

    status, headers, body = ware.call({'CLIENT_CODE' => 'corp'})
    assert_equal 200, status
    assert_equal "corp:3", body.join('')
    assert_nil Client.current
  end

  def test_global_paths_arent_isolated
    app = ->(env) {
      [200, {'Content-Type' => 'text/plain'}, ["#{Client.current.try(:code)}:#{Widget.count}"]]
    }
    ware = MultiTenant::Middleware.new(app, {
      model: Client,
      identifier: ->(req) { req.env['CLIENT_CODE'] },
      global_paths: ['/about']
    })

    status, _, body = ware.call({'PATH_INFO' => '/about'})
    assert_equal 200, status
    assert_equal ":4", body.join('')
    assert_nil Client.current
  end

  def test_scope_doesnt_break_anything
    app = ->(env) {
      [200, {'Content-Type' => 'text/plain'}, ["#{Client.current.try(:code)}:#{Widget.count}"]]
    }
    ware = MultiTenant::Middleware.new(app, {
      model: -> { Client.active },
      identifier: ->(req) { req.env['CLIENT_CODE'] }
    })

    status, _, body = ware.call({'CLIENT_CODE' => 'corp'})
    assert_equal 200, status
    assert_equal "corp:3", body.join('')
    assert_nil Client.current
  end

  def test_scope_actually_works
    app = ->(env) {
      [200, {'Content-Type' => 'text/plain'}, ["#{Client.current.try(:code)}:#{Widget.count}"]]
    }
    ware = MultiTenant::Middleware.new(app, {
      model: -> { Client.active },
      identifier: ->(req) { req.env['CLIENT_CODE'] }
    })
    client = Client.find_by(code: 'corp')
    client.update_column(:active, false)

    status, _, _ = ware.call({'CLIENT_CODE' => client.code})
    assert_equal 404, status
    assert_nil Client.current
  end
end
