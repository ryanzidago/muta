defmodule Muta.Target do
  @enforce_keys [:file]
  defstruct [:file]

  @type t :: %__MODULE__{file: Path.t()}
end
