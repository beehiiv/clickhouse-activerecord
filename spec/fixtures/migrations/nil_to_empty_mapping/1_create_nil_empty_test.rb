# frozen_string_literal: true

class CreateNilEmptyTest < ActiveRecord::Migration[7.1]
  def up
    create_table :nil_empty_test, id: false, options: 'MergeTree ORDER BY body' do |t|
      t.string :body, null: false
      t.string :optional, null: true
      t.integer :counter, null: false
    end
  end
end
