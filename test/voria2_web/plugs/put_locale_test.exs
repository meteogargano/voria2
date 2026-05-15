defmodule Voria2Web.Plugs.PutLocaleTest do
  use Voria2Web.ConnCase, async: true

  alias Voria2Web.Plugs.PutLocale
  alias Voria2Web.UserPreferences

  setup do
    locale = Gettext.get_locale(Voria2Web.Gettext)
    on_exit(fn -> Gettext.put_locale(Voria2Web.Gettext, locale) end)
  end

  test "sets gettext locale from session preferences" do
    conn =
      build_conn()
      |> init_test_session(%{
        "user_preferences" => UserPreferences.serialize(%UserPreferences{language: :it})
      })
      |> PutLocale.call([])

    assert Gettext.get_locale(Voria2Web.Gettext) == "it"
    assert conn.status == nil
  end
end
