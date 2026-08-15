defmodule Muta.Config do
  alias Muta.Mutator
  alias Muta.Target

  @enforce_keys [:targets, :mutators, :timeout_ms]
  defstruct [:targets, :mutators, :timeout_ms]

  @default_mutators [Mutator.Comparison]
  @default_timeout_ms 5_000

  @type t :: %__MODULE__{
          targets: [Target.t()],
          mutators: [module()],
          timeout_ms: pos_integer()
        }

  @spec new([Target.t()], keyword()) :: t()
  def new(targets, opts \\ []) do
    %__MODULE__{
      targets: targets,
      mutators: Keyword.get(opts, :mutators, @default_mutators),
      timeout_ms: Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    }
  end
end
