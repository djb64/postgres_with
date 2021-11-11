module ActiveRecord
  module QueryMethods
    # WithChain objects act as placeholder for queries in which #with does not have any parameter.
    # In this case, #with must be chained with #recursive to return a new relation.
    class WithChain
      def initialize(scope)
        @scope = scope
      end

      def materialized(*args)
        materialized_args = args.flat_map do |arg|
          case arg
          when Hash
            name = arg.keys.first
            new_name = "_materialized_#{name}"
            { new_name => arg[name] }
          else
            arg
          end
        end
        @scope.with_values += materialized_args
        @scope
      end

      # Returns a new relation expressing WITH RECURSIVE
      def recursive(*args)
        @scope.with_values += args
        @scope.recursive_value = true
        @scope
      end
    end

    [:with].each do |name|
      class_eval <<-CODE, __FILE__, __LINE__ + 1
       def #{name}_values                   # def select_values
         @values[:#{name}] || []            #   @values[:select] || []
       end                                  # end
                                            #
       def #{name}_values=(values)          # def select_values=(values)
         raise ImmutableRelation if @loaded #   raise ImmutableRelation if @loaded
         @values[:#{name}] = values         #   @values[:select] = values
       end                                  # end
      CODE
    end

    [:recursive].each do |name|
      class_eval <<-CODE, __FILE__, __LINE__ + 1
        def #{name}_value=(value)            # def readonly_value=(value)
          raise ImmutableRelation if @loaded #   raise ImmutableRelation if @loaded
          @values[:#{name}] = value          #   @values[:readonly] = value
        end                                  # end

        def #{name}_value                    # def readonly_value
          @values[:#{name}]                  #   @values[:readonly]
        end                                  # end
      CODE
    end

    def with(opts = :chain, *rest)
      if opts == :chain
        WithChain.new(spawn)
      elsif opts.blank?
        self
      else
        spawn.with!(opts, *rest)
      end
    end

    def with!(opts = :chain, *rest) # :nodoc:
      if opts == :chain
        WithChain.new(self)
      else
        self.with_values += [opts] + rest
        self
      end
    end

    def build_arel_with_extensions(aliases = nil)
      arel = build_arel_without_extensions(aliases)

      with_statements = with_values.flat_map do |with_value|
        case with_value
        when String
          Arel::Nodes::SqlLiteral.new(with_value)
        when Hash
          build_arel_from_hash(with_value)
        when Arel::Nodes::As
          with_value
        when Array
          build_arel_from_array(with_value)
        else
          raise ArgumentError, "Unsupported argument type: #{with_value} #{with_value.class}"
        end
      end
      unless with_statements.empty?
        if recursive_value
          arel.with :recursive, with_statements
        else
          arel.with with_statements
        end
      end

      arel
    end

    def build_arel_from_hash(with_value)
      with_value.map do |name, expression|
        select = case expression
                 when String
                   Arel::Nodes::SqlLiteral.new("(#{expression})")
                 when ActiveRecord::Relation
                   expression.arel
                 when Arel::SelectManager
                   expression
                 end
        if name.to_s.start_with?('_materialized_')
          name = name.gsub('_materialized_', '')
          table = Arel::Table.new(name)
          Arel::Nodes::AsMaterialized.new(table, select)
        else
          table = Arel::Table.new(name)
          Arel::Nodes::As.new(table, select)
        end
      end
    end

    def build_arel_from_array(array)
      unless array.map(&:class).uniq == [Arel::Nodes::As]
        raise ArgumentError, "Unsupported argument type: #{array} #{array.class}"
      end

      array
    end

    alias_method :build_arel_without_extensions, :build_arel
    alias_method :build_arel, :build_arel_with_extensions
  end
end
