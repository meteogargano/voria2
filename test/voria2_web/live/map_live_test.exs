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

  describe "radar" do
    test "renders the radar section, timeline and legend", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/map")

      assert has_element?(view, "#radar-form[phx-change='radar_update']")
      assert has_element?(view, "#radar-enable[type='checkbox']")
      assert has_element?(view, "#radar-product")
      assert has_element?(view, "option[value='VMI'][selected]")
      assert has_element?(view, "option[value='IR_108']")
      assert has_element?(view, "#radar-opacity[type='range']")
      assert has_element?(view, "#radar-timeline[phx-hook='RadarTimeline'][phx-update='ignore']")
      assert has_element?(view, "#radar-legend[phx-update='ignore'] #radar-legend-img")
    end

    test "enabling radar pushes state to the hooks", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/map")

      view
      |> element("#radar-form")
      |> render_change(%{"radar_enabled" => "true", "product" => "VMI", "opacity" => "85"})

      assert_push_event(view, "radar_state", %{
        enabled: true,
        product: "VMI",
        opacity: 0.85
      })

      assert has_element?(view, "#radar-enable:checked")
      assert has_element?(view, "#radar-product:not([disabled])")
    end

    test "changes the radar product and ignores invalid ones", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/map")

      view
      |> element("#radar-form")
      |> render_change(%{"radar_enabled" => "true", "product" => "IR_108", "opacity" => "85"})

      assert has_element?(view, "option[value='IR_108'][selected]")

      view
      |> element("#radar-form")
      |> render_change(%{"radar_enabled" => "true", "product" => "BOGUS", "opacity" => "85"})

      assert has_element?(view, "option[value='IR_108'][selected]")
      refute has_element?(view, "option[value='BOGUS']")
    end

    test "disabling radar removes the enabled controls state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/map")

      view
      |> element("#radar-form")
      |> render_change(%{"radar_enabled" => "true", "product" => "VMI", "opacity" => "85"})

      view
      |> element("#radar-form")
      |> render_change(%{"radar_enabled" => "false", "product" => "VMI", "opacity" => "85"})

      assert_push_event(view, "radar_state", %{
        enabled: false,
        product: "VMI",
        opacity: 0.85
      })

      assert has_element?(view, "#radar-product[disabled]")
    end

    test "timeline time selection updates server state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/map")

      view
      |> element("#radar-timeline")
      |> render_hook("radar_time_changed", %{"time" => 1_788_543_600_000, "live" => false})

      assert has_element?(view, "#radar-timeline[data-time='1788543600000'][data-live='false']")

      view
      |> element("#radar-timeline")
      |> render_hook("radar_go_live", %{})

      assert has_element?(view, "#radar-timeline[data-live='true']")
      refute has_element?(view, "#radar-timeline[data-time]")
    end
  end
end
