# frozen_string_literal: true

RSpec.describe ActiveRecord::ConnectionAdapters::Clickhouse::Column do
  def build_column(default_kind: nil, codec: nil)
    metadata = ActiveRecord::ConnectionAdapters::SqlTypeMetadata.new(
      sql_type: 'String', type: :string
    )
    args = ['city_name']
    args << ActiveModel::Type::String.new if ActiveRecord.version >= Gem::Version.new('8.1')
    args += [nil, metadata, false, nil]
    described_class.new(*args, codec: codec, default_kind: default_kind)
  end

  it 'does not treat a materialized column as equal to a plain column' do
    plain = build_column
    materialized = build_column(default_kind: 'MATERIALIZED')

    expect(plain).not_to eq(materialized)
    expect(plain.hash).not_to eq(materialized.hash)
  end

  it 'does not deduplicate a plain column into a materialized column' do
    materialized = build_column(default_kind: 'MATERIALIZED').deduplicate
    plain = build_column.deduplicate

    expect(plain).not_to be_virtual
    expect(plain).not_to equal(materialized)
  end

  it 'treats identical columns as equal' do
    expect(build_column).to eq(build_column)
    expect(build_column.hash).to eq(build_column.hash)
  end

  it 'does not treat columns with different codecs as equal' do
    expect(build_column(codec: 'ZSTD')).not_to eq(build_column)
  end
end
