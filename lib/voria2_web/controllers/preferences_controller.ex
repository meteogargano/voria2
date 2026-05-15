defmodule Voria2Web.PreferencesController do
  use Voria2Web, :controller

  alias Voria2.Measurements.Units
  alias Voria2Web.UserPreferences

  def index(conn, _params) do
    render(conn, :index,
      preferences: conn.assigns.user_preferences,
      units: Units,
      page_title: gettext("Preferences")
    )
  end

  def save(conn, %{"preferences" => params}) do
    prefs = UserPreferences.from_params(params)

    conn
    |> put_session("user_preferences", UserPreferences.serialize(prefs))
    |> redirect(to: ~p"/map")
  end
end
