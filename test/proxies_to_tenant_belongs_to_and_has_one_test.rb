require 'test_helper'

class ProxiesToTenantBelongsToAndHasOneTest < Minitest::Test
  class Client < ActiveRecord::Base
    has_one :license
    acts_as_tenant
  end

  class License < ActiveRecord::Base
    belongs_to :client, inverse_of: :license
    proxies_to_tenant :client
  end

  class Widget < ActiveRecord::Base
    belongs_to_tenant :license
  end

  def setup
    @c1 = Client.create!(code: 'megaA')
    @c2 = Client.create!(code: 'conglomA')
    @c3 = Client.create!(code: 'startup')
    @l1 = License.create!(description: 'Megacorp', client_id: @c1.id)
    @l2 = License.create!(description: 'Conglomerate', client_id: @c2.id)
    @l3 = License.create!(description: 'Lone Startup', client_id: @c3.id)
  end

  def teardown
    DatabaseCleaner.clean
  end

  def test_proxies_to_tenant_false
    refute Class.new(ActiveRecord::Base).proxies_to_tenant?
  end

  def test_proxies_to_tenant_true
    assert License.proxies_to_tenant?
  end

  def test_proxied_tenant_class_is_set
    assert_equal Client, License.proxied_tenant_class
  end

  def test_proxied_tenant_inverse_assoc_is_set
    assert_equal :license, License.proxied_tenant_inverse_assoc
  end

  def test_finds_current_proxy_record
    Client.with_tenant 'megaA' do
      assert_equal 'Megacorp', License.current.description
    end
    Client.with_tenant 'conglomA' do
      assert_equal 'Conglomerate', License.current.description
    end
    Client.with_tenant 'startup' do
      assert_equal 'Lone Startup', License.current.description
    end
    assert_nil License.current
  end

  def test_the_right_records_are_found
    Client.with_tenant('megaA') { Widget.create!(name: 'A') }
    Client.with_tenant('conglomA') { Widget.create!(name: 'B') }
    Client.with_tenant('startup') { Widget.create!(name: 'C') }

    Client.with_tenant 'megaA' do
      assert_equal %w(A), Widget.pluck(:name)
    end
    Client.with_tenant 'conglomA' do
      assert_equal %w(B), Widget.pluck(:name)
    end
    Client.with_tenant 'startup' do
      assert_equal %w(C), Widget.pluck(:name)
    end
  end
end
