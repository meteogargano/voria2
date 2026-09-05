defmodule Voria2Web.PublicNavbarTest do
  use Voria2Web.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Voria2.MeasurementsHelpers

  setup do
    user = create_user()

    installation =
      create_installation(user,
        name: "Navbar Installation",
        latitude: 41.88,
        longitude: 16.05
      )

    station = create_station(installation, name: "Navbar Station")
    temperature = create_measurement_type(slug: "temperature", name: "Temperature")
    sensor = create_sensor_installation(station, temperature)
    record_temperature!(sensor, 21.5)

    %{installation: installation}
  end

  describe "Rete Meteo dropdown" do
    test "renders the dropdown with map, compare and webcams items", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/map")

      assert has_element?(view, "#nav-rete-meteo-dropdown [role='button']", "Rete Meteo")

      assert has_element?(
               view,
               "#nav-rete-meteo-dropdown a[href='/map'][role='menuitem']",
               "Rete Meteo"
             )

      assert has_element?(
               view,
               "#nav-rete-meteo-dropdown a[href='/compare'][role='menuitem']",
               "Confronta"
             )

      assert has_element?(
               view,
               "#nav-rete-meteo-dropdown a[href='/webcams'][role='menuitem']",
               "Tutte le Webcam"
             )
    end

    test "marks the trigger and the map item as current page on /map", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/map")

      assert has_element?(view, "#nav-rete-meteo-dropdown [role='button'].text-base-content")
      assert has_element?(view, "#nav-rete-meteo-dropdown a[href='/map'][aria-current='page']")

      refute has_element?(
               view,
               "#nav-rete-meteo-dropdown a[href='/compare'][aria-current='page']"
             )

      refute has_element?(
               view,
               "#nav-rete-meteo-dropdown a[href='/webcams'][aria-current='page']"
             )
    end

    test "keeps the trigger active and marks the item on the compare subpage", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/compare")

      assert has_element?(view, "#nav-rete-meteo-dropdown [role='button'].text-base-content")

      assert has_element?(
               view,
               "#nav-rete-meteo-dropdown a[href='/compare'][aria-current='page']"
             )
    end

    test "keeps the trigger active and marks the item on the webcams subpage", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/webcams")

      assert has_element?(view, "#nav-rete-meteo-dropdown [role='button'].text-base-content")

      assert has_element?(
               view,
               "#nav-rete-meteo-dropdown a[href='/webcams'][aria-current='page']"
             )
    end

    test "keeps the trigger active on installation pages without marking dropdown items", %{
      conn: conn,
      installation: installation
    } do
      {:ok, view, _html} = live(conn, ~p"/installations/#{installation.id}")

      assert has_element?(view, "#nav-rete-meteo-dropdown [role='button'].text-base-content")

      refute has_element?(view, "#nav-rete-meteo-dropdown [aria-current='page']")
    end
  end

  describe "preferences icon link" do
    test "renders icon only with label and is inactive on map pages", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/map")

      assert has_element?(view, "nav a[href='/preferences'][aria-label='Preferenze']")
      refute has_element?(view, "nav a[href='/preferences'][aria-current='page']")
    end

    test "GET /preferences marks the icon as current page and not the map dropdown", %{conn: conn} do
      conn = get(conn, ~p"/preferences")
      html = html_response(conn, 200)

      assert html =~ ~s(<a href="/preferences" title="Preferenze")

      assert [_before, _after] = String.split(html, ~s(aria-current="page"))
    end
  end
end
