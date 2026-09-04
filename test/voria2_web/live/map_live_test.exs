defmodule Voria2Web.MapLiveTest do
  use Voria2Web.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Voria2.MeasurementsHelpers

  setup do
    user = create_user()

    installation =
      create_installation(user,
        name: "Map Installation",
        latitude: 41.88,
        longitude: 16.05
      )

    station = create_station(installation, name: "Map Station")
    temperature = create_measurement_type(slug: "temperature", name: "Temperature")
    sensor = create_sensor_installation(station, temperature)
    record_temperature!(sensor, 21.5)

    %{installation: installation}
  end

  describe "MapLive" do
    test "renders the map root with the MaplibreMap hook", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/map")

      assert has_element?(view, "#map-root[phx-hook='MaplibreMap'][phx-update='ignore']")
      assert has_element?(view, "#map-controls")
      assert has_element?(view, "select[name='field']")
      assert has_element?(view, "option[value='temperature.current']")
    end

    test "changes the selected display field", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/map")

      view
      |> element("form[phx-change='select_field']")
      |> render_change(%{"field" => "humidity_pressure.current_humidity"})

      assert has_element?(
               view,
               "option[value='humidity_pressure.current_humidity'][selected]"
             )
    end
  end
end
