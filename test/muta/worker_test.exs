defmodule Muta.WorkerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog, only: [with_log: 1]

  alias Muta.Config
  alias Muta.Generator
  alias Muta.Settings
  alias Muta.Support.Fixture
  alias Muta.UntrustworthyError
  alias Muta.Worker

  setup do
    Code.put_compiler_option(:ignore_module_conflict, true)
    dir = Fixture.tmp_dir()
    on_exit(fn -> File.rm_rf!(dir) end)

    %{dir: dir}
  end

  defp judged(%Config{} = config) do
    Settings.restored_after(fn ->
      worker = Worker.start(node(), config)

      mutants =
        config.sources
        |> Enum.flat_map(&elem(Generator.generate(&1, config.mutators), 0))
        |> Enum.map(&Worker.judge(worker, &1))

      GenServer.stop(worker)

      mutants
    end)
  end

  defp start_worker(%Config{} = config) do
    Settings.restored_after(fn -> Worker.start(node(), config) end)
  end

  defp outcome_of(mutants, mutated) do
    Enum.find_value(mutants, :not_generated, fn mutant ->
      mutant.mutated == mutated && mutant.outcome
    end)
  end

  test "reports a mutant no test can tell apart as survived", %{dir: dir} do
    config =
      Fixture.config(
        dir,
        "loose_bands",
        ~S"""
        defmodule LooseBands do
          def band(n) when n < 100, do: :low
          def band(_n), do: :high
        end
        """,
        ~S"""
        defmodule LooseBandsTest do
          use ExUnit.Case, async: false

          test "well below the threshold is low" do
            assert LooseBands.band(50) == :low
          end
        end
        """
      )

    assert outcome_of(judged(config), "n <= 100") == :survived
  end

  test "reports a mutant a test catches as killed", %{dir: dir} do
    config =
      Fixture.config(
        dir,
        "tight_bands",
        ~S"""
        defmodule TightBands do
          def band(n) when n < 100, do: :low
          def band(_n), do: :high
        end
        """,
        ~S"""
        defmodule TightBandsTest do
          use ExUnit.Case, async: false

          test "the threshold itself is high" do
            assert TightBands.band(100) == :high
          end
        end
        """
      )

    assert outcome_of(judged(config), "n <= 100") == :killed
  end

  test "reports a mutant the compiler rejects as invalid", %{dir: dir} do
    config =
      Fixture.config(
        dir,
        "guarded_bands",
        ~S"""
        defmodule GuardedBands do
          def band(n) when n < 100, do: :low
          def band(_n), do: :high
        end
        """,
        ~S"""
        defmodule GuardedBandsTest do
          use ExUnit.Case, async: false

          test "the threshold itself is high" do
            assert GuardedBands.band(100) == :high
          end
        end
        """,
        mutators: [Muta.Support.IllegalInGuard]
      )

    assert outcome_of(judged(config), "IO.inspect(n, 100)") == :invalid
  end

  test "puts the original module back after judging a mutant", %{dir: dir} do
    config =
      Fixture.config(
        dir,
        "restored_bands",
        ~S"""
        defmodule RestoredBands do
          def band(n) when n < 100, do: :low
          def band(_n), do: :high
        end
        """,
        ~S"""
        defmodule RestoredBandsTest do
          use ExUnit.Case, async: false

          test "well below the threshold is low" do
            assert RestoredBands.band(50) == :low
          end
        end
        """
      )

    judged(config)

    restored = Module.concat([:RestoredBands])

    assert restored.band(99) == :low
    assert restored.band(100) == :high
  end

  test "refuses when a test leaves a process running the mutant behind", %{dir: dir} do
    config =
      Fixture.config(
        dir,
        "lingering_bands",
        ~S"""
        defmodule LingeringBands do
          def band(n) when n < 100, do: :low
          def band(_n), do: :high

          def linger do
            Process.sleep(2_000)
            :done
          end
        end
        """,
        ~S"""
        defmodule LingeringBandsTest do
          use ExUnit.Case, async: false

          test "spawns a process that outlives it" do
            spawn(fn -> LingeringBands.linger() end)
            Process.sleep(20)

            assert LingeringBands.band(100) == :high
          end
        end
        """
      )

    assert_raise UntrustworthyError, ~r/still running mutated/, fn -> judged(config) end
  end

  test "stops when a mutant outruns the budget its tests were given", %{dir: dir} do
    config =
      Fixture.config(
        dir,
        "budget_money",
        ~S"""
        defmodule BudgetMoney do
          def format(cents) when cents < 0, do: "-" <> format(-cents)
          def format(cents), do: "$#{div(cents, 100)}"
        end
        """,
        ~S"""
        defmodule BudgetMoneyTest do
          use ExUnit.Case, async: false

          test "formats zero" do
            Process.sleep(120)

            assert BudgetMoney.format(0) == "$0"
          end
        end
        """,
        baseline_timeout_ms: 400
      )

    with_log(fn ->
      assert_raise UntrustworthyError, ~r/did not return within 400ms/, fn ->
        judged(config)
      end
    end)
  end

  test "refuses to judge anything when the tests are already red in its own vm", %{dir: dir} do
    config =
      Fixture.config(
        dir,
        "red_worker_bands",
        ~S"""
        defmodule RedWorkerBands do
          def band(n) when n < 100, do: :low
          def band(_n), do: :high
        end
        """,
        ~S"""
        defmodule RedWorkerBandsTest do
          use ExUnit.Case, async: false

          test "holds a belief that is simply untrue" do
            assert RedWorkerBands.band(50) == :high
          end
        end
        """
      )

    assert_raise UntrustworthyError, ~r/fail on unmutated code inside a worker/, fn ->
      start_worker(config)
    end
  end

  test "reports a mutant that a macro rejects while expanding as invalid", %{dir: dir} do
    config =
      Fixture.config(
        dir,
        "strict_tags",
        ~S"""
        defmodule StrictTags do
          require Muta.Support.StrictMacro

          def tag, do: Muta.Support.StrictMacro.must_be_ok(:ok)
        end
        """,
        ~S"""
        defmodule StrictTagsTest do
          use ExUnit.Case, async: false

          test "tags with ok" do
            assert StrictTags.tag() == :ok
          end
        end
        """
      )

    assert outcome_of(judged(config), ":error") == :invalid
  end

  test "reports a mutant only one run in two catches as unstable", %{dir: dir} do
    config =
      Fixture.config(
        dir,
        "flaky_gate",
        ~S"""
        defmodule FlakyGate do
          def exact?(n), do: n == 10
        end
        """,
        ~S"""
        defmodule FlakyGateTest do
          use ExUnit.Case, async: false

          test "fails the first time it judges a mutant and passes the next" do
            run = :persistent_term.get(:muta_flaky_gate_runs, 0) + 1
            :persistent_term.put(:muta_flaky_gate_runs, run)

            assert is_boolean(FlakyGate.exact?(3))
            assert run != 2
          end
        end
        """,
        mutators: [Muta.Mutator.Comparison]
      )

    on_exit(fn -> :persistent_term.erase(:muta_flaky_gate_runs) end)

    assert outcome_of(judged(config), "n != 10") == :unstable
  end
end
