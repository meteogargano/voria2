defmodule Voria2Web.Plugs.LoadPreferences do
  @moduledoc """
  Reads user preferences from the session and assigns them to `conn.assigns`.

  Locale selection itself happens earlier at the endpoint level so it also applies
  to custom error pages.
  """

  import Plug.Conn
  alias Voria2Web.UserPreferences

  def init(opts), do: opts

  def call(conn, _opts) do
    prefs = conn |> get_session("user_preferences") |> UserPreferences.deserialize()
    assign(conn, :user_preferences, prefs)
  end
end
