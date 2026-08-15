defmodule Muta.Config do
  alias Muta.Mutator
  alias Muta.Target

  @enforce_keys [:targets, :mutators, :baseline_timeout_ms]
  defstruct [:targets, :mutators, :baseline_timeout_ms]

  @default_mutators [Mutator.Comparison]
  @default_baseline_timeout_ms 30_000

  @type t :: %__MODULE__{
          targets: [Target.t()],
          mutators: [module()],
          baseline_timeout_ms: pos_integer()
        }

  @spec new([Target.t()], keyword()) :: t()
  def new(targets, opts \\ []) do
    %__MODULE__{
      targets: targets,
      mutators: Keyword.get(opts, :mutators, @default_mutators),
      baseline_timeout_ms: Keyword.get(opts, :baseline_timeout_ms, @default_baseline_timeout_ms)
    }
  end
end
