defmodule Mix.Tasks.Mutate do
  use Mix.Task

  alias Muta.Config
  alias Muta.Coverage
  alias Muta.Coverage.Cache
  alias Muta.Report

  @shortdoc "Reports which mutants of your staged code survive the tests"

  @cache_path ".muta/coverage.bin"

  @impl Mix.Task
  def run(args) do
    ensure_test_env!()
    Mix.Task.run("app.start")
    Application.put_env(:ex_unit, :autorun, false)
    Code.require_file("test/test_helper.exs")

    files = source_files(args)
    announce(files)

    report = mutate(files)

    render(report)
    exit_for(report)
  end

  defp mutate([]), do: Report.from_mutants([])

  defp mutate(files) do
    target_modules = Config.target_modules(Config.new(files, []))
    fingerprint = Cache.fingerprint(test_files(), target_modules)

    {coverage, test_modules, files_by_module} = coverage(fingerprint, files, target_modules)
    loader = fn module -> load_test_module(module, files_by_module) end
    config = Config.new(files, test_modules, load_test_module: loader)

    coverage = learn_unknown(coverage, config, test_modules, fingerprint, files_by_module)

    Muta.run(config, coverage)
  end

  defp coverage(fingerprint, files, target_modules) do
    case Cache.fetch(@cache_path, fingerprint) do
      {:ok, {coverage, files_by_module}} ->
        {coverage, Coverage.test_modules_reaching(coverage, target_modules), files_by_module}

      :stale ->
        rebuild(fingerprint, files)
    end
  end

  # A function written since the map was built is in no entry at all, and the
  # safe reading of that is "every test that reaches this module might reach
  # it". Running the reaching tests once settles the question instead: whatever
  # they never call has no test to kill its mutants, which is the answer that
  # matters most for code you just wrote.
  defp learn_unknown(coverage, config, test_modules, fingerprint, files) do
    case Muta.unknown_functions(config, coverage) do
      [] ->
        coverage

      unknown ->
        Enum.each(test_modules, &config.load_test_module.(&1))
        learned = Coverage.settle(coverage, unknown, test_modules)
        Cache.store(@cache_path, fingerprint, {learned, files})

        learned
    end
  end

  defp load_test_module(module, files_by_module) do
    if Code.ensure_loaded?(module) do
      :ok
    else
      files_by_module |> Map.fetch!(module) |> Code.require_file()
    end
  end

  defp rebuild(fingerprint, files) do
    Mix.shell().info("Mapping which tests reach your code. Later runs reuse this.\n")

    files_by_module = require_every_test_file()
    test_modules = Map.keys(files_by_module)
    coverage = Muta.coverage(Config.new(files, test_modules))

    Cache.store(@cache_path, fingerprint, {coverage, files_by_module})

    {coverage, test_modules, files_by_module}
  end

  defp require_every_test_file do
    for file <- test_files(),
        {module, _binary} <- List.wrap(Code.require_file(file)),
        function_exported?(module, :__ex_unit__, 0),
        into: %{},
        do: {module, file}
  end

  defp test_files, do: Path.wildcard("test/**/*_test.exs")

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

  defp source_files([]), do: staged_files()
  defp source_files(paths), do: paths

  defp staged_files do
    {output, 0} = System.cmd("git", ["diff", "--cached", "--name-only", "--diff-filter=ACMR"])

    output
    |> String.split("\n", trim: true)
    |> Enum.filter(&(String.ends_with?(&1, ".ex") and File.exists?(&1)))
  end

  defp announce([]), do: Mix.shell().info("Nothing staged to mutate.")
  defp announce(files), do: Mix.shell().info("Mutating #{Enum.join(files, ", ")}\n")

  defp render(%Report{mutants: []}), do: :ok

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
