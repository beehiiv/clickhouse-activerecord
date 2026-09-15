# frozen_string_literal: true

# processed_response returns only the response body, so X-ClickHouse-Summary was previously
# readable only inside exec_delete.
RSpec.describe 'ActiveRecord::ConnectionAdapters::Clickhouse::SchemaStatements#last_summary' do
  let(:connection) { ActiveRecord::Base.connection }

  before do
    connection.execute('DROP TABLE IF EXISTS last_summary_items')
    connection.execute('CREATE TABLE last_summary_items (n UInt32) ENGINE = MergeTree ORDER BY n')
  end

  after { connection.execute('DROP TABLE IF EXISTS last_summary_items') }

  it 'reports the rows an insert wrote' do
    connection.execute('INSERT INTO last_summary_items SELECT number FROM numbers(37)')

    expect(connection.last_summary['written_rows'].to_i).to eq(37)
  end

  it 'reports no written rows for a select' do
    connection.execute('SELECT 1')

    expect(connection.last_summary['written_rows'].to_i).to eq(0)
  end

  it 'reports the rows a select read' do
    connection.execute('INSERT INTO last_summary_items SELECT number FROM numbers(12)')
    connection.execute('SELECT * FROM last_summary_items')

    expect(connection.last_summary['read_rows'].to_i).to eq(12)
  end

  it 'describes the latest statement rather than an earlier one' do
    connection.execute('INSERT INTO last_summary_items SELECT number FROM numbers(50)')
    connection.execute('SELECT 1')

    expect(connection.last_summary['written_rows'].to_i).to eq(0)
  end

  it 'keeps one thread summary out of another' do
    connection.execute('INSERT INTO last_summary_items SELECT number FROM numbers(9)')

    other = Thread.new { Thread.current[:summary] = connection.last_summary }
    other.join

    expect(other[:summary]).to be_nil
    expect(connection.last_summary['written_rows'].to_i).to eq(9)
  end
end
