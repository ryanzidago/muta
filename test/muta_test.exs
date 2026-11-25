defmodule MutaTest do
  use ExUnit.Case, async: false

  alias Muta.Config
  alias Muta.Mutation
  alias Muta.Report
  alias Muta.Support.Fixture

  setup do
    Code.put_compiler_option(:ignore_module_conflict, true)
    dir = Fixture.tmp_dir()
    on_exit(fn -> File.rm_rf!(dir) end)

    %{dir: dir}
  end

  test "reports surviving mutants across every file it is given", %{dir: dir} do
    weak =
      Fixture.target(dir, "weak_gate", ~S"""
      defmodule WeakGate do
        def open?(n), do: n > 10
      end
      """)

    weak_suite =
      Fixture.test_file(dir, "weak_gate", ~S"""
      defmodule WeakGateTest do
        use ExUnit.Case, async: false

        test "returns a boolean" do
          assert is_boolean(WeakGate.open?(50))
        end
      end
      """)

    strong =
      Fixture.target(dir, "strong_gate", ~S"""
      defmodule StrongGate do
        def open?(n), do: n > 10
      end
      """)

    strong_suite =
      Fixture.test_file(dir, "strong_gate", ~S"""
      defmodule StrongGateTest do
        use ExUnit.Case, async: false

        test "the threshold itself is closed" do
          refute StrongGate.open?(10)
        end

        test "above the threshold is open" do
          assert StrongGate.open?(11)
        end

        test "below the threshold is closed" do
          refute StrongGate.open?(9)
        end
      end
      """)

    report =
      Muta.run(
        Config.new([weak, strong], [weak_suite, strong_suite],
          workers: 1,
          test_helper: Fixture.helper(dir)
        )
      )

    assert Enum.all?(Report.survivors(report), &(&1.file =~ "weak_gate"))
    assert report.survived == 3
    assert report.killed == 3
  end

  test "judges every mutant exactly once when several workers share the work", %{dir: dir} do
    source =
      Fixture.target(dir, "shared_gates", ~S"""
      defmodule SharedGates do
        def open?(n), do: n > 10
        def big?(n), do: n > 100
        def huge?(n), do: n > 1000
      end
      """)

    tests =
      Fixture.test_file(dir, "shared_gates", ~S"""
      defmodule SharedGatesTest do
        use ExUnit.Case, async: false

        test "the open threshold itself is closed" do
          refute SharedGates.open?(10)
        end

        test "a step over the open threshold is open" do
          assert SharedGates.open?(11)
        end
      end
      """)

    report =
      Muta.run(Config.new([source], [tests], workers: 3, test_helper: Fixture.helper(dir)))

    assert length(report.mutants) == 9
    assert report.killed == 3
    assert report.survived == 6

    assert Enum.map(Report.survivors(report), & &1.mutated) |> Enum.sort() == [
             "n < 100",
             "n < 1000",
             "n > 1001",
             "n > 101",
             "n >= 100",
             "n >= 1000"
           ]
  end

  test "keeps completed verdicts, stops dispatching and records failed and pending identities",
       %{dir: dir} do
    slow = flag_source(dir, "slow_gate")
    fast = flag_source(dir, "fast_gate")
    drain = flag_source(dir, "drain_gate")
    in_flight = flag_source(dir, "in_flight_gate")
    pending = flag_source(dir, "pending_gate")

    tests =
      Fixture.test_file(dir, "incomplete_gates", ~S"""
      defmodule IncompleteGatesTest do
        use ExUnit.Case, async: false

        setup_all do
          cond do
            SlowGate.open?() -> Process.sleep(8_000)
            DrainGate.open?() -> Process.sleep(800)
            InFlightGate.open?() -> Process.sleep(2_700)
            true -> :ok
          end
        end

        test "each gate returns a boolean" do
          assert Enum.all?([SlowGate, FastGate, DrainGate, InFlightGate, PendingGate], fn gate ->
                   is_boolean(gate.open?())
                 end)
        end
      end
      """)

    acceptances =
      Fixture.target(dir, "incomplete_acceptances", """
      [
        %{
          file: "#{Path.expand(slow)}",
          original: "false",
          mutated: "true",
          reason: "a timed-out mutant must not be accepted"
        }
      ]
      """)

    report =
      Muta.run(
        Config.new([slow, fast, drain, in_flight, pending], [tests],
          workers: 2,
          baseline_timeout_ms: 3_000,
          test_helper: Fixture.helper(dir),
          acceptances_file: acceptances,
          mutators: [Muta.Mutator.Boolean]
        )
      )

    assert report.complete? == false
    assert report.score == nil
    assert report.accepted == 0

    assert Enum.map(report.mutants, & &1.file) |> Enum.sort() ==
             Enum.sort([fast, drain, in_flight])

    assert Enum.all?(report.mutants, &(&1.outcome == :survived))

    assert [
             %{
               mutation: %Mutation{file: ^slow, original: "false", mutated: "true"},
               reason: reason
             }
           ] =
             report.failures

    assert reason =~ "within 3000ms"
    assert [%Mutation{file: ^pending}] = report.pending
  end

  test "reports the first failed mutant and leaves later mutants pending", %{dir: dir} do
    slow = flag_source(dir, "first_slow_gate")
    pending = flag_source(dir, "later_pending_gate")

    tests =
      Fixture.test_file(dir, "first_failure", ~S"""
      defmodule FirstFailureTest do
        use ExUnit.Case, async: false

        setup_all do
          if FirstSlowGate.open?(), do: Process.sleep(4_000)
          :ok
        end

        test "both gates return a boolean" do
          assert is_boolean(FirstSlowGate.open?())
          assert is_boolean(LaterPendingGate.open?())
        end
      end
      """)

    report =
      Muta.run(
        Config.new([slow, pending], [tests],
          workers: 1,
          baseline_timeout_ms: 1_000,
          test_helper: Fixture.helper(dir),
          mutators: [Muta.Mutator.Boolean]
        )
      )

    assert report.complete? == false
    assert report.mutants == []
    assert report.score == nil
    assert [%{mutation: %Mutation{file: ^slow}, reason: reason}] = report.failures
    assert reason =~ "within 1000ms"
    assert [%Mutation{file: ^pending}] = report.pending
  end

  defp flag_source(dir, name) do
    module = Macro.camelize(name)

    Fixture.target(dir, name, """
    defmodule #{module} do
      def open?, do: false
    end
    """)
  end

  test "raises when a target file does not exist" do
    assert_raise File.Error, fn -> Config.new(["does/not/exist.ex"], []) end
  end

  test "requires a positive baseline timeout", %{dir: dir} do
    source = flag_source(dir, "timeout_validation")

    assert_raise ArgumentError, ~r/positive baseline timeout/, fn ->
      Config.new([source], [], baseline_timeout_ms: 0)
    end
  end
end
