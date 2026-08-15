defmodule Muta.EngineTrustTest do
  use ExUnit.Case, async: false

  alias Muta.Engine
  alias Muta.Mutator.Comparison
  alias Muta.UntrustworthyError

  defp run_fixture(source, suite) do
    Code.put_compiler_option(:ignore_module_conflict, true)
    Code.compile_string(source)
    [{test_module, _binary}] = Code.compile_string(suite)

    Engine.run(source, "fixture.ex", [test_module], [Comparison])
  end

  test "refuses to score a suite that is already failing" do
    source = ~S"""
    defmodule RedBands do
      def band(n) when n < 100, do: :low
      def band(_n), do: :high
    end
    """

    suite = ~S"""
    defmodule RedBandsTest do
      use ExUnit.Case, async: false

      test "holds a belief that is simply untrue" do
        assert RedBands.band(50) == :high
      end
    end
    """

    assert_raise UntrustworthyError, ~r/fail on unmutated code/, fn ->
      run_fixture(source, suite)
    end
  end

  test "refuses to score a suite that does not give the same answer twice" do
    source = ~S"""
    defmodule LeakyBands do
      def band(n) when n < 100, do: :low
      def band(_n), do: :high
    end
    """

    suite = ~S"""
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

    assert_raise UntrustworthyError, fn -> run_fixture(source, suite) end
  end

  test "refuses when a test leaves a process running the mutant behind" do
    source = ~S"""
    defmodule LingeringBands do
      def band(n) when n < 100, do: :low
      def band(_n), do: :high

      def linger do
        Process.sleep(2_000)
        :done
      end
    end
    """

    suite = ~S"""
    defmodule LingeringBandsTest do
      use ExUnit.Case, async: false

      test "spawns a process that outlives it" do
        spawn(fn -> LingeringBands.linger() end)
        Process.sleep(20)

        assert LingeringBands.band(100) == :high
      end
    end
    """

    assert_raise UntrustworthyError, ~r/still running mutated/, fn ->
      run_fixture(source, suite)
    end
  end

  test "judges a mutant only by the tests it was given" do
    Code.put_compiler_option(:ignore_module_conflict, true)

    Code.compile_string(~S"""
    defmodule UnrelatedFailingTest do
      use ExUnit.Case, async: false

      test "fails for reasons of its own" do
        flunk("nothing to do with any mutant")
      end
    end
    """)

    source = ~S"""
    defmodule IsolatedBands do
      def band(n) when n < 100, do: :low
      def band(_n), do: :high
    end
    """

    suite = ~S"""
    defmodule IsolatedBandsTest do
      use ExUnit.Case, async: false

      test "the threshold itself is high" do
        assert IsolatedBands.band(100) == :high
      end
    end
    """

    report = run_fixture(source, suite)

    assert report.killed > 0
  end

  test "scores a suite that is green and repeatable" do
    source = ~S"""
    defmodule SteadyBands do
      def band(n) when n < 100, do: :low
      def band(_n), do: :high
    end
    """

    suite = ~S"""
    defmodule SteadyBandsTest do
      use ExUnit.Case, async: false

      test "the threshold itself is high" do
        assert SteadyBands.band(100) == :high
      end
    end
    """

    report = run_fixture(source, suite)

    assert report.killed > 0
  end
end
