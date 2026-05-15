defmodule Voria2Web.Live.Hooks.PreferencesHook do
  @moduledoc """
  LiveView on_mount hook that copies user preferences from the session into
  socket assigns as `:user_preferences`.

  Add to live sessions in the router:

      ash_authentication_live_session :my_session,
        on_mount: [{Voria2Web.Live.Hooks.PreferencesHook, :default}] do
        ...
      end
  """

  import Phoenix.Component
  import Phoenix.LiveView
  alias Voria2Web.UserPreferences

  def on_mount(:default, _params, session, socket) do
    prefs = UserPreferences.from_session(session)
    Gettext.put_locale(Voria2Web.Gettext, Atom.to_string(prefs.language))

    socket =
      socket
      |> assign(:user_preferences, prefs)
      |> assign(:current_path, nil)
      |> attach_hook(:public_nav_path, :handle_params, &capture_current_path/3)

    {:cont, socket}
  end

  defp capture_current_path(_params, uri, socket) do
    path = uri |> URI.parse() |> Map.get(:path)
    {:cont, assign(socket, :current_path, path)}
  end
end
