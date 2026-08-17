defmodule Mix.Tasks.MutateTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Mutate
  alias Muta.Support.Fixture

  setup do
    Code.put_compiler_option(:ignore_module_conflict, true)
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    dir = Fixture.tmp_dir()

    on_exit(fn ->
      Mix.shell(shell)
      File.rm_rf!(dir)
    end)

    %{dir: dir}
  end

  defp output, do: Enum.join(messages(), "\n")

  defp messages do
    receive do
      {:mix_shell, :info, [message]} -> [message | messages()]
    after
      0 -> []
    end
  end

  defp weakly_tested_gate(dir, name) do
    source =
      Fixture.target(dir, name, """
      defmodule #{Macro.camelize(name)} do
        def free_shipping?(cents), do: cents > 5000
      end
      """)

    tests =
      Fixture.test_file(dir, name, """
      defmodule #{Macro.camelize(name)}Test do
        use ExUnit.Case, async: false

        test "a big order ships free" do
          assert #{Macro.camelize(name)}.free_shipping?(9_000)
        end

        test "a small order does not" do
          refute #{Macro.camelize(name)}.free_shipping?(1_000)
        end
      end
      """)

    {source, tests}
  end

  test "prints each survivor as a diff and exits 1", %{dir: dir} do
    {source, tests} = weakly_tested_gate(dir, "task_gate")

    assert catch_exit(Mutate.run([source, "--test", tests])) == {:shutdown, 1}

    printed = output()

    assert printed =~ "Mutating #{source}"
    assert printed =~ "Judged by #{tests}"
    assert printed =~ "- cents > 5000"
    assert printed =~ "+ cents >= 5000"
    assert printed =~ "survived"
    assert printed =~ "2 mutants · 1 killed · 1 survived · 0 invalid · 50.0%"
  end

  test "exits without failing when every mutant is killed", %{dir: dir} do
    source =
      Fixture.target(dir, "pinned_gate", ~S"""
      defmodule PinnedGate do
        def free_shipping?(cents), do: cents > 5000
      end
      """)

    tests =
      Fixture.test_file(dir, "pinned_gate", ~S"""
      defmodule PinnedGateTest do
        use ExUnit.Case, async: false

        test "the threshold itself does not ship free" do
          refute PinnedGate.free_shipping?(5_000)
        end

        test "a cent over does" do
          assert PinnedGate.free_shipping?(5_001)
        end
      end
      """)

    assert Mutate.run([source, "--test", tests]) == :ok
    assert output() =~ "2 mutants · 2 killed · 0 survived · 0 invalid · 100.0%"
  end

  test "says so when the source has nothing to mutate", %{dir: dir} do
    {_source, tests} = weakly_tested_gate(dir, "spare_gate")

    quiet =
      Fixture.target(dir, "no_comparisons", ~S"""
      defmodule NoComparisons do
        def shout(word), do: String.upcase(word)
      end
      """)

    assert Mutate.run([quiet, "--test", tests]) == :ok
    assert output() =~ "Nothing in these files can be mutated yet"
  end

  test "refuses when no tests were named", %{dir: dir} do
    {source, _tests} = weakly_tested_gate(dir, "unnamed_gate")

    assert_raise Mix.Error, ~r/needs the source files to mutate/, fn ->
      Mutate.run([source])
    end
  end

  test "refuses when a named test file defines no tests", %{dir: dir} do
    {source, _tests} = weakly_tested_gate(dir, "testless_gate")
    empty = Fixture.test_file(dir, "empty", "_ = :nothing_here\n")

    assert_raise Mix.Error, ~r/defines no ExUnit tests/, fn ->
      Mutate.run([source, "--test", empty])
    end
  end

  test "refuses when a named test file was already loaded", %{dir: dir} do
    {source, tests} = weakly_tested_gate(dir, "loaded_gate")
    Code.require_file(tests)

    assert_raise Mix.Error, ~r/was already loaded/, fn ->
      Mutate.run([source, "--test", tests])
    end
  end

  test "refuses to run outside the test environment", %{dir: dir} do
    {source, tests} = weakly_tested_gate(dir, "env_gate")

    try do
      Mix.env(:dev)

      assert_raise Mix.Error, ~r/must run in the test environment/, fn ->
        Mutate.run([source, "--test", tests])
      end
    after
      Mix.env(:test)
    end
  end
end
