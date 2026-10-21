# frozen_string_literal: true

# Upstream's connection_hardening_spec covers passing open_timeout to Net::HTTP.start.
RSpec.describe 'connect timeout' do
  # Callers rescue ActiveRecord errors to fall back, so a connect timeout has to arrive as one.
  # The adapter connects eagerly in initialize, outside the read-query retry in internal_exec_query.
  it 'raises ConnectionNotEstablished when the connect times out' do
    allow(Net::HTTP).to receive(:start).and_raise(Net::OpenTimeout, 'execution expired')
    config = { host: 'localhost', port: 8123, database: 'db', open_timeout: 1 }

    expect { ActiveRecord::Base.clickhouse_connection(config) }.to raise_error(ActiveRecord::ConnectionNotEstablished, /execution expired/)
  end
end
