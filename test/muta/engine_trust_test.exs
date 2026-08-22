defmodule Muta.EngineTrustTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO, only: [with_io: 2]
  import ExUnit.CaptureLog, only: [with_log: 1]

  alias Muta.Support.Fixture
  alias Muta.UntrustworthyError

  setup do
    Code.put_compiler_option(:ignore_module_conflict, true)
    dir = Fixture.tmp_dir()
    on_exit(fn -> File.rm_rf!(dir) end)

    %{dir: dir}
  end

  test "refuses to score a suite that is already failing", %{dir: dir} do
    config =
      Fixture.config(
        dir,
        "red_bands",
        ~S"""
        defmodule RedBands do
          def band(n) when n < 100, do: :low
          def band(_n), do: :high
        end
        """,
        ~S"""
        defmodule RedBandsTest do
          use ExUnit.Case, async: false

          test "holds a belief that is simply untrue" do
            assert RedBands.band(50) == :high
          end
        end
        """
      )

    assert_raise UntrustworthyError, ~r/fail on unmutated code/, fn ->
      Muta.run(config)
    end
  end

  test "refuses to score a suite that does not give the same answer twice", %{dir: dir} do
    config =
      Fixture.config(
        dir,
        "leaky_bands",
        ~S"""
        defmodule LeakyBands do
          def band(n) when n < 100, do: :low
          def band(_n), do: :high
        end
        """,
        ~S"""
        defmodule LeakyBandsTest do
          use ExUnit.Case, async: false

          test "passes only on the first run" do
            seen = :persistent_term.get({__MODULE__, :seen}, 0)
            :persistent_term.put({__MODULE__, :seen}, seen + 1)

            assert LeakyBands.band(50) == :low
            assert seen == 0
          end
        end
        """
      )

    assert_raise UntrustworthyError, ~r/two runs of the unmutated tests disagreed/, fn ->
      Muta.run(config)
    end
  end

  test "judges a mutant only by the tests it was given", %{dir: dir} do
    Code.compile_string(~S"""
    defmodule UnrelatedFailingTest do
      use ExUnit.Case, async: false

      test "fails for reasons of its own" do
        flunk("nothing to do with any mutant")
      end
    end
    """)

    config =
      Fixture.config(
        dir,
        "isolated_bands",
        ~S"""
        defmodule IsolatedBands do
          def band(n) when n < 100, do: :low
          def band(_n), do: :high
        end
        """,
        ~S"""
        defmodule IsolatedBandsTest do
          use ExUnit.Case, async: false

          test "the threshold itself is high" do
            assert IsolatedBands.band(100) == :high
          end
        end
        """
      )

    report = Muta.run(config)

    assert report.killed > 0
  end

  test "refuses to judge when it was given no tests", %{dir: dir} do
    file =
      Fixture.target(dir, "unjudged_bands", ~S"""
      defmodule UnjudgedBands do
        def band(n) when n < 100, do: :low
        def band(_n), do: :high
      end
      """)

    assert_raise UntrustworthyError, ~r/no tests were given/, fn ->
      Muta.run(Muta.Config.new([file], []))
    end
  end

  test "refuses when the tests do not finish in time on unmutated code", %{dir: dir} do
    config =
      Fixture.config(
        dir,
        "slow_bands",
        ~S"""
        defmodule SlowBands do
          def band(n) when n < 100, do: :low
          def band(_n), do: :high
        end
        """,
        ~S"""
        defmodule SlowBandsTest do
          use ExUnit.Case, async: false

          test "takes longer than muta was told to wait" do
            Process.sleep(300)

            assert SlowBands.band(100) == :high
          end
        end
        """,
        baseline_timeout_ms: 50
      )

    with_log(fn ->
      assert_raise UntrustworthyError, ~r/did not finish within 50ms on unmutated code/, fn ->
        Muta.run(config)
      end
    end)
  end

  test "carries a refusal raised inside a worker back to the caller", %{dir: dir} do
    config =
      Fixture.config(
        dir,
        "guarded_limits",
        ~S"""
        defmodule GuardedLimits do
          defguard over?(cents) when cents > 5000

          def name, do: :limits
        end
        """,
        ~S"""
        defmodule GuardedLimitsTest do
          use ExUnit.Case, async: false

          test "knows its name" do
            assert GuardedLimits.name() == :limits
          end
        end
        """
      )

    assert_raise UntrustworthyError, ~r/defines macros/, fn -> Muta.run(config) end
  end

  test "refuses when every test it was given is skipped", %{dir: dir} do
    config =
      Fixture.config(
        dir,
        "unrun_bands",
        ~S"""
        defmodule UnrunBands do
          def band(n) when n < 100, do: :low
          def band(_n), do: :high
        end
        """,
        ~S"""
        defmodule UnrunBandsTest do
          use ExUnit.Case, async: false

          @moduletag :skip

          test "never actually runs" do
            assert UnrunBands.band(100) == :high
          end
        end
        """
      )

    assert_raise UntrustworthyError, ~r/ran nothing/, fn -> Muta.run(config) end
  end

  test "refuses to score a run in which the compiler rejected every mutant", %{dir: dir} do
    config =
      Fixture.config(
        dir,
        "all_invalid_bands",
        ~S"""
        defmodule AllInvalidBands do
          def band(n) when n < 100, do: :low
          def band(_n), do: :high
        end
        """,
        ~S"""
        defmodule AllInvalidBandsTest do
          use ExUnit.Case, async: false

          test "the threshold itself is high" do
            assert AllInvalidBands.band(100) == :high
          end
        end
        """,
        mutators: [Muta.Support.IllegalInGuard]
      )

    {_result, _diagnostic} =
      with_io(:stderr, fn ->
        assert_raise UntrustworthyError, ~r/rejected by the compiler/, fn -> Muta.run(config) end
      end)
  end
end
