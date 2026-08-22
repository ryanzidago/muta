defmodule Muta.ChangedTest do
  use ExUnit.Case, async: true

  alias Muta.Changed
  alias Muta.Support.Fixture

  defp repo_with(dir, first, second) do
    File.mkdir_p!(dir)
    path = Path.join(dir, "gate.ex")

    git = fn args ->
      {output, status} =
        System.cmd("git", args,
          cd: dir,
          stderr_to_stdout: true,
          env: [{"GIT_CONFIG_GLOBAL", "/dev/null"}, {"GIT_CONFIG_SYSTEM", "/dev/null"}]
        )

      assert status == 0, "git #{Enum.join(args, " ")} failed: #{output}"
    end

    git.(["init", "-q", "-b", "main"])
    git.(["config", "user.email", "muta@example.test"])
    git.(["config", "user.name", "muta"])

    File.write!(path, first)
    git.(["add", "gate.ex"])
    git.(["commit", "-q", "-m", "first"])

    File.write!(path, second)

    path
  end

  setup do
    dir = Fixture.tmp_dir()
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "counts every line of a source when nothing scopes it" do
    assert Changed.every_line("one\ntwo\nthree") == MapSet.new([1, 2, 3])
  end

  test "counts a single line" do
    assert Changed.every_line("only") == MapSet.new([1])
  end

  test "names only the lines a ref changed", %{dir: dir} do
    path =
      repo_with(
        dir,
        "line one\nline two\nline three\n",
        "line one\nline two changed\nline three\n"
      )

    assert Changed.lines_since("HEAD", path) == MapSet.new([2])
  end

  test "names every line of a multi-line addition", %{dir: dir} do
    path =
      repo_with(
        dir,
        "line one\nline two\n",
        "line one\nadded a\nadded b\nline two\n"
      )

    assert Changed.lines_since("HEAD", path) == MapSet.new([2, 3])
  end

  test "names nothing when the file did not change", %{dir: dir} do
    path = repo_with(dir, "line one\n", "line one\n")

    assert Changed.lines_since("HEAD", path) == MapSet.new()
  end

  test "raises when the ref cannot be diffed", %{dir: dir} do
    path = repo_with(dir, "line one\n", "line two\n")

    assert_raise ArgumentError, ~r/muta needs a ref it can diff against/, fn ->
      Changed.lines_since("no-such-ref", path)
    end
  end
end
