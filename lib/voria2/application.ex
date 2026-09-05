defmodule Voria2.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Voria2Web.Telemetry,
      Voria2.Repo,
      {DNSCluster, query: Application.get_env(:voria2, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Voria2.PubSub},
      {Task.Supervisor, name: Voria2.TaskSupervisor, max_children: 24},
      # Start to serve requests, typically the last entry
      Voria2Web.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :voria2]}
    ]

    children = List.insert_at(children, 5, background_children())
    children = List.flatten(children)

    # Initialize ETS table
    Voria2.Cache.init_table()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Voria2.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp background_children do
    if Application.get_env(:voria2, :start_background_processes?, true) do
      [
        {Voria2.CacheInvalidationListener, []},
        {Voria2.Network.WebcamShotPurger, []},
        {Voria2.Network.FaultScheduler, []}
      ]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    Voria2Web.Endpoint.config_change(changed, removed)
    :ok
  end
end
