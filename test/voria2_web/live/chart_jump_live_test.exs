defmodule Voria2Web.ChartJumpLiveTest do
  use Voria2Web.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Voria2.MeasurementsHelpers

  setup do
    user = create_user()

    installation =
      create_installation(user, name: "Jump Installation")
      |> Ash.Changeset.for_update(:update, %{city: "Bergamo", country: "Italy"})
      |> Ash.update!(authorize?: false)

    station = create_station(installation, name: "Jump Station")
    temperature = create_measurement_type(slug: "temperature", name: "Temperature")
    sensor = create_sensor_installation(station, temperature)

    morning = ~U[2026-04-22 09:00:00Z]
    late_morning = ~U[2026-04-22 11:30:00Z]
    noonish = ~U[2026-04-22 12:15:00Z]

    record_temperature!(sensor, 12.5, morning)
    record_temperature!(sensor, 13.0, late_morning)
    record_temperature!(sensor, 13.8, noonish)

    other_installation =
      create_installation(user, name: "Compare Peer Installation")
      |> Ash.Changeset.for_update(:update, %{city: "Lecco", country: "Italy"})
      |> Ash.update!(authorize?: false)

    other_station = create_station(other_installation, name: "Compare Peer Station")
    other_sensor = create_sensor_installation(other_station, temperature)
    record_temperature!(other_sensor, 10.0, morning)
    record_temperature!(other_sensor, 11.2, late_morning)

    %{installation: installation, station: station, other_station: other_station}
  end

  describe "InstallationLive chart jump" do
    test "renders the chart jump controls", %{conn: conn, installation: installation} do
      {:ok, view, _html} = live(conn, ~p"/installations/#{installation.id}")

      assert has_element?(view, "#installation-chart-jump-form")
      assert has_element?(view, "#installation-chart-jump-input")
      assert has_element?(view, "#installation-chart-jump-submit")
    end

    test "jumps to a datetime and keeps the input synced when range changes", %{
      conn: conn,
      installation: installation
    } do
      {:ok, view, _html} = live(conn, ~p"/installations/#{installation.id}")

      view
      |> element("#installation-chart-jump-form")
      |> render_submit(%{
        "jump" => %{
          "input" => "22/04/2026 09:00",
          "utc_iso" => "2026-04-22T09:00:00Z"
        }
      })

      assert has_element?(view, "#installation-chart-jump-input[value='22/04/2026 09:00']")

      assert has_element?(
               view,
               "#ts-chart-from[data-ts='#{DateTime.to_unix(~U[2026-04-22 09:00:00Z], :millisecond)}']"
             )

      assert has_element?(
               view,
               "#ts-chart-to[data-ts='#{DateTime.to_unix(~U[2026-04-22 12:00:00Z], :millisecond)}']"
             )

      refute has_element?(view, "#installation-chart-jump-error")

      view
      |> element("button[phx-click='set_chart_range'][phx-value-range='h6']")
      |> render_click()

      assert has_element?(view, "#installation-chart-jump-input[value='22/04/2026 09:00']")

      assert has_element?(
               view,
               "#ts-chart-from[data-ts='#{DateTime.to_unix(~U[2026-04-22 09:00:00Z], :millisecond)}']"
             )

      assert has_element?(
               view,
               "#ts-chart-to[data-ts='#{DateTime.to_unix(~U[2026-04-22 15:00:00Z], :millisecond)}']"
             )
    end

    test "shows an error for invalid datetime input", %{conn: conn, installation: installation} do
      {:ok, view, _html} = live(conn, ~p"/installations/#{installation.id}")

      view
      |> element("#installation-chart-jump-form")
      |> render_submit(%{
        "jump" => %{
          "input" => "bad input",
          "utc_iso" => ""
        }
      })

      assert has_element?(view, "#installation-chart-jump-error")
      assert has_element?(view, "#installation-chart-jump-input[value='bad input']")
    end
  end

  describe "CompareLive chart jump" do
    test "renders the chart jump controls", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/compare")

      assert has_element?(view, "#compare-chart-jump-form")
      assert has_element?(view, "#compare-chart-jump-input")
      assert has_element?(view, "#compare-chart-jump-submit")
    end

    test "jumps to a datetime and clamps future values", %{conn: conn, station: station} do
      {:ok, view, _html} = live(conn, ~p"/compare")

      view
      |> element("input[phx-click='toggle_station'][phx-value-id='#{station.id}']")
      |> render_click()

      view
      |> element("#compare-chart-jump-form")
      |> render_submit(%{
        "jump" => %{
          "input" => "22/04/2026 11:30",
          "utc_iso" => "2026-04-22T11:30:00Z"
        }
      })

      assert has_element?(view, "#compare-chart-jump-input[value='22/04/2026 11:30']")

      assert has_element?(
               view,
               "#ts-chart-from[data-ts='#{DateTime.to_unix(~U[2026-04-22 11:30:00Z], :millisecond)}']"
             )

      assert has_element?(
               view,
               "#ts-chart-to[data-ts='#{DateTime.to_unix(~U[2026-04-22 14:30:00Z], :millisecond)}']"
             )

      refute has_element?(view, "#compare-chart-jump-error")

      future = DateTime.add(DateTime.utc_now(), 7_200, :second)

      view
      |> element("#compare-chart-jump-form")
      |> render_submit(%{
        "jump" => %{
          "input" => Calendar.strftime(future, "%d/%m/%Y %H:%M"),
          "utc_iso" => DateTime.to_iso8601(future)
        }
      })

      html = render(view)
      refute html =~ "compare-chart-jump-error"
      refute html =~ ~s(data-ts="#{DateTime.to_unix(future, :millisecond)}")
    end

    test "shows an error for invalid datetime input", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/compare")

      view
      |> element("#compare-chart-jump-form")
      |> render_submit(%{
        "jump" => %{
          "input" => "bad input",
          "utc_iso" => ""
        }
      })

      assert has_element?(view, "#compare-chart-jump-error")
      assert has_element?(view, "#compare-chart-jump-input[value='bad input']")
    end
  end
end
