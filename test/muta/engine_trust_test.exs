defmodule Muta.EngineTrustTest do
  use ExUnit.Case, async: false

  alias Muta.Config
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

    assert_raise UntrustworthyError, fn -> Muta.run(config) end
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

    assert_raise UntrustworthyError, ~r/still running mutated/, fn ->
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

  test "refuses when the target was compiled without debug info", %{dir: dir} do
    Code.put_compiler_option(:debug_info, false)

    on_exit(fn -> Code.put_compiler_option(:debug_info, true) end)

    file = Path.join(dir, "stripped_bands.ex")

    source = ~S"""
    defmodule StrippedBands do
      def band(n) when n < 100, do: :low
      def band(_n), do: :high
    end
    """

    File.write!(file, source)
    Code.prepend_path(dir)

    [{module, binary}] = Code.compile_string(source, file)
    File.write!(Path.join(dir, "#{module}.beam"), binary)
    :code.purge(module)
    :code.load_file(module)

    [{test_module, _binary}] =
      Code.compile_string(~S"""
      defmodule StrippedBandsTest do
        use ExUnit.Case, async: false

        test "the threshold itself is high" do
          assert StrippedBands.band(100) == :high
        end
      end
      """)

    config = Config.new([file], [test_module])

    assert_raise UntrustworthyError, ~r/without debug info/, fn ->
      Muta.run(config)
    end
  end
end
