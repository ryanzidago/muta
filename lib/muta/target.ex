defmodule Muta.Target do
  @enforce_keys [:file, :test_modules]
  defstruct [:file, :test_modules]

  @type t :: %__MODULE__{
          file: Path.t(),
          test_modules: [module()]
        }
end
