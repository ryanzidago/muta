defmodule Muta.Config do
  alias Muta.Mutator
  alias Muta.Target

  @enforce_keys [:targets, :test_modules, :mutators, :baseline_timeout_ms, :load_test_module]
  defstruct [:targets, :test_modules, :mutators, :baseline_timeout_ms, :load_test_module]

  @default_mutators [Mutator.Comparison]
  @default_baseline_timeout_ms 30_000

  @type t :: %__MODULE__{
          targets: [Target.t()],
          test_modules: [module()],
          mutators: [module()],
          baseline_timeout_ms: pos_integer(),
          load_test_module: (module() -> any())
        }

  @spec new([Target.t()], [module()], keyword()) :: t()
  def new(targets, test_modules, opts \\ []) do
    %__MODULE__{
      targets: targets,
      test_modules: test_modules,
      mutators: Keyword.get(opts, :mutators, @default_mutators),
      baseline_timeout_ms: Keyword.get(opts, :baseline_timeout_ms, @default_baseline_timeout_ms),
      load_test_module: Keyword.get(opts, :load_test_module, &already_loaded/1)
    }
  end

  defp already_loaded(_test_module), do: :ok
end
