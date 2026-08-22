defmodule MutaTest do
  use ExUnit.Case, async: false

  alias Muta.Config
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
    assert report.survived == 2
    assert report.killed == 2
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

    assert length(report.mutants) == 6
    assert report.killed == 2
    assert report.survived == 4

    assert Enum.map(Report.survivors(report), & &1.mutated) |> Enum.sort() == [
             "n < 100",
             "n < 1000",
             "n >= 100",
             "n >= 1000"
           ]
  end

  test "raises when a target file does not exist" do
    assert_raise File.Error, fn -> Config.new(["does/not/exist.ex"], []) end
  end
end
