# frozen_string_literal: true

# Regression coverage for stale keep-alive sockets.
#
# When a previous response is aborted mid-read (e.g. a timeout raised while
# Net::HTTP is reading the body), unread bytes stay buffered on the persistent
# connection and the next query fails with Net::HTTPBadResponse ("wrong status
# line"). Net::HTTP closes the socket before raising, so a retry reconnects
# and succeeds.
RSpec.describe 'ActiveRecord::ConnectionAdapters::Clickhouse::SchemaStatements#raw_execute retries' do
  let(:connection) { ActiveRecord::Base.connection }
  let(:http) { connection.instance_variable_get(:@connection) }

  it 'retries and succeeds when the first attempt raises Net::HTTPBadResponse' do
    calls = 0
    allow(http).to receive(:post).and_wrap_original do |original, *args|
      calls += 1
      raise Net::HTTPBadResponse, 'wrong status line: "c8e74\"]"' if calls == 1

      original.call(*args)
    end

    expect(connection.select_value('SELECT 1').to_i).to eq(1)
    expect(calls).to eq(2)
  end

  it 'raises the original error when retries are exhausted' do
    allow(http).to receive(:post).and_raise(Net::HTTPBadResponse, 'wrong status line: "c8e74\"]"')

    expect { connection.select_value('SELECT 1') }
      .to raise_error(ActiveRecord::ActiveRecordError, /wrong status line/)
  end
end
