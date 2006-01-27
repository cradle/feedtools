class AddFeedToolsTables < ActiveRecord::Migration
  def self.up
    puts "Adding feed cache table..."
    create_table :feeds do |t|
      t.column :url, :string
      t.column :title, :string
      t.column :link, :string
      t.column :feed_data, :text
      t.column :feed_data_type, :string
      t.column :http_headers, :text
      t.column :last_retrieved, :datetime
    end
  end

  def self.down
    puts "Dropping feed cache table..."
    drop_table :feeds
  end
end
