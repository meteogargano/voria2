defmodule Voria2.Release do
  @moduledoc false

  @app :voria2

  def prepare do
    migrate()
    seed()
  end

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def seed do
    Application.put_env(@app, :start_background_processes?, false)

    load_app()
    {:ok, _} = Application.ensure_all_started(@app)

    Voria2.Seeds.run(require_admin_password?: false)
  end

  def rollback(repo, version) when is_binary(repo) do
    rollback(String.to_existing_atom(repo), version)
  end

  def rollback(repo, version) when is_atom(repo) do
    load_app()
    version = parse_version(version)

    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end

  defp parse_version(version) when is_integer(version), do: version
  defp parse_version(version) when is_binary(version), do: String.to_integer(version)
end
