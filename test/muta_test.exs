defmodule MutaTest do
  use ExUnit.Case, async: false

  alias Muta.Config
  alias Muta.Report
  alias Muta.Target

  setup do
    dir = Path.join(System.tmp_dir!(), "muta-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    Code.put_compiler_option(:ignore_module_conflict, true)

    %{dir: dir}
  end

  defp write_target(dir, name, source, suite) do
    file = Path.join(dir, "#{name}.ex")
    File.write!(file, source)
    Code.compile_string(source, file)
    [{test_module, _binary}] = Code.compile_string(suite)

    %Target{file: file, test_modules: [test_module]}
  end

  test "reports surviving mutants across every file it is given", %{dir: dir} do
    weak =
      write_target(
        dir,
        "weak_gate",
        ~S"""
        defmodule WeakGate do
          def open?(n), do: n > 10
        end
        """,
        ~S"""
        defmodule WeakGateTest do
          use ExUnit.Case, async: false

          test "returns a boolean" do
            assert is_boolean(WeakGate.open?(50))
          end
        end
        """
      )

    strong =
      write_target(
        dir,
        "strong_gate",
        ~S"""
        defmodule StrongGate do
          def open?(n), do: n > 10
        end
        """,
        ~S"""
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
        """
      )

    report = Muta.run(Config.new([weak, strong]))

    survivors = Report.survivors(report)

    assert Enum.all?(survivors, &(&1.file =~ "weak_gate"))
    assert report.survived == 2
    assert report.killed == 2
  end

  test "raises when a target file does not exist" do
    target = %Target{file: "does/not/exist.ex", test_modules: []}

    assert_raise File.Error, fn -> Muta.run(Config.new([target])) end
  end
end
