defmodule Muta.Worker do
  use GenServer

  alias Muta.Config
  alias Muta.Engine
  alias Muta.Mutant
  alias Muta.Mutation
  alias Muta.Original
  alias Muta.Suite
  alias Muta.Timing
  alias Muta.UntrustworthyError

  @enforce_keys [:config, :suite, :originals]
  defstruct [:config, :suite, :originals]

  @patience 10
  @min_timeout_ms 200

  @spec start(node(), Config.t()) :: pid()
  def start(node, %Config{} = config) do
    case :erpc.call(node, GenServer, :start, [__MODULE__, config], :infinity) do
      {:ok, pid} -> pid
      {:error, {exception, stacktrace}} -> reraise(exception, stacktrace)
    end
  end

  @spec judge(pid(), Mutation.t()) :: Mutant.t()
  def judge(worker, %Mutation{} = mutation) do
    case GenServer.call(worker, {:judge, mutation}, :infinity) do
      {:ok, mutant} -> mutant
      {:raised, {exception, stacktrace}} -> reraise(exception, stacktrace)
    end
  end

  @impl GenServer
  def init(%Config{} = config) do
    Code.put_compiler_option(:ignore_module_conflict, true)
    Code.require_file(config.test_helper)

    suite = Suite.load(config.test_files)
    {:ok, timing} = Timing.start_link()

    ExUnit.configure(
      formatters: [Timing.Formatter],
      max_failures: 1,
      muta_timing: timing,
      only_test_ids: suite.test_ids,
      timeout: config.baseline_timeout_ms
    )

    originals = Map.new(config.sources, &{&1.file, Original.compile(&1)})

    ensure_green(ExUnit.run(suite.modules))

    ExUnit.configure(formatters: [], timeout: deadline(Timing.slowest_ms(timing)))
    Timing.stop(timing)

    {:ok, %__MODULE__{config: config, suite: suite, originals: originals}}
  end

  defp deadline(slowest_ms), do: max(slowest_ms * @patience, @min_timeout_ms)

  @impl GenServer
  def handle_call({:judge, %Mutation{} = mutation}, _from, %__MODULE__{} = state) do
    {:reply, attempt(mutation, state), state}
  end

  defp attempt(%Mutation{} = mutation, %__MODULE__{} = state) do
    original = Map.fetch!(state.originals, mutation.file)

    {:ok, Engine.judge(mutation, original, state.suite, state.config)}
  rescue
    exception -> {:raised, {exception, __STACKTRACE__}}
  end

  defp ensure_green(%{failures: 0}), do: :ok

  defp ensure_green(%{failures: failures}) do
    raise UntrustworthyError,
          "#{failures} test(s) fail on unmutated code inside a worker, even though they pass " <>
            "where muta was started. A worker runs the same tests in its own VM, so every " <>
            "mutant it judged would be measured against a suite that was already red."
  end
end
