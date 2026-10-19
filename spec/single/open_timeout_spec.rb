# frozen_string_literal: true

RSpec.describe 'open_timeout configuration' do
  let(:http_connection) { instance_double(Net::HTTP) }

  def net_http_start_kwargs(config)
    kwargs = nil
    allow(Net::HTTP).to receive(:start) do |*_args, **options|
      kwargs = options
      http_connection
    end
    ActiveRecord::Base.clickhouse_connection(config).send(:connect)
    kwargs
  end

  before do
    allow(http_connection).to receive(:keep_alive_timeout=)
    allow(http_connection).to receive(:read_timeout=)
  end

  # The connect and TLS handshake happen inside Net::HTTP.start, so the timeout only bounds them
  # when it is passed there rather than set on the connection afterwards.
  it 'passes open_timeout from the config to Net::HTTP.start' do
    kwargs = net_http_start_kwargs({ host: 'localhost', port: 8123, database: 'db', open_timeout: 3 })

    expect(kwargs).to include(open_timeout: 3, use_ssl: false)
  end

  it 'reads open_timeout from URL query params' do
    kwargs = net_http_start_kwargs({ url: 'clickhouse://localhost:8123/db?open_timeout=4' })

    expect(kwargs).to include(open_timeout: 4)
  end

  it "leaves Net::HTTP's default in place when open_timeout is not configured" do
    kwargs = net_http_start_kwargs({ host: 'localhost', port: 8123, database: 'db' })

    expect(kwargs).to include(use_ssl: false)
    expect(kwargs).not_to have_key(:open_timeout)
  end
end
