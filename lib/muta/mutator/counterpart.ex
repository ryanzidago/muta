defmodule Muta.Mutator.Counterpart do
  @behaviour Muta.Mutator

  @swaps %{
    {[:Enum], :all?} => :any?,
    {[:Enum], :any?} => :all?,
    {[:Enum], :drop} => :take,
    {[:Enum], :filter} => :reject,
    {[:Enum], :max} => :min,
    {[:Enum], :max_by} => :min_by,
    {[:Enum], :min} => :max,
    {[:Enum], :min_by} => :max_by,
    {[:Enum], :reject} => :filter,
    {[:Enum], :take} => :drop,
    {[:List], :first} => :last,
    {[:List], :last} => :first,
    {[:String], :downcase} => :upcase,
    {[:String], :ends_with?} => :starts_with?,
    {[:String], :starts_with?} => :ends_with?,
    {[:String], :trim_leading} => :trim_trailing,
    {[:String], :trim_trailing} => :trim_leading,
    {[:String], :upcase} => :downcase
  }

  @impl Muta.Mutator
  def mutations(
        {{:., dot_meta, [{:__aliases__, _alias_meta, segments} = module, name]}, meta, args}
      ) do
    case Map.fetch(@swaps, {segments, name}) do
      {:ok, counterpart} -> [{{:., dot_meta, [module, counterpart]}, meta, args}]
      :error -> []
    end
  end

  def mutations(_node), do: []
end
