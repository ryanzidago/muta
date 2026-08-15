defmodule Muta.EngineTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog, only: [with_log: 1]

  alias Muta.Engine
  alias Muta.Mutator.Comparison
  alias Muta.Report

  defp run_fixture(source, suite) do
    Code.put_compiler_option(:ignore_module_conflict, true)
    Code.compile_string(source)
    [{test_module, _binary}] = Code.compile_string(suite)

    Engine.run(source, "fixture.ex", [test_module], [Comparison])
  end

  defp mutant(report, mutated) do
    Enum.find(report.mutants, &(&1.mutated == mutated))
  end

  test "a mutant no test can detect is reported as survived" do
    source = ~S"""
    defmodule WeakBands do
      def band(n) when n < 100, do: :low
      def band(_n), do: :high
    end
    """

    suite = ~S"""
    defmodule WeakBandsTest do
      use ExUnit.Case, async: false

      test "well below the threshold is low" do
        assert WeakBands.band(50) == :low
      end

      test "well above the threshold is high" do
        assert WeakBands.band(500) == :high
      end
    end
    """

    report = run_fixture(source, suite)

    assert %{outcome: :survived} = mutant(report, "n <= 100")
  end

  test "the same mutant is killed once a test pins the boundary" do
    source = ~S"""
    defmodule StrongBands do
      def band(n) when n < 100, do: :low
      def band(_n), do: :high
    end
    """

    suite = ~S"""
    defmodule StrongBandsTest do
      use ExUnit.Case, async: false

      test "well below the threshold is low" do
        assert StrongBands.band(50) == :low
      end

      test "the threshold itself is high" do
        assert StrongBands.band(100) == :high
      end
    end
    """

    report = run_fixture(source, suite)

    assert %{outcome: :killed} = mutant(report, "n <= 100")
  end

  test "a mutant that loops forever is killed by the timeout" do
    source = ~S"""
    defmodule LoopingMoney do
      def format(cents) when cents < 0, do: "-" <> format(-cents)
      def format(cents), do: "$#{div(cents, 100)}"
    end
    """

    suite = ~S"""
    defmodule LoopingMoneyTest do
      use ExUnit.Case, async: false

      test "formats zero" do
        assert LoopingMoney.format(0) == "$0"
      end
    end
    """

    Code.put_compiler_option(:ignore_module_conflict, true)
    Code.compile_string(source)
    [{test_module, _binary}] = Code.compile_string(suite)

    {report, _log} =
      with_log(fn ->
        Engine.run(source, "fixture.ex", [test_module], [Comparison], timeout_ms: 500)
      end)

    assert %{outcome: :timed_out} = mutant(report, "cents <= 0")
  end

  test "restores the original module after every mutant" do
    source = ~S"""
    defmodule RestoredBands do
      def band(n) when n < 100, do: :low
      def band(_n), do: :high
    end
    """

    suite = ~S"""
    defmodule RestoredBandsTest do
      use ExUnit.Case, async: false

      test "well below the threshold is low" do
        assert RestoredBands.band(50) == :low
      end
    end
    """

    run_fixture(source, suite)

    restored = Module.concat([:RestoredBands])

    assert restored.band(99) == :low
    assert restored.band(100) == :high
  end

  test "scores a suite that pins nothing at zero" do
    source = ~S"""
    defmodule UntestedBoundary do
      def positive?(n), do: n > 0
    end
    """

    suite = ~S"""
    defmodule UntestedBoundaryTest do
      use ExUnit.Case, async: false

      test "returns a boolean" do
        assert is_boolean(UntestedBoundary.positive?(5))
      end
    end
    """

    report = run_fixture(source, suite)

    assert %Report{killed: 0, score: +0.0} = report
    assert length(Report.survivors(report)) == 2
  end
end
