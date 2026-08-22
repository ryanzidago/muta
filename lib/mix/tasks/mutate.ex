defmodule Mix.Tasks.Mutate do
  use Mix.Task

  alias Muta.Config
  alias Muta.Mutant
  alias Muta.Report
  alias Muta.UntrustworthyError

  @shortdoc "Reports which mutants of the given source files survive the given tests"

  @impl Mix.Task
  def run(argv) do
    ensure_test_env!()
    Mix.Task.run("app.start")
    Application.put_env(:ex_unit, :autorun, false)

    {opts, sources} = OptionParser.parse!(argv, strict: [test: :keep, workers: :integer])
    test_files = Keyword.get_values(opts, :test)

    ensure_both_given!(sources, test_files)
    announce(sources, test_files)

    report = judge(sources, test_files, Keyword.take(opts, [:workers]))

    render(report)
    exit_for(report)
  end

  defp judge(sources, test_files, opts) do
    Muta.run(Config.new(sources, test_files, opts))
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

  defp announce(sources, test_files) do
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

  defp render(%Report{mutants: []}) do
    Mix.shell().info("No mutants generated. Nothing in these files can be mutated yet.")
  end

  defp render(%Report{} = report) do
    Enum.each(Report.survivors(report) ++ Report.unstable(report), &render_mutant/1)

    report |> Report.by_file() |> render_breakdown()

    Mix.shell().info(tally(report))

    render_notes(report)
  end

  defp render_mutant(%Mutant{} = mutant) do
    Mix.shell().info("""
      #{mutant.outcome}  #{mutant.file}:#{mutant.line}  #{mutator(mutant.mutator)}
        - #{first_line(mutant.original)}
        + #{first_line(mutant.mutated)}
    """)
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
      "#{report.survived} survived · #{report.unstable} unstable · " <>
      "#{report.invalid} invalid · #{report.score}%"
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
