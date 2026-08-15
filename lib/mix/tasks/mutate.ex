defmodule Mix.Tasks.Mutate do
  use Mix.Task

  alias Muta.Config
  alias Muta.Coverage
  alias Muta.Coverage.Cache
  alias Muta.Report
  alias Muta.Target

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

    targets = Enum.map(files, &%Target{file: &1})
    report = mutate(targets)

    render(report)
    exit_for(report)
  end

  defp mutate([]), do: Report.from_mutants([])

  defp mutate(targets) do
    target_modules = Muta.modules_under_test(Config.new(targets, []))
    fingerprint = Cache.fingerprint(test_files(), target_modules)

    {coverage, test_modules} = coverage(fingerprint, targets, target_modules)

    Muta.run(Config.new(targets, test_modules), coverage)
  end

  defp coverage(fingerprint, targets, target_modules) do
    case Cache.fetch(@cache_path, fingerprint) do
      {:ok, {coverage, files_by_module}} ->
        reuse(coverage, files_by_module, target_modules)

      :stale ->
        rebuild(fingerprint, targets)
    end
  end

  defp reuse(coverage, files_by_module, target_modules) do
    test_modules = Coverage.test_modules_reaching(coverage, target_modules)

    test_modules
    |> Enum.map(&Map.fetch!(files_by_module, &1))
    |> Enum.uniq()
    |> Enum.each(&Code.require_file/1)

    {coverage, test_modules}
  end

  defp rebuild(fingerprint, targets) do
    Mix.shell().info("Mapping which tests reach your code. Later runs reuse this.\n")

    files_by_module = require_every_test_file()
    test_modules = Map.keys(files_by_module)
    coverage = Muta.coverage(Config.new(targets, test_modules))

    Cache.store(@cache_path, fingerprint, {coverage, files_by_module})

    {coverage, test_modules}
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
