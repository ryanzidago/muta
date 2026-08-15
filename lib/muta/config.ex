defmodule Muta.Config do
  alias Muta.Mutator
  alias Muta.Target

  @enforce_keys [:targets, :test_modules, :mutators, :baseline_timeout_ms]
  defstruct [:targets, :test_modules, :mutators, :baseline_timeout_ms]

  @default_mutators [Mutator.Comparison]
  @default_baseline_timeout_ms 30_000

  @type t :: %__MODULE__{
          targets: [Target.t()],
          test_modules: [module()],
          mutators: [module()],
          baseline_timeout_ms: pos_integer()
        }

  @spec new([Target.t()], [module()], keyword()) :: t()
  def new(targets, test_modules, opts \\ []) do
    %__MODULE__{
      targets: targets,
      test_modules: test_modules,
      mutators: Keyword.get(opts, :mutators, @default_mutators),
      baseline_timeout_ms: Keyword.get(opts, :baseline_timeout_ms, @default_baseline_timeout_ms)
    }
  end
end
