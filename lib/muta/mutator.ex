defmodule Muta.Mutator do
  @callback mutations(Macro.t()) :: [Macro.t()]
end
