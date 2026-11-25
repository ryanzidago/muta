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
      {:mix_shell, level, [message]} when level in [:info, :error] -> [message | messages()]
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

        test "a cent over the threshold does" do
          assert #{Macro.camelize(name)}.free_shipping?(5_001)
        end
      end
      """)

    {source, tests}
  end

  test "prints the report as json and nothing else when asked for it", %{dir: dir} do
    {source, tests} = weakly_tested_gate(dir, "json_gate")

    assert catch_exit(Mutate.run([source, "--test", tests, "--workers", "1", "--format", "json"])) ==
             {:shutdown, 1}

    decoded = output() |> String.trim() |> JSON.decode!()

    assert decoded["score"] == 66.67
    assert decoded["totals"]["survived"] == 1
    assert decoded["files"] == [source]

    assert %{"line" => 2, "mutated" => "cents >= 5000", "mutator" => "Comparison"} =
             Enum.find(decoded["mutants"], &(&1["outcome"] == "survived"))
  end

  test "prints incomplete JSON with the failed mutant and exits 2", %{dir: dir} do
    source =
      Fixture.target(dir, "timed_out_gate", ~S"""
      defmodule TimedOutGate do
        def open?, do: false
      end
      """)

    tests =
      Fixture.test_file(dir, "timed_out_gate", ~S"""
      defmodule TimedOutGateTest do
        use ExUnit.Case, async: false

        setup_all do
          if TimedOutGate.open?(), do: Process.sleep(1_000)
          :ok
        end

        test "the gate is boolean" do
          assert is_boolean(TimedOutGate.open?())
        end
      end
      """)

    assert catch_exit(
             Mutate.run([
               source,
               "--test",
               tests,
               "--workers",
               "1",
               "--baseline-timeout-ms",
               "300",
               "--format",
               "json"
             ])
           ) == {:shutdown, 2}

    decoded = output() |> String.trim() |> JSON.decode!()

    assert decoded["complete"] == false
    assert decoded["score"] == nil
    assert decoded["totals"]["unjudged"] == 1

    assert [%{"file" => ^source, "line" => 2, "at" => at, "reason" => reason}] =
             decoded["failures"]

    assert is_integer(at)
    assert reason =~ "within 300ms"
    assert decoded["mutants"] == []
    assert decoded["pending"] == []
  end

  test "refuses a format it does not know rather than guessing", %{dir: dir} do
    {source, tests} = weakly_tested_gate(dir, "unknown_format")

    assert_raise Mix.Error, ~r/does not know the format "yaml"/, fn ->
      Mutate.run([source, "--test", tests, "--workers", "1", "--format", "yaml"])
    end
  end

  test "says how many mutants it never generated inside a type guard", %{dir: dir} do
    source =
      Fixture.target(dir, "guarded_fetch", ~S"""
      defmodule GuardedFetch do
        def fetch(id, scope) when is_binary(id) and is_binary(scope), do: :ok
        def fetch(_id, _scope), do: :error
      end
      """)

    tests =
      Fixture.test_file(dir, "guarded_fetch", ~S"""
      defmodule GuardedFetchTest do
        use ExUnit.Case, async: false

        test "both binaries are fetched" do
          assert GuardedFetch.fetch("a", "b") == :ok
        end

        test "anything else is not" do
          assert GuardedFetch.fetch(1, "b") == :error
        end
      end
      """)

    assert Mutate.run([source, "--test", tests, "--workers", "1"]) == :ok

    printed = output()

    assert printed =~ "1 mutant(s) inside type guards were never generated"
    assert printed =~ "no test can tell"
  end

  test "says nothing about type guards when none suppressed a mutant", %{dir: dir} do
    {source, tests} = weakly_tested_gate(dir, "unguarded_gate")

    catch_exit(Mutate.run([source, "--test", tests, "--workers", "1"]))

    refute output() =~ "inside type guards"
  end

  test "prints each survivor as a diff and exits 1", %{dir: dir} do
    {source, tests} = weakly_tested_gate(dir, "task_gate")

    assert catch_exit(Mutate.run([source, "--test", tests, "--workers", "1"])) == {:shutdown, 1}

    printed = output()

    assert printed =~ "Mutating #{source}"
    assert printed =~ "Judged by #{tests}"
    assert printed =~ "- cents > 5000"
    assert printed =~ "+ cents >= 5000"
    assert printed =~ "survived"

    assert printed =~
             "3 mutants · 2 killed · 1 survived · 0 accepted · 0 unstable · 0 invalid · 66.67%"
  end

  test "an accepted mutant stops failing the run and shows why", %{dir: dir} do
    {source, tests} = weakly_tested_gate(dir, "accepted_gate")

    record =
      Fixture.target(dir, "muta_record", """
      [
        %{
          file: "#{source}",
          original: "cents > 5000",
          mutated: "cents >= 5000",
          reason: "the exact-5000 cart is unreachable from any caller"
        }
      ]
      """)

    Mutate.run([source, "--test", tests, "--workers", "1", "--acceptances-file", record])

    printed = output()

    assert printed =~ "accepted"
    assert printed =~ "the exact-5000 cart is unreachable from any caller"
    assert printed =~ "3 mutants · 2 killed · 0 survived · 1 accepted · 0 unstable · 0 invalid"
  end

  test "says when an accepted mutant matched nothing, since a stale one hides a real survivor",
       %{dir: dir} do
    {source, tests} = weakly_tested_gate(dir, "stale_gate")

    record =
      Fixture.target(dir, "stale_record", """
      [
        %{
          file: "#{source}",
          original: "cents > 9999",
          mutated: "cents >= 9999",
          reason: "deleted long ago"
        }
      ]
      """)

    assert catch_exit(
             Mutate.run([source, "--test", tests, "--workers", "1", "--acceptances-file", record])
           ) == {:shutdown, 1}

    assert output() =~ "matched nothing in this run"
  end

  test "collapses repeats of one accepted pattern too", %{dir: dir} do
    source =
      Fixture.target(dir, "twice_gate", """
      defmodule TwiceGate do
        def a(cents), do: cents > 5000
        def b(cents), do: cents > 5000
      end
      """)

    tests =
      Fixture.test_file(dir, "twice_gate", """
      defmodule TwiceGateTest do
        use ExUnit.Case, async: false

        test "both read the same way" do
          assert TwiceGate.a(9_000)
          assert TwiceGate.b(9_000)
        end

        test "both pin a cent over the threshold" do
          assert TwiceGate.a(5_001)
          assert TwiceGate.b(5_001)
        end
      end
      """)

    record =
      Fixture.target(dir, "twice_record", """
      [
        %{
          file: "#{source}",
          original: "cents > 5000",
          mutated: "cents >= 5000",
          reason: "the exact-5000 cart is unreachable"
        }
      ]
      """)

    Mutate.run([source, "--test", tests, "--workers", "1", "--acceptances-file", record])

    printed = output()

    assert printed =~ "accepted"
    assert printed =~ "(2 sites)"
    assert printed =~ "0 survived · 2 accepted"
  end

  test "collapses repeats of one pattern into a single finding", %{dir: dir} do
    source =
      Fixture.target(dir, "repeated_gate", """
      defmodule RepeatedGate do
        def a(cents), do: cents > 5000
        def b(cents), do: cents > 5000
      end
      """)

    tests =
      Fixture.test_file(dir, "repeated_gate", """
      defmodule RepeatedGateTest do
        use ExUnit.Case, async: false

        test "both read the same way" do
          assert RepeatedGate.a(9_000)
          assert RepeatedGate.b(9_000)
        end
      end
      """)

    assert catch_exit(Mutate.run([source, "--test", tests, "--workers", "1"])) == {:shutdown, 1}

    printed = output()

    assert printed =~ "(2 sites)"
    assert printed =~ "2,3"
  end

  test "names a function nothing reached", %{dir: dir} do
    {source, tests} = weakly_tested_gate(dir, "unreached_gate")

    assert catch_exit(Mutate.run([source, "--test", tests, "--workers", "1"])) == {:shutdown, 1}

    refute output() =~ "may not reach them at all"
  end

  test "keeps invalid mutants out of the report unless asked for them", %{dir: dir} do
    {source, tests} = weakly_tested_gate(dir, "quiet_gate")

    catch_exit(Mutate.run([source, "--test", tests, "--workers", "1"]))

    refute output() =~ "invalid  "
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

    assert Mutate.run([source, "--test", tests, "--workers", "1"]) == :ok

    assert output() =~
             "3 mutants · 3 killed · 0 survived · 0 accepted · 0 unstable · 0 invalid · 100.0%"
  end

  test "says so when the source has nothing to mutate", %{dir: dir} do
    quiet =
      Fixture.target(dir, "no_comparisons", ~S"""
      defmodule NoComparisons do
        def label(word), do: word <> "!"
      end
      """)

    quiet_tests =
      Fixture.test_file(dir, "no_comparisons", ~S"""
      defmodule NoComparisonsTest do
        use ExUnit.Case, async: false

        test "labels" do
          assert NoComparisons.label("hi") == "hi!"
        end
      end
      """)

    assert Mutate.run([quiet, "--test", quiet_tests, "--workers", "1"]) == :ok
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

    assert catch_exit(Mutate.run([source, "--test", empty, "--workers", "1"])) ==
             {:shutdown, 2}

    printed = output()

    assert printed =~ "muta refused to score this run"
    assert printed =~ "defines no ExUnit tests"
  end

  test "refuses when a named test file was already loaded", %{dir: dir} do
    {source, tests} = weakly_tested_gate(dir, "loaded_gate")
    Code.require_file(tests)

    assert catch_exit(Mutate.run([source, "--test", tests, "--workers", "1"])) ==
             {:shutdown, 2}

    assert output() =~ "was already loaded"
  end

  test "refuses to run outside the test environment", %{dir: dir} do
    {source, tests} = weakly_tested_gate(dir, "env_gate")

    try do
      Mix.env(:dev)

      assert_raise Mix.Error, ~r/must run in the test environment/, fn ->
        Mutate.run([source, "--test", tests, "--workers", "1"])
      end
    after
      Mix.env(:test)
    end
  end

  test "keeps a survivor spanning several lines to one line each", %{dir: dir} do
    source =
      Fixture.target(dir, "branching_gate", ~S"""
      defmodule BranchingGate do
        def status(seats) do
          if seats > 0 do
            :open
          else
            :full
          end
        end
      end
      """)

    tests =
      Fixture.test_file(dir, "branching_gate", ~S"""
      defmodule BranchingGateTest do
        use ExUnit.Case, async: false

        test "a room with seats is open" do
          assert BranchingGate.status(5) == :open
        end
      end
      """)

    assert catch_exit(Mutate.run([source, "--test", tests, "--workers", "1"])) ==
             {:shutdown, 1}

    printed = output()

    assert printed =~ "- if seats > 0 do …"
    assert printed =~ "+ if true do …"
    refute printed =~ ":full\n"
  end

  test "marks a mutant the tests judged twice and disagreed on as unstable", %{dir: dir} do
    source =
      Fixture.target(dir, "wobbly_gate", ~S"""
      defmodule WobblyGate do
        def exact?(n, limit), do: n == limit
        def big?(n), do: n > 100
      end
      """)

    tests =
      Fixture.test_file(dir, "wobbly_gate", ~S"""
      defmodule WobblyGateTest do
        use ExUnit.Case, async: false

        setup_all do
          run = :persistent_term.get(:muta_wobbly_gate_runs, 0) + 1
          :persistent_term.put(:muta_wobbly_gate_runs, run)

          %{run: run, in_worker?: to_string(node()) =~ "worker"}
        end

        test "fails the first mutant a worker judges, passes on the re-run", context do
          refute context.in_worker? and context.run == 2
        end

        test "the threshold itself is not big" do
          refute WobblyGate.big?(100)
          assert WobblyGate.big?(101)
        end
      end
      """)

    on_exit(fn -> :persistent_term.erase(:muta_wobbly_gate_runs) end)

    assert catch_exit(Mutate.run([source, "--test", tests, "--workers", "1"])) ==
             {:shutdown, 1}

    printed = output()

    assert printed =~ "unstable  #{source}:2  Comparison"

    assert printed =~
             "4 mutants · 3 killed · 0 survived · 0 accepted · 1 unstable · 0 invalid · 100.0%"

    assert printed =~ "failed on the first run and passed on the re-run"
  end

  test "says why a mutant the compiler rejected is left out of the score", %{dir: dir} do
    source =
      Fixture.target(dir, "strict_tags", ~S"""
      defmodule StrictTags do
        require Muta.Support.StrictMacro

        def tag, do: Muta.Support.StrictMacro.must_be_ok(:ok)
        def big?(n), do: n > 10
      end
      """)

    tests =
      Fixture.test_file(dir, "strict_tags", ~S"""
      defmodule StrictTagsTest do
        use ExUnit.Case, async: false

        test "the threshold itself is not big" do
          refute StrictTags.big?(10)
          assert StrictTags.big?(11)
        end
      end
      """)

    assert Mutate.run([source, "--test", tests, "--workers", "1"]) == :ok

    printed = output()

    assert printed =~
             "4 mutants · 3 killed · 0 survived · 0 accepted · 0 unstable · 1 invalid · 100.0%"

    assert printed =~ "1 invalid: the mutated code did not compile"
  end

  test "scores each source file on its own when given several", %{dir: dir} do
    {weak_source, weak_tests} = weakly_tested_gate(dir, "weak_half")

    strong_source =
      Fixture.target(dir, "strong_half", ~S"""
      defmodule StrongHalf do
        def free_shipping?(cents), do: cents > 5000
      end
      """)

    strong_tests =
      Fixture.test_file(dir, "strong_half", ~S"""
      defmodule StrongHalfTest do
        use ExUnit.Case, async: false

        test "the threshold itself does not ship free" do
          refute StrongHalf.free_shipping?(5_000)
          assert StrongHalf.free_shipping?(5_001)
        end
      end
      """)

    assert catch_exit(
             Mutate.run([
               weak_source,
               strong_source,
               "--test",
               weak_tests,
               "--test",
               strong_tests,
               "--workers",
               "1"
             ])
           ) == {:shutdown, 1}

    printed = output()

    assert printed =~ "#{weak_source}  3 mutants · 2 killed · 1 survived"
    assert printed =~ "#{strong_source}  3 mutants · 3 killed · 0 survived"

    assert printed =~
             "6 mutants · 5 killed · 1 survived · 0 accepted · 0 unstable · 0 invalid · 83.33%"
  end

  test "says which named source files produced nothing to check", %{dir: dir} do
    {gate, gate_tests} = weakly_tested_gate(dir, "checked_gate")

    quiet =
      Fixture.target(dir, "quiet_label", ~S"""
      defmodule QuietLabel do
        def shout(word), do: word <> "!"
      end
      """)

    quiet_tests =
      Fixture.test_file(dir, "quiet_label", ~S"""
      defmodule QuietLabelTest do
        use ExUnit.Case, async: false

        test "shouts" do
          assert QuietLabel.shout("hi") == "hi!"
        end
      end
      """)

    assert catch_exit(
             Mutate.run([
               gate,
               quiet,
               "--test",
               gate_tests,
               "--test",
               quiet_tests,
               "--workers",
               "1"
             ])
           ) == {:shutdown, 1}

    printed = output()

    assert printed =~ "#{quiet}  no mutants, so nothing here was checked"
    assert printed =~ "#{gate}  3 mutants · 2 killed · 1 survived"
    assert printed =~ "1 of the 2 files you named produced no mutants and went unchecked"
  end
end
