require 'test_helper'

class MultipleCurrentTest < Minitest::Test
  class Client < ActiveRecord::Base
    self.table_name = "clients"
    acts_as_tenant using: :code
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
    @client1 = Client.create!(uuid: SecureRandom.uuid, code: "foo")
    @client2 = Client.create!(uuid: SecureRandom.uuid, code: "bar")
    @client3 = Client.create!(uuid: SecureRandom.uuid, code: "zorp")
  end

  def teardown
    Client.current_tenants = []
    DatabaseCleaner.clean
  end

  def test_current_one
    assert_equal [], Client.current_tenants

    Client.current_tenants = [@client1]
    assert_equal [@client1], Client.current_tenants

    Client.current_tenants = [@client1.code]
    assert_equal [@client1], Client.current_tenants
  end

  def test_current_two
    assert_equal [], Client.current_tenants

    Client.current_tenants = [@client1, @client2]
    assert_equal [@client1, @client2], Client.current_tenants

    Client.current_tenants = [@client1.code, @client2.code]
    assert_equal [@client1, @client2], Client.current_tenants
  end

  def test_shared_code
    Client.delete_all
    @client1 = Client.create!(uuid: SecureRandom.uuid, code: "foo")
    @client2 = Client.create!(uuid: SecureRandom.uuid, code: "foo")
    @client3 = Client.create!(uuid: SecureRandom.uuid, code: "bar")

    assert_equal [], Client.current_tenants
    Client.current_tenant = "foo"
    assert_equal [@client1.uuid, @client2.uuid].sort, Client.current_tenants.map(&:uuid).sort
  end

  def test_doesnt_set_client_id
    Client.current_tenants = [@client1, @client2]
    w = Widget.new(name: "Foo")
    refute w.save
    assert_includes w.errors.full_messages, "Client can't be blank"
  end

  def test_sets_client_id_if_all_share_identifier
    @client1.update_column(:code, "foo")
    @client2.update_column(:code, "foo")

    Client.current_tenants = [@client1, @client2]
    w = Widget.new(name: "Foo")
    assert w.save
    assert_equal @client1.id, w.client_id
  end

  def test_overwrites_client_id_if_its_wrong
    @client1.update_column(:code, "foo")
    @client2.update_column(:code, "foo")

    Client.current_tenants = [@client1, @client2]
    w = Widget.new(name: "Foo")
    w.client_id = @client3.id
    assert w.save
    assert_equal @client1.id, w.client_id
  end

  def test_doesnt_overwrite_client_id_if_its_right
    @client1.update_column(:code, "foo")
    @client2.update_column(:code, "foo")

    Client.current_tenants = [@client1, @client2]
    w = Widget.new(name: "Foo")
    w.client_id = @client2.id
    assert w.save
    assert_equal @client2.id, w.client_id
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
      [200, {'Content-Type' => 'text/plain'}, ["#{Client.current_tenants.size} current clients"]]
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
      assert_equal %w(bar foo), Client.current_tenants.map(&:code).sort
      assert_equal %w(Bar Foo), Widget.all.pluck(:name).sort
      [200, {'Content-Type' => 'text/plain'}, ["Current are #{Client.current_tenants.map(&:code).sort.join ", "}"]]
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
