require "./nfa.cr"
require "./pda.cr"
require "./error.cr"

module Pegasus
  module Dfa
    class Dfa
      # Creates a final table, which is used to determine if a state matched a token.
      def final_table
        return [0_i64] + @states.map { |s| s.data.compact_map(&.data).max_of?(&.+(1)) || 0_i64 }
      end

      # Creates a transition table given, see `Pegasus::Language::LanguageData`
      def state_table
        table = [Array.new(256, 0_i64)]
        @states.each do |state|
          empty_table = Array.new(256, 0_i64)
          state.transitions.each do |byte, out_state|
            empty_table[byte] = out_state.id + 1
          end
          table << empty_table
        end
        return table
      end
    end
  end

  module Pda
    class Pda
      private def check_conflict(action_table, state_index, index, shifting)
        current_value = action_table[state_index][index]
        if shifting
          raise_table "Shift / reduce conflict" if current_value > 0
        else
          raise_table "Shift / reduce conflict" if current_value == 0
          raise_table "Reduce / reduce conflict" if current_value > 0
        end
      end

      # Creates an action table, determing what the parser should do
      # at the given state and the lookhead token.
      def action_table
        max_terminal = @items.max_of? do |item|
          item.body.select(&.is_a?(Terminal)).max_of?(&.id) || 0_i64
        end || -1_i64

        # +1 for potential -1, +1 since terminal IDs start at 0.
        table = Array.new(@states.size + 1) { Array.new(max_terminal + 1 + 1, -1_i64) }
        @states.each do |state|
          done_items = state.data.select &.done?
          shiftable_items = state.data.select do |item|
            !item.done? && item.item.body[item.index].is_a?(Terminal)
          end
          done_items.each do |item|
            item.lookahead.each do |terminal|
              check_conflict(table, state.id + 1, terminal.id + 1, shifting: false)
              table[state.id + 1][terminal.id + 1] = @items.index(item.item).not_nil!.to_i64 + 1
            end
          end
          shiftable_items.each do |item|
            terminal = item.item.body[item.index].as(Terminal)
            check_conflict(table, state.id + 1, terminal.id + 1, shifting: true)
            table[state.id + 1][terminal.id + 1] = 0
          end
        end

        return table
      end

      # Creates a transition table that is indexed by both Terminals and Nonterminals.
      def state_table
        max_terminal = @items.max_of? do |item|
          item.body.select(&.is_a?(Terminal)).max_of?(&.id) || -1_i64
        end || -1_i64

        max_nonterminal = @items.max_of? do |item|
          Math.max(item.head.id, item.body.select(&.is_a?(Nonterminal)).max_of?(&.id) || -1_i64)
        end || -1_i64

        # +1 for potential -1 in terminal, +1 + 1 because both terminal and nonterminals start at 0.
        table = Array.new(@states.size + 1) { Array.new(max_nonterminal + max_terminal + 1 + 1 + 1, 0_i64) }
        @states.each do |state|
          state.transitions.each do |token, to|
            case token
            when Terminal
              table[state.id + 1][token.id + 1] = to.id + 1
            when Nonterminal
              table[state.id + 1][token.id + 1 + 1 + max_terminal] = to.id + 1
            end
          end
        end

        return table
      end
    end
  end
end
