require 'test_helper'

class MultipleCurrentTest < Minitest::Test
  class Client < ActiveRecord::Base
    self.table_name = "clients"
    acts_as_tenant using: :code, current: :multiple
  end

  class Widget < ActiveRecord::Base
    belongs_to_tenant :client
  end

  class Membership < ActiveRecord::Base
    belongs_to_tenant :client
  end

  class User < ActiveRecord::Base
    has_many :memberships
    belongs_to_tenant_through :memberships
  end

  def setup
    @client1 = Client.create!(code: "foo")
    @client2 = Client.create!(code: "bar")
    @client3 = Client.create!(code: "zorp")
  end

  def teardown
    Client.current = []
    DatabaseCleaner.clean
  end

  def test_current_one
    assert_equal [], Client.current

    Client.current = [@client1]
    assert_equal [@client1], Client.current

    Client.current = [@client1.code]
    assert_equal [@client1], Client.current
  end

  def test_current_two
    assert_equal [], Client.current

    Client.current = [@client1, @client2]
    assert_equal [@client1, @client2], Client.current

    Client.current = [@client1.code, @client2.code]
    assert_equal [@client1, @client2], Client.current
  end

  def test_isolates_records
    _widget1 = Widget.create!(client_id: @client1.id, name: 'Foo')
    _widget2 = Widget.create!(client_id: @client2.id, name: 'Bar')
    _widget3 = Widget.create!(client_id: @client3.id, name: 'Zorp')

    Client.with_tenant %w(foo bar) do
      assert_equal %w(Bar Foo), Widget.all.pluck(:name).sort
    end

    assert_equal %w(Bar Foo Zorp), Widget.all.pluck(:name).sort

    Client.with_tenant [@client1, @client2] do
      assert_equal %w(Bar Foo), Widget.all.pluck(:name).sort
    end

    assert_equal %w(Bar Foo Zorp), Widget.all.pluck(:name).sort
  end

  def test_isolates_through_records
    user = User.create!(name: 'Todd')
    Membership.create!(client_id: @client1.id, user_id: user.id)

    assert_equal 1, User.where(name: 'Todd').count
    assert_equal 1, Client.with_tenant(%w(foo bar)) { User.where(name: 'Todd').count }
    assert_equal 0, Client.with_tenant(%w(bar zorp)) { User.where(name: 'Todd').count }
  end

  def test_middleware_global_identifiers_match
    app = ->(env) {
      [200, {'Content-Type' => 'text/plain'}, ["#{Client.current.size} current clients"]]
    }
    ware = MultiTenant::Middleware.new(app, {
      model: Client,
      identifier: ->(req) { %w(foo api) },
      globals: {
        "api" => {
          /.*/ => :any
        }
      }
    })
    status, _header, body = ware.call({})
    assert_equal 200, status
    assert_equal "0 current clients", body[0]
  end

  def test_middleware_global_identifiers_dont_mismatch
    app = ->(env) {
      [200, {'Content-Type' => 'text/plain'}, ["junk"]]
    }
    ware = MultiTenant::Middleware.new(app, {
      model: Client,
      identifier: ->(req) { %w(wrong fake) },
      globals: {
        "api" => {
          /.*/ => :any
        }
      }
    })
    status, _header, body = ware.call({})
    assert_equal 404, status
    assert_match (/Invalid tenant: wrong, fake/i), body.join('')
  end

  def test_middleware_isolation
    _widget1 = Widget.create!(client_id: @client1.id, name: 'Foo')
    _widget2 = Widget.create!(client_id: @client2.id, name: 'Bar')
    _widget3 = Widget.create!(client_id: @client3.id, name: 'Zorp')

    app = ->(env) {
      assert_equal %w(bar foo), Client.current.map(&:code).sort
      assert_equal %w(Bar Foo), Widget.all.pluck(:name).sort
      [200, {'Content-Type' => 'text/plain'}, ["Current are #{Client.current.map(&:code).sort.join ", "}"]]
    }
    ware = MultiTenant::Middleware.new(app, {
      model: Client,
      identifier: ->(req) { %w(foo bar) }
    })
    status, _, body = ware.call({})
    assert_equal 200, status
    assert_match (/Current are bar, foo/i), body.join('')
  end
end
