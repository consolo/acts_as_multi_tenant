require 'otr-activerecord'
ActiveRecord::Base.logger = nil

$test_db = Tempfile.new %w(acts_as_multi_tenant_test .sqlite3)
OTR::ActiveRecord.configure_from_hash!(adapter: 'sqlite3', database: $test_db.path, encoding: 'utf8', pool: 5, timeout: 5000)

ActiveRecord::Base.connection.instance_eval do
  create_table :clients do |t|
    t.string :uuid
    t.integer :license_id
    t.boolean :active, null: false, default: true
    t.string :code
    t.string :name
  end

  create_table :licenses do |t|
    t.integer :client_id
    t.string :description
    t.string :contact
    t.integer :seats
    t.date :start_date
    t.date :end_date
  end

  create_table :widgets do |t|
    t.integer :client_id
    t.string :client_uuid
    t.integer :license_id
    t.string :name
  end

  create_table :users do |t|
    t.string :name
  end

  create_table :memberships do |t|
    t.integer :client_id
    t.integer :user_id
  end
end
