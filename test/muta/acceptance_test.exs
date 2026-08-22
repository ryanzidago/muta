defmodule Muta.AcceptanceTest do
  use ExUnit.Case, async: true

  alias Muta.Acceptance
  alias Muta.Mutant
  alias Muta.Mutator.Comparison
  alias Muta.Support.Fixture

  setup do
    dir = Fixture.tmp_dir()
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp record(dir, contents) do
    path = Path.join(dir, "muta.exs")
    File.write!(path, contents)
    path
  end

  defp survivor(file, opts \\ []) do
    %Mutant{
      file: file,
      line: Keyword.get(opts, :line, 5),
      mutator: Comparison,
      function: "free_shipping?/1",
      original: Keyword.get(opts, :original, "cents > 5000"),
      mutated: Keyword.get(opts, :mutated, "cents >= 5000"),
      outcome: Keyword.get(opts, :outcome, :survived)
    }
  end

  test "reads nothing when no record exists", %{dir: dir} do
    assert Acceptance.read(Path.join(dir, "absent.exs")) == []
  end

  test "accepts a survivor whose expression matches", %{dir: dir} do
    path =
      record(dir, ~S"""
      [
        %{
          file: "lib/store/pricing.ex",
          original: "cents > 5000",
          mutated: "cents >= 5000",
          reason: "the boundary is unobservable from any caller"
        }
      ]
      """)

    accepted = Acceptance.apply_to(Acceptance.read(path), [survivor("lib/store/pricing.ex")])

    assert [%Mutant{outcome: :accepted}] = accepted
  end

  test "matches on the expression rather than the line, so edits above it do not stale", %{
    dir: dir
  } do
    path =
      record(dir, ~S"""
      [
        %{
          file: "lib/store/pricing.ex",
          original: "cents > 5000",
          mutated: "cents >= 5000",
          reason: "the boundary is unobservable from any caller"
        }
      ]
      """)

    moved = survivor("lib/store/pricing.ex", line: 91)

    assert [%Mutant{outcome: :accepted}] = Acceptance.apply_to(Acceptance.read(path), [moved])
  end

  test "leaves a survivor in another file alone", %{dir: dir} do
    path =
      record(dir, ~S"""
      [
        %{
          file: "lib/store/pricing.ex",
          original: "cents > 5000",
          mutated: "cents >= 5000",
          reason: "the boundary is unobservable from any caller"
        }
      ]
      """)

    elsewhere = survivor("lib/store/cart.ex")

    assert [%Mutant{outcome: :survived}] = Acceptance.apply_to(Acceptance.read(path), [elsewhere])
  end

  test "never turns a killed mutant into an accepted one", %{dir: dir} do
    path =
      record(dir, ~S"""
      [
        %{
          file: "lib/store/pricing.ex",
          original: "cents > 5000",
          mutated: "cents >= 5000",
          reason: "the boundary is unobservable from any caller"
        }
      ]
      """)

    killed = survivor("lib/store/pricing.ex", outcome: :killed)

    assert [%Mutant{outcome: :killed}] = Acceptance.apply_to(Acceptance.read(path), [killed])
  end

  test "reports the reason so a reader can check the claim", %{dir: dir} do
    path =
      record(dir, ~S"""
      [
        %{
          file: "lib/store/pricing.ex",
          original: "cents > 5000",
          mutated: "cents >= 5000",
          reason: "the boundary is unobservable from any caller"
        }
      ]
      """)

    acceptances = Acceptance.read(path)

    assert Acceptance.reason_for(acceptances, survivor("lib/store/pricing.ex")) ==
             "the boundary is unobservable from any caller"
  end

  test "names an accepted mutant that matched nothing in the run", %{dir: dir} do
    path =
      record(dir, ~S"""
      [
        %{
          file: "lib/store/pricing.ex",
          original: "cents > 9999",
          mutated: "cents >= 9999",
          reason: "long since deleted"
        }
      ]
      """)

    acceptances = Acceptance.read(path)

    assert [%Acceptance{original: "cents > 9999"}] =
             Acceptance.unused(acceptances, [survivor("lib/store/pricing.ex")])
  end

  test "matches an expression written on one line against a mutant spanning several", %{dir: dir} do
    path =
      record(dir, ~S"""
      [
        %{
          file: "lib/store/pricing.ex",
          original: "a and b",
          mutated: "a or b",
          reason: "both spellings crash the same way"
        }
      ]
      """)

    wrapped =
      survivor("lib/store/pricing.ex", original: "a and\n  b", mutated: "a or\n  b")

    assert [%Mutant{outcome: :accepted}] = Acceptance.apply_to(Acceptance.read(path), [wrapped])
  end

  test "raises when an entry has no reason", %{dir: dir} do
    path =
      record(dir, ~S"""
      [%{file: "lib/store/pricing.ex", original: "a > b", mutated: "a >= b", reason: ""}]
      """)

    assert_raise ArgumentError, ~r/non-empty :reason/, fn -> Acceptance.read(path) end
  end

  test "raises when an entry is missing a key", %{dir: dir} do
    path =
      record(dir, ~S"""
      [%{file: "lib/store/pricing.ex", original: "a > b"}]
      """)

    assert_raise ArgumentError, ~r/cannot read/, fn -> Acceptance.read(path) end
  end

  test "raises when the record is not a list", %{dir: dir} do
    path =
      record(dir, ~S"""
      %{file: "lib/store/pricing.ex"}
      """)

    assert_raise ArgumentError, ~r/must return a list/, fn -> Acceptance.read(path) end
  end
end
