# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module Clickhouse
      module OID # :nodoc:
        class DateTime < Type::DateTime # :nodoc:

          def serialize(value)
            value = super
            return unless value
            # Rails 8 routes raw query values (e.g. integer epochs from defaults)
            # through #serialize; only Time-like values can be strftime'd, pass
            # anything else (Integer, etc.) through for ClickHouse to interpret.
            return value unless value.respond_to?(:strftime)

            value.strftime('%Y-%m-%d %H:%M:%S' + (@precision.present? && @precision > 0 ? ".%#{@precision}N" : ''))
          end

          def type_cast_from_database(value)
            value
          end

          # Type cast a value for schema dumping. This method is private, as we are
          # hoping to remove it entirely.
          def type_cast_for_schema(value) # :nodoc:
            value.inspect
          end

        end
      end
    end
  end
end
