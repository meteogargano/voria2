defmodule Voria2Web.Plugs.PutLocale do
  @moduledoc """
  Sets the Gettext locale from the user's stored session preferences.

  This plug runs at the endpoint level so custom error pages can be localized
  even when a request never reaches the browser router pipeline.
  """

  import Plug.Conn

  alias Voria2Web.UserPreferences

  def init(opts), do: opts

  def call(conn, _opts) do
    prefs =
      conn |> fetch_session() |> get_session("user_preferences") |> UserPreferences.deserialize()

    Gettext.put_locale(Voria2Web.Gettext, Atom.to_string(prefs.language))

    conn
  end
end
