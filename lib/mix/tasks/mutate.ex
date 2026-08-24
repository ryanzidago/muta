defmodule Mix.Tasks.Mutate do
  use Mix.Task

  alias Muta.Acceptance
  alias Muta.Config
  alias Muta.Report
  alias Muta.Report.Json
  alias Muta.UntrustworthyError

  @shortdoc "Reports which mutants of the given source files survive the given tests"

  @impl Mix.Task
  def run(argv) do
    ensure_test_env!()
    Mix.Task.run("app.start")
    Application.put_env(:ex_unit, :autorun, false)

    {opts, sources} =
      OptionParser.parse!(argv,
        strict: [
          test: :keep,
          workers: :integer,
          acceptances_file: :string,
          since: :string,
          show_invalid: :boolean,
          format: :string
        ]
      )

    test_files = Keyword.get_values(opts, :test)
    format = format!(Keyword.get(opts, :format, "human"))

    ensure_both_given!(sources, test_files)
    announce(format, sources, test_files)

    config =
      Config.new(sources, test_files, Keyword.take(opts, [:workers, :acceptances_file, :since]))

    report = judge(config)

    render(format, report, config, Keyword.get(opts, :show_invalid, false))
    exit_for(report)
  end

  defp format!(format) when format in ["human", "json"], do: format

  defp format!(format) do
    Mix.raise("mix mutate does not know the format #{inspect(format)}. Use human or json.")
  end

  defp judge(%Config{} = config) do
    Muta.run(config)
  rescue
    refusal in UntrustworthyError ->
      Mix.shell().error("muta refused to score this run.\n\n" <> Exception.message(refusal))

      exit({:shutdown, 2})
  end

  defp ensure_both_given!(sources, test_files) when sources == [] or test_files == [] do
    Mix.raise("""
    mix mutate needs the source files to mutate and the tests to judge them by.

        mix mutate lib/store/pricing.ex --test test/store/pricing_test.exs

    Pass --test once per test file. Every mutant is judged only by the tests you
    name here, so a mutant reported as surviving means those tests did not catch
    it, not that nothing in your suite would.
    """)
  end

  defp ensure_both_given!(_sources, _test_files), do: :ok

  defp announce("json", _sources, _test_files), do: :ok

  defp announce("human", sources, test_files) do
    Mix.shell().info(
      "Mutating #{Enum.join(sources, ", ")}\n" <>
        "Judged by #{Enum.join(test_files, ", ")}\n"
    )
  end

  defp ensure_test_env! do
    if Mix.env() != :test do
      Mix.raise("""
      mix mutate must run in the test environment.

      Add it to your project's preferred envs in mix.exs:

          def cli do
            [preferred_envs: [mutate: :test]]
          end

      or run it as MIX_ENV=test mix mutate
      """)
    end
  end

  defp render("json", %Report{} = report, %Config{}, _show_invalid) do
    Mix.shell().info(Json.encode(report))
  end

  defp render("human", %Report{mutants: []}, %Config{}, _show_invalid) do
    Mix.shell().info("No mutants generated. Nothing in these files can be mutated yet.")
  end

  defp render("human", %Report{} = report, %Config{} = config, show_invalid) do
    render_grouped(Report.survivors(report) ++ Report.unstable(report))

    report |> Report.by_file() |> render_breakdown()

    Mix.shell().info(tally(report))

    render_accepted(Report.accepted(report), config.acceptances)
    render_invalid(Report.invalid(report), show_invalid)
    render_notes(report)
    render_unexercised(Report.unexercised(report))
    render_skipped(report.skipped)
    render_type_guards(report.in_type_guards)
    render_unused(Acceptance.unused(config.acceptances, report.mutants))
  end

  defp render_accepted([], _acceptances), do: :ok

  defp render_accepted(accepted, acceptances) do
    Mix.shell().info("")

    accepted
    |> Enum.group_by(&{&1.file, &1.mutator, &1.original, &1.mutated})
    |> Enum.sort_by(fn {_pattern, [first | _rest]} -> {first.file, first.line} end)
    |> Enum.each(&render_accepted_pattern(&1, acceptances))
  end

  defp render_accepted_pattern({{file, mutator, original, mutated}, [first | _] = mutants}, acc) do
    Mix.shell().info("""
      accepted  #{file}:#{sites(mutants)}  #{mutator(mutator)}
        - #{first_line(original)}
        + #{first_line(mutated)}
        #{Acceptance.reason_for(acc, first)}
    """)
  end

  defp render_invalid([], _show_invalid), do: :ok
  defp render_invalid(_invalid, false), do: :ok

  defp render_invalid(invalid, true) do
    Mix.shell().info("")
    render_grouped(invalid)
  end

  defp render_unexercised([]), do: :ok

  defp render_unexercised(functions) do
    Mix.shell().info("""

    Every mutant in these survived, so the tests you named may not reach them at all:

    #{Enum.map_join(functions, "\n", fn {file, function} -> "  #{file}  #{function}" end)}\
    """)
  end

  defp render_skipped(0), do: :ok

  defp render_skipped(skipped) do
    Mix.shell().info("""

    #{skipped} mutant(s) fell outside the lines --since named and were not judged.
    The score above covers the changed lines only, and says nothing about the rest.\
    """)
  end

  defp render_type_guards(0), do: :ok

  defp render_type_guards(in_type_guards) do
    Mix.shell().info("""

    #{in_type_guards} mutant(s) inside type guards were never generated. Widening
    `is_binary(x)` in a guard only changes which clause matches, so the mutant either
    behaves identically or fails to compile, and no test can tell. They are left out
    of the run rather than reported as surviving.\
    """)
  end

  defp render_unused([]), do: :ok

  defp render_unused(unused) do
    Mix.shell().info("""

    #{length(unused)} accepted mutant(s) in muta.exs matched nothing in this run:

    #{Enum.map_join(unused, "\n", &"  #{&1.file}  #{&1.original} -> #{&1.mutated}")}

    Either the code moved on and the entry is stale, or this run did not cover
    that file. A stale entry will silently accept a real survivor later.\
    """)
  end

  defp render_grouped(mutants) do
    mutants
    |> Enum.group_by(&{&1.file, &1.outcome, &1.mutator, &1.original, &1.mutated})
    |> Enum.sort_by(fn {_pattern, [first | _rest]} -> {first.file, first.line} end)
    |> Enum.each(&render_pattern/1)
  end

  defp render_pattern({{file, outcome, mutator, original, mutated}, mutants}) do
    Mix.shell().info("""
      #{outcome}  #{file}:#{sites(mutants)}  #{mutator(mutator)}
        - #{first_line(original)}
        + #{first_line(mutated)}
    """)
  end

  defp sites([mutant]), do: mutant.line

  defp sites(mutants) do
    lines = mutants |> Enum.map(& &1.line) |> Enum.sort() |> Enum.join(",")

    "#{lines}  (#{length(mutants)} sites)"
  end

  defp render_breakdown([_only_one_file]), do: :ok

  defp render_breakdown(files) do
    Enum.each(files, &render_file/1)

    Mix.shell().info("")
  end

  defp render_file({file, %Report{mutants: []}}) do
    Mix.shell().info("  #{file}  no mutants, so nothing here was checked")
  end

  defp render_file({file, %Report{} = of_file}) do
    Mix.shell().info("  #{file}  #{tally(of_file)}")
  end

  defp tally(%Report{} = report) do
    "#{length(report.mutants)} mutants · #{report.killed} killed · " <>
      "#{report.survived} survived · #{report.accepted} accepted · " <>
      "#{report.unstable} unstable · #{report.invalid} invalid · #{report.score}%"
  end

  defp render_notes(%Report{} = report) do
    render_unchecked_note(unchecked(report), length(report.files))
    render_unstable_note(report.unstable)
    render_invalid_note(report.invalid)
  end

  defp unchecked(%Report{} = report) do
    report
    |> Report.by_file()
    |> Enum.count(fn {_file, of_file} -> of_file.mutants == [] end)
  end

  defp render_unchecked_note(0, _named), do: :ok

  defp render_unchecked_note(unchecked, named) do
    Mix.shell().info("""

    #{unchecked} of the #{named} files you named produced no mutants and went unchecked.
    The score above says nothing about them.\
    """)
  end

  defp render_unstable_note(0), do: :ok

  defp render_unstable_note(unstable) do
    Mix.shell().info("""

    #{unstable} unstable: a test failed on the first run and passed on the re-run, so muta
    cannot say whether the mutation was caught. Something other than the mutation
    made that test fail. Re-run, lower --workers, or fix the flaky test. Unstable
    mutants are left out of the score.\
    """)
  end

  defp render_invalid_note(0), do: :ok

  defp render_invalid_note(invalid) do
    Mix.shell().info("""

    #{invalid} invalid: the mutated code did not compile, so no test ever ran against it.
    Nothing to fix. Invalid mutants are left out of the score.\
    """)
  end

  defp mutator(module), do: module |> Module.split() |> List.last()

  defp first_line(source) do
    case String.split(source, "\n", parts: 2) do
      [whole] -> whole
      [first, _rest] -> first <> " …"
    end
  end

  defp exit_for(%Report{survived: 0, unstable: 0}), do: :ok
  defp exit_for(%Report{}), do: exit({:shutdown, 1})
end
