require 'test_helper'

class ActsAsTenantTest < Minitest::Test
  def teardown
    DatabaseCleaner.clean
  end

  def test_acts_as_tenant_false
    client = Class.new ActiveRecord::Base
    refute client.acts_as_tenant?
  end

  def test_acts_as_tenant_true
    client = Class.new ActiveRecord::Base do
      acts_as_tenant
    end
    assert client.acts_as_tenant?
  end

  def test_default_identifier
    client = Class.new ActiveRecord::Base do
      acts_as_tenant
    end
    assert_equal :code, client.tenant_identifier
  end

  def test_custom_identifier
    client = Class.new ActiveRecord::Base do
      acts_as_tenant using: :subdomain
    end
    assert_equal :subdomain, client.tenant_identifier
  end

  def test_gets_some_class_methods
    client = Class.new ActiveRecord::Base do
      acts_as_tenant using: :subdomain
    end
    assert client.respond_to? :current
    assert client.respond_to? :current=
    assert client.respond_to? :with_each_tenant
    assert client.respond_to? :with_tenant
    assert client.respond_to? :without_tenant
  end

  def test_current_seems_to_work
    client_class = Class.new ActiveRecord::Base do
      self.table_name = 'clients'
      acts_as_tenant using: :code
    end
    client = client_class.new(code: 'foo')
    assert_nil client_class.current

    client_class.current = client
    refute_nil client_class.current
    assert_equal client, client_class.current

    client_class.current = client_class.new(code: 'bar')
    refute_nil client_class.current
    refute_equal client, client_class.current

    client_class.create!(code: 'foo')
    client_class.current = 'foo'
    refute_nil client_class.current
    assert_equal 'foo', client_class.current.code

    client_class.current = 'bar'
    assert_nil client_class.current
  end

  def test_current_is_isolated_to_thread
    client_class = Class.new ActiveRecord::Base do
      self.table_name = 'clients'
      acts_as_tenant using: :code
    end
    client_class.create!(code: 'foo')

    Thread.new {
      client_class.current = 'foo'
      ActiveRecord::Base.connection_pool.checkin ActiveRecord::Base.connection
      refute_nil client_class.current
      assert_equal 'foo', client_class.current.code
    }.join

    assert_nil client_class.current
  end

  def test_current_is_isolated_to_thread_2
    client_class = Class.new ActiveRecord::Base do
      self.table_name = 'clients'
      acts_as_tenant using: :code
    end
    client_class.create!(code: 'foo')
    client_class.current = 'foo'

    Thread.new {
      assert_nil client_class.current
      client_class.current = nil
    }.join

    assert_equal 'foo', client_class.current.code
  end
end
