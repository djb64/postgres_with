module Arel
  module Visitors
    class ToSql < Arel::Visitors::Reduce
      def visit_Arel_Nodes_AsMaterialized o, collector
        collector = visit o.left, collector
        collector << " AS MATERIALIZED "
        visit o.right, collector
      end
    end
  end
end
