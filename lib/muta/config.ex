defmodule Muta.Config do
  alias Muta.Mutator
  alias Muta.Source

  @enforce_keys [:sources, :test_files, :test_helper, :mutators, :workers, :baseline_timeout_ms]
  defstruct [:sources, :test_files, :test_helper, :mutators, :workers, :baseline_timeout_ms]

  @default_mutators [
    Mutator.Arithmetic,
    Mutator.Boolean,
    Mutator.Comparison,
    Mutator.Condition,
    Mutator.Counterpart,
    Mutator.Logical,
    Mutator.Membership,
    Mutator.Result
  ]
  @default_test_helper "test/test_helper.exs"
  @default_workers 4
  @default_baseline_timeout_ms 30_000

  @type t :: %__MODULE__{
          sources: [Source.t()],
          test_files: [Path.t()],
          test_helper: Path.t(),
          mutators: [module()],
          workers: pos_integer(),
          baseline_timeout_ms: pos_integer()
        }

  @spec new([Path.t()], [Path.t()], keyword()) :: t()
  def new(source_files, test_files, opts \\ []) do
    %__MODULE__{
      sources: Enum.map(source_files, &Source.read/1),
      test_files: Enum.map(test_files, &Path.expand/1),
      test_helper: Path.expand(Keyword.get(opts, :test_helper, @default_test_helper)),
      mutators: Keyword.get(opts, :mutators, @default_mutators),
      workers: workers(Keyword.get(opts, :workers, @default_workers)),
      baseline_timeout_ms: Keyword.get(opts, :baseline_timeout_ms, @default_baseline_timeout_ms)
    }
  end

  defp workers(count) when is_integer(count) and count > 0, do: count

  defp workers(count) do
    raise ArgumentError,
          "muta needs at least one worker to judge mutants, got #{inspect(count)}. " <>
            "With none, every mutant would go unjudged and the run would score 100%."
  end
end
