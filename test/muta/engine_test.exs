defmodule Muta.EngineTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO, only: [with_io: 2]
  import ExUnit.CaptureLog, only: [with_log: 1]

  alias Muta.Report
  alias Muta.Support.Fixture

  setup do
    Code.put_compiler_option(:ignore_module_conflict, true)
    dir = Fixture.tmp_dir()
    on_exit(fn -> File.rm_rf!(dir) end)

    %{dir: dir}
  end

  defp mutant(report, mutated) do
    Enum.find(report.mutants, &(&1.mutated == mutated))
  end

  test "a mutant no test can detect is reported as survived", %{dir: dir} do
    config =
      Fixture.config(
        dir,
        "weak_bands",
        ~S"""
        defmodule WeakBands do
          def band(n) when n < 100, do: :low
          def band(_n), do: :high
        end
        """,
        ~S"""
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
      )

    report = Muta.run(config)

    assert %{outcome: :survived} = mutant(report, "n <= 100")
  end

  test "the same mutant is killed once a test pins the boundary", %{dir: dir} do
    config =
      Fixture.config(
        dir,
        "strong_bands",
        ~S"""
        defmodule StrongBands do
          def band(n) when n < 100, do: :low
          def band(_n), do: :high
        end
        """,
        ~S"""
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
      )

    report = Muta.run(config)

    assert %{outcome: :killed} = mutant(report, "n <= 100")
  end

  test "a mutant that loops forever is killed by ExUnit timing its test out", %{dir: dir} do
    config =
      Fixture.config(
        dir,
        "looping_money",
        ~S"""
        defmodule LoopingMoney do
          def format(cents) when cents < 0, do: "-" <> format(-cents)
          def format(cents), do: "$#{div(cents, 100)}"
        end
        """,
        ~S"""
        defmodule LoopingMoneyTest do
          use ExUnit.Case, async: false

          test "formats zero" do
            assert LoopingMoney.format(0) == "$0"
          end
        end
        """
      )

    {report, _log} = with_log(fn -> Muta.run(config) end)

    assert %{outcome: :killed} = mutant(report, "cents <= 0")
  end

  test "restores the original module after every mutant", %{dir: dir} do
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

    Muta.run(config)

    restored = Module.concat([:RestoredBands])

    assert restored.band(99) == :low
    assert restored.band(100) == :high
  end

  test "scores a suite that pins nothing at zero", %{dir: dir} do
    config =
      Fixture.config(
        dir,
        "untested_boundary",
        ~S"""
        defmodule UntestedBoundary do
          def positive?(n), do: n > 0
        end
        """,
        ~S"""
        defmodule UntestedBoundaryTest do
          use ExUnit.Case, async: false

          test "returns a boolean" do
            assert is_boolean(UntestedBoundary.positive?(5))
          end
        end
        """
      )

    report = Muta.run(config)

    assert %Report{killed: 0, score: +0.0} = report
    assert length(Report.survivors(report)) == 2
  end

  test "reports a mutant on a line no test reaches as survived without running", %{dir: dir} do
    config =
      Fixture.config(
        dir,
        "unreached_bands",
        ~S"""
        defmodule UnreachedBands do
          def band(n) when n < 100, do: :low
          def band(_n), do: :high

          def surcharge(n) when n > 500, do: :levied
          def surcharge(_n), do: :none
        end
        """,
        ~S"""
        defmodule UnreachedBandsTest do
          use ExUnit.Case, async: false

          test "the threshold itself is high" do
            assert UnreachedBands.band(100) == :high
          end
        end
        """
      )

    report = Muta.run(config)

    assert %{outcome: :survived} = mutant(report, "n >= 500")
    assert %{outcome: :killed} = mutant(report, "n <= 100")
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
        mutators: [Muta.Mutator.Comparison, Muta.Support.IllegalInGuard]
      )

    {report, _compiler_diagnostic} = with_io(:stderr, fn -> Muta.run(config) end)

    assert %Report{invalid: 1, killed: 1, survived: 1, score: 50.0} = report
  end
end
