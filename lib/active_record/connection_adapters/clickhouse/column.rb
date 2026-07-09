module ActiveRecord
  module ConnectionAdapters
    module Clickhouse
      DescribedColumn =
        Data.define(:name, :sql_type, :default_type, :default_expression, :comment, :codec) do
          def ephemeral?
            default_type.to_s.downcase == 'ephemeral'
          end
        end

      class Column < ActiveRecord::ConnectionAdapters::Column
        attr_reader :codec, :default_kind

        def initialize(*, codec: nil, default_kind: nil, **)
          super
          @codec = codec
          @default_kind = ActiveSupport::StringInquirer.new(default_kind.to_s.downcase.presence || 'none')
        end

        def virtual?
          default_kind.materialized? || default_kind.alias?
        end

        # Base Column equality ignores our extra attributes, so ActiveRecord's
        # deduplication registry would intern a plain column and a MATERIALIZED
        # column of the same name/type as one object — leaking virtual? onto
        # the plain column and silently dropping it from INSERTs.
        def ==(other)
          super &&
            other.respond_to?(:default_kind) && default_kind.to_s == other.default_kind.to_s &&
            other.respond_to?(:codec) && codec == other.codec
        end
        alias eql? ==

        def hash
          [super, default_kind.to_s, codec].hash
        end

        private

        def deduplicated
          self
        end
      end
    end
  end
end
