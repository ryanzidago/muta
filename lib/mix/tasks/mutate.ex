defmodule Mix.Tasks.Mutate do
  use Mix.Task

  alias Muta.Config
  alias Muta.Report

  @shortdoc "Reports which mutants of the given source files survive the given tests"

  @impl Mix.Task
  def run(argv) do
    ensure_test_env!()
    Mix.Task.run("app.start")
    Application.put_env(:ex_unit, :autorun, false)
    Code.require_file("test/test_helper.exs")

    {opts, sources} = OptionParser.parse!(argv, strict: [test: :keep])
    test_files = Keyword.get_values(opts, :test)

    ensure_both_given!(sources, test_files)
    announce(sources, test_files)

    report = Muta.run(Config.new(sources, test_modules(test_files)))

    render(report)
    exit_for(report)
  end

  defp test_modules(files), do: Enum.flat_map(files, &tests_defined_in/1)

  defp tests_defined_in(file) do
    case Code.require_file(file) do
      nil -> raise_already_loaded(file)
      compiled -> compiled |> exunit_modules() |> ensure_any_tests!(file)
    end
  end

  defp exunit_modules(compiled) do
    for {module, _binary} <- compiled, function_exported?(module, :__ex_unit__, 0), do: module
  end

  defp ensure_any_tests!([], file) do
    Mix.raise("""
    #{file} defines no ExUnit tests.

    Every mutant is judged only by the tests you name. Judging them by a file with
    no tests in it would report every mutant as surviving without running anything,
    which is indistinguishable from a real result.
    """)
  end

  defp ensure_any_tests!(modules, _file), do: modules

  defp raise_already_loaded(file) do
    Mix.raise("""
    #{file} was already loaded, so muta cannot tell which test modules it defines.

    Pass each test file once, and do not pass a file that test_helper.exs already
    requires.
    """)
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
    Enum.each(Report.survivors(report), &render_survivor/1)

    Mix.shell().info(
      "#{length(report.mutants)} mutants · #{report.killed} killed · " <>
        "#{report.survived} survived · #{report.invalid} invalid · #{report.score}%"
    )
  end

  defp render_survivor(mutant) do
    Mix.shell().info("""
      #{mutant.file}:#{mutant.line}
        - #{mutant.original}
        + #{mutant.mutated}
        survived
    """)
  end

  defp exit_for(%Report{survived: 0}), do: :ok
  defp exit_for(%Report{}), do: exit({:shutdown, 1})
end
