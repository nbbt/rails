module ActiveRecord
  module Associations
    class Preloader
      class Association #:nodoc:
        attr_reader :owners, :reflection, :preload_scope, :model, :klass

        def initialize(klass, owners, reflection, preload_scope)
          @klass         = klass
          @owners        = owners
          @reflection    = reflection
          @preload_scope = preload_scope
          @model         = owners.first && owners.first.class
          @scope         = nil
          @owners_by_key = nil
        end

        def run
          unless owners.first.association(reflection.name).loaded?
            preload
          end
        end

        def preload
          raise NotImplementedError
        end

        def scope
          @scope ||= build_scope
        end

        def records_for(ids)
          query_scope(ids)
        end

        def query_scope(ids)
          scope.where(association_key.in(ids))
        end

        def table
          klass.arel_table
        end

        # The name of the key on the associated records
        def association_key_name
          raise NotImplementedError
        end

        # This is overridden by HABTM as the condition should be on the foreign_key column in
        # the join table
        def association_key
          table[association_key_name]
        end

        # The name of the key on the model which declares the association
        def owner_key_name
          raise NotImplementedError
        end

        def owners_by_key
          @owners_by_key ||= owners.group_by do |owner|
            owner[owner_key_name]
          end
        end

        def options
          reflection.options
        end

        private

        def associated_records_by_owner
          owners_map = owners_by_key
          owner_keys = owners_map.keys.compact

          # Each record may have multiple owners, and vice-versa
          records_by_owner = Hash[owners.map { |owner| [owner, []] }]

          if klass && owner_keys.any?
            # Some databases impose a limit on the number of ids in a list (in Oracle it's 1000)
            # Make several smaller queries if necessary or make one query if the adapter supports it
            sliced  = owner_keys.each_slice(klass.connection.in_clause_length || owner_keys.size)
            sliced.each { |slice|
              records = records_for(slice)
              caster = type_caster(records, association_key_name)
              records.each do |record|
                owner_key = caster.call record[association_key_name]

                owners_map[owner_key].each do |owner|
                  records_by_owner[owner] << record
                end
              end
            }
          end

          records_by_owner
        end

        IDENTITY = lambda { |value| value }
        def type_caster(results, name)
          IDENTITY
        end

        def reflection_scope
          @reflection_scope ||= reflection.scope ? klass.unscoped.instance_exec(nil, &reflection.scope) : klass.unscoped
        end

        def build_scope
          scope = klass.unscoped

          values         = reflection_scope.values
          preload_values = preload_scope.values

          scope.where_values      = Array(values[:where])      + Array(preload_values[:where])
          scope.references_values = Array(values[:references]) + Array(preload_values[:references])

          scope.select!   preload_values[:select] || values[:select] || table[Arel.star]
          scope.includes! preload_values[:includes] || values[:includes]

          if options[:as]
            scope.where!(klass.table_name => { reflection.type => model.base_class.sti_name })
          end

          klass.default_scoped.merge(scope)
        end
      end
    end
  end
end
