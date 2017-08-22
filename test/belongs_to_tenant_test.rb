require 'test_helper'
require 'securerandom'

class BelongsToTenantTest < Minitest::Test
  class Client < ActiveRecord::Base
    acts_as_tenant
  end

  class Widget < ActiveRecord::Base
    belongs_to_tenant :client
  end

  class UuidClient < ActiveRecord::Base
    self.table_name = 'clients'
    acts_as_tenant
  end

  class UuidWidget < ActiveRecord::Base
    self.table_name = 'widgets'
    belongs_to_tenant :client, class_name: 'UuidClient', primary_key: :uuid, foreign_key: :client_uuid
  end

  def teardown
    Client.current = nil
    UuidClient.current = nil
    DatabaseCleaner.clean
  end

  def test_belongs_to_tenant_false
    widget = Class.new ActiveRecord::Base
    refute widget.belongs_to_tenant?
  end

  def test_belongs_to_tenant_true
    assert Widget.belongs_to_tenant?
  end

  def test_basic_tenant_config
    assert_equal 'Client', Widget.tenant_class.name.split(/::/)[-1]
    assert_equal :client_id, Widget.tenant_foreign_key
    assert_equal :id, Widget.tenant_primary_key
  end

  def test_basic_tenant_config_isolates_records
    client1 = Client.create!(code: 'acme', name: 'ACME')
    client2 = Client.create!(code: 'corp', name: 'Corp')

    Client.with_tenant 'acme' do
      widget = Widget.create!(name: 'Foo')
      assert_equal client1.id, widget.client_id
    end

    Client.with_tenant 'corp' do
      widget = Widget.create!(name: 'Bar')
      assert_equal client2.id, widget.client_id
    end

    Client.with_tenant('acme') { assert_equal 1, Widget.count }
    Client.with_tenant('corp') { assert_equal 1, Widget.count }
    assert_equal 2, Widget.count
  end

  def test_advanced_tenant_config
    assert_equal 'UuidClient', UuidWidget.tenant_class.name.split(/::/)[-1]
    assert_equal :client_uuid,  UuidWidget.tenant_foreign_key
    assert_equal :uuid, UuidWidget.tenant_primary_key
  end

  def test_advanced_tenant_config_isolates_records
    client1 = UuidClient.create!(code: 'acme', name: 'ACME', uuid: SecureRandom.uuid)
    client2 = UuidClient.create!(code: 'corp', name: 'Corp', uuid: SecureRandom.uuid)

    UuidClient.with_tenant 'acme' do
      widget = UuidWidget.create!(name: 'Foo')
      assert_equal client1.uuid, widget.client_uuid
    end

    UuidClient.with_tenant 'corp' do
      widget = UuidWidget.create!(name: 'Bar')
      assert_equal client2.uuid, widget.client_uuid
    end

    UuidClient.with_tenant('acme') { assert_equal 1, UuidWidget.count }
    UuidClient.with_tenant('corp') { assert_equal 1, UuidWidget.count }
    assert_equal 2, UuidWidget.count
  end
end
