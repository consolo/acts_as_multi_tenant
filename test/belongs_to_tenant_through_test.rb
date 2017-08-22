require 'test_helper'

class BelongsToTenantThroughTest < Minitest::Test
  class Client < ActiveRecord::Base
    acts_as_tenant
  end

  class Membership < ActiveRecord::Base
    belongs_to_tenant :client
  end

  class User < ActiveRecord::Base
    has_many :memberships
    belongs_to_tenant_through :memberships
  end

  def teardown
    Client.current = nil
    DatabaseCleaner.clean
  end

  def test_belongs_to_tenant_through_false
    widget = Class.new ActiveRecord::Base
    refute widget.belongs_to_tenant_through?
  end

  def test_belongs_to_tenant_through_true
    assert User.belongs_to_tenant_through?
  end

  def test_through_config
    assert_equal 'Membership', User.delegate_class.name.split(/::/)[-1]
  end

  def test_isolation
    user = User.create!(name: 'Todd')
    Client.create!(code: 'acme', name: 'ACME')
    Client.create!(code: 'corp', name: 'Corp')
    Client.with_tenant('acme') { Membership.create!(user_id: user.id) }

    assert_equal 1, User.where(name: 'Todd').count
    assert_equal 1, Client.with_tenant('acme') { User.where(name: 'Todd').count }
    assert_equal 0, Client.with_tenant('corp') { User.where(name: 'Todd').count }
  end
end
