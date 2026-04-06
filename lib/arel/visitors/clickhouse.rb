# frozen_string_literal: true

require 'arel/visitors/to_sql'

module Arel
  module Visitors
    class Clickhouse < ::Arel::Visitors::ToSql

      SETTING_KEY_NON_WORD_CHARS = /\W+/
      CH_TYPE_ENUM_PREFIX = /\AEnum\d?\b/i
      CH_TYPE_SUPPORTS_EMPTY = /\A(String|FixedString|Array|Map|UUID|Tuple|IPv[46])/i
      CH_TYPE_NULLABLE_WRAPPER = /\ANullable\((.+)\)\z/m
      CH_TYPE_LOW_CARDINALITY_WRAPPER = /\ALowCardinality\((.+)\)\z/m

      def compile(node, collector = Arel::Collectors::SQLString.new)
        @delete_or_update = false
        super
      end

      def aggregate(name, o, collector)
        # replacing function name for materialized view
        if o.expressions.first && o.expressions.first != '*' && !o.expressions.first.is_a?(String) && o.expressions.first.relation&.is_view
          super("#{name.downcase}Merge", o, collector)
        else
          super
        end
      end

      # https://clickhouse.com/docs/en/sql-reference/statements/delete
      # DELETE and UPDATE in ClickHouse working only without table name
      def visit_Arel_Attributes_Attribute(o, collector)
        unless @delete_or_update
          join_name  = o.relation.table_alias || o.relation.name
          collector << quote_table_name(join_name) << '.'
        end
        collector << quote_column_name(o.name)
      end

      def visit_Arel_Nodes_SelectOptions(o, collector)
        maybe_visit o.limit_by, collector
        maybe_visit o.settings, super
      end

      def visit_Arel_Nodes_UpdateStatement(o, collector)
        @delete_or_update = true
        o = prepare_update_statement(o)

        collector << 'ALTER TABLE '
        collector = visit o.relation, collector
        collect_nodes_for o.values, collector, ' UPDATE '
        collect_nodes_for o.wheres, collector, ' WHERE ', ' AND '
        collect_nodes_for o.orders, collector, ' ORDER BY '
        maybe_visit o.limit, collector
      end

      def visit_Arel_Nodes_DeleteStatement(o, collector)
        @delete_or_update = true
        super
      end

      def visit_Arel_Nodes_Final(o, collector)
        visit o.expr.left, collector
        collector << ' FINAL'

        o.expr.right.each do |join|
          collector << ' '
          visit join, collector
        end

        collector
      end

      def visit_Arel_Nodes_GroupingSets(o, collector)
        collector << 'GROUPING SETS '
        grouping_array_or_grouping_element(o.expr, collector)
      end

      def visit_Arel_Nodes_Settings(o, collector)
        return collector if o.expr.empty?

        collector << "SETTINGS "
        o.expr.each_with_index do |(key, value), i|
          collector << ", " if i > 0
          collector << key.to_s.gsub(SETTING_KEY_NON_WORD_CHARS, "")
          collector << " = "
          collector << sanitize_as_setting_value(value)
        end
        collector
      end

      def visit_Arel_Nodes_Using(o, collector)
        collector << "USING "
        visit o.expr, collector
        collector
      end

      def visit_Arel_Nodes_LimitBy(o, collector)
        collector << "LIMIT #{o.expr} BY #{o.column}"
        collector
      end

      def visit_Arel_Nodes_Matches(o, collector)
        op = o.case_sensitive ? " LIKE " : " ILIKE "
        infix_value o, collector, op
      end

      def visit_Arel_Nodes_DoesNotMatch(o, collector)
        op = o.case_sensitive ? " NOT LIKE " : " NOT ILIKE "
        infix_value o, collector, op
      end

      def visit_Arel_Nodes_Rows(o, collector)
        if o.expr.is_a?(String)
          collector << "ROWS #{o.expr}"
        else
          super
        end
      end

      def visit_Arel_Nodes_Equality(o, collector)
        if rewrite_nil_to_empty_predicate?(o)
          collector << 'empty('
          visit o.left, collector
          collector << ')'
          return collector
        end

        super
      end

      def visit_Arel_Nodes_NotEqual(o, collector)
        if rewrite_nil_to_empty_predicate?(o)
          collector << 'notEmpty('
          visit o.left, collector
          collector << ')'
          return collector
        end

        super
      end

      def sanitize_as_setting_value(value)
        if value == :default
          'DEFAULT'
        else
          quote(value)
        end
      end

      def sanitize_as_setting_name(value)
        return value if Arel::Nodes::SqlLiteral === value
        @connection.sanitize_as_setting_name(value)
      end

      private

      def rewrite_nil_to_empty_predicate?(o)
        return false if unboundable?(o.right)
        return false unless o.left.is_a?(Arel::Attributes::Attribute)
        return false unless nil_comparison_operand?(o.right)

        column = column_for_arel_attribute(o.left)
        return false unless column
        return false if column.null
        return false unless clickhouse_sql_type_supports_empty?(column.sql_type)

        true
      end

      def nil_comparison_operand?(right)
        return true if right.nil?

        if defined?(ActiveModel::Attribute) && right.is_a?(ActiveModel::Attribute)
          return right.value.nil?
        end

        if right.is_a?(Arel::Nodes::Casted)
          return right.value.nil?
        end

        false
      end

      def column_for_arel_attribute(attr)
        table_name = resolve_arel_table_name(attr.relation)
        return nil unless table_name

        cols = @connection.schema_cache.columns(table_name)
        cols.find { |c| c.name == attr.name.to_s }
      rescue StandardError
        nil
      end

      def resolve_arel_table_name(relation)
        rel = relation
        while rel.is_a?(Arel::Nodes::TableAlias)
          rel = rel.relation
        end

        return nil unless rel.respond_to?(:name)

        rel.name.to_s
      end

      def clickhouse_sql_type_supports_empty?(sql_type)
        bare = strip_clickhouse_type_wrappers(sql_type)
        return false if bare.match?(CH_TYPE_ENUM_PREFIX)

        bare.match?(CH_TYPE_SUPPORTS_EMPTY)
      end

      def strip_clickhouse_type_wrappers(sql_type)
        s = sql_type.to_s.strip

        loop do
          case s
          when CH_TYPE_NULLABLE_WRAPPER
            s = Regexp.last_match(1)
          when CH_TYPE_LOW_CARDINALITY_WRAPPER
            s = Regexp.last_match(1)
          else
            break
          end
        end

        s
      end

      # Utilized by GroupingSet, Cube & RollUp visitors to
      # handle grouping aggregation semantics
      def grouping_array_or_grouping_element(o, collector)
        if o.is_a? Array
          collector << '( '
          o.each_with_index do |el, i|
            collector << ', ' if i > 0
            grouping_array_or_grouping_element el, collector
          end
          collector << ' )'
        elsif o.respond_to? :expr
          visit o.expr, collector
        else
          visit o, collector
        end
      end

    end
  end
end
