defmodule Muta.Fleet do
  alias Muta.Config
  alias Muta.Mutant
  alias Muta.Mutation
  alias Muta.UntrustworthyError
  alias Muta.Worker

  @spec judge([Mutation.t()], Config.t()) :: [Mutant.t()]
  def judge(mutations, %Config{} = config) do
    ensure_distributed()
    peers = Enum.map(1..config.workers, &hire(&1, System.pid()))

    try do
      peers
      |> alongside(fn {_peer, node} -> brief(node, config) end)
      |> share(mutations)
    after
      Enum.each(peers, fn {peer, _node} -> :peer.stop(peer) end)
    end
  end

  defp share(workers, mutations) do
    {:ok, queue} = Agent.start_link(fn -> mutations end)

    try do
      workers
      |> alongside(&drain(queue, &1, []))
      |> Enum.concat()
    after
      Agent.stop(queue)
    end
  end

  defp drain(queue, worker, judged) do
    case take(queue) do
      :none -> Enum.reverse(judged)
      {:next, mutation} -> drain(queue, worker, [Worker.judge(worker, mutation) | judged])
    end
  end

  defp take(queue) do
    Agent.get_and_update(queue, fn
      [] -> {:none, []}
      [next | rest] -> {{:next, next}, rest}
    end)
  end

  defp alongside(items, work) do
    items
    |> Task.async_stream(&attempt(work, &1),
      timeout: :infinity,
      max_concurrency: length(items),
      ordered: false
    )
    |> Enum.map(fn {:ok, outcome} -> outcome end)
    |> Enum.split_with(&match?({:raised, _cause}, &1))
    |> answer()
  end

  defp attempt(work, item) do
    {:ok, work.(item)}
  rescue
    exception -> {:raised, {exception, __STACKTRACE__}}
  end

  defp answer({[{:raised, {exception, stacktrace}} | _rest], _done}) do
    reraise(exception, stacktrace)
  end

  defp answer({[], done}), do: Enum.map(done, fn {:ok, result} -> result end)

  defp hire(index, run) do
    {:ok, peer, node} =
      :peer.start_link(%{
        name: :"muta_#{run}_worker_#{index}",
        host: ~c"127.0.0.1",
        longnames: true,
        args: [~c"-setcookie", Atom.to_charlist(Node.get_cookie()), ~c"-connect_all", ~c"false"]
      })

    {peer, node}
  end

  defp brief(node, %Config{} = config) do
    :erpc.call(node, :code, :add_paths, [:code.get_path()])
    :erpc.call(node, :application, :set_env, [borrowed_env(), [persistent: true]])
    :erpc.call(node, File, :cd!, [File.cwd!()])

    Enum.each(
      running_apps(),
      &:erpc.call(node, Application, :ensure_all_started, [&1], :infinity)
    )

    Worker.start(node, config)
  end

  defp borrowed_env do
    for {app, _description, _vsn} <- Application.loaded_applications() do
      {app, Application.get_all_env(app)}
    end
  end

  defp running_apps do
    for {app, _description, _vsn} <- Application.started_applications(), do: app
  end

  defp ensure_distributed do
    if Node.alive?() do
      :ok
    else
      start_distribution()
    end
  end

  defp start_distribution do
    case Node.start(:"muta_#{System.pid()}@127.0.0.1", name_domain: :longnames) do
      {:ok, _pid} ->
        Node.set_cookie(:muta)

        :ok

      {:error, reason} ->
        raise UntrustworthyError,
              "muta could not start distributed Erlang, so it has no worker VMs to judge " <>
                "mutants in: #{inspect(reason)}. Mutants are judged on separate nodes " <>
                "because the code server holds one version of a module at a time. Check that " <>
                "epmd is running and reachable on 127.0.0.1 (`epmd -daemon` starts it), and " <>
                "that nothing is blocking loopback connections."
    end
  end
end
