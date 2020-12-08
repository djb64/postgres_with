module Arel
  module Visitors
    class Dot < Arel::Visitors::Visitor
      alias :visit_Arel_Nodes_AsMaterialized :binary
    end
  end
end
