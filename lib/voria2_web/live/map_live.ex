defmodule Voria2Web.MapLive do
  use Voria2Web, :live_view

  alias Voria2.Measurements.Units

  on_mount {Voria2Web.LiveUserAuth, :live_user_optional}

  @fault_refresh_ms 2 * 60 * 1000

  @cardinals [
    "N",
    "NNE",
    "NE",
    "ENE",
    "E",
    "ESE",
    "SE",
    "SSE",
    "S",
    "SSW",
    "SW",
    "WSW",
    "W",
    "WNW",
    "NW",
    "NNW"
  ]

  def mount(_params, _session, socket) do
    {:ok, map_data} = Voria2.Network.list_public_map_data()
    prefs = socket.assigns.user_preferences
    selected = "temperature.current"
    opts = summary_options(prefs)
    markers = build_markers(map_data, selected, prefs)

    socket =
      socket
      |> assign(:page_title, gettext("Rete Meteo"))
      |> assign(:map_data, map_data)
      |> assign(:selected_field, selected)
      |> assign(:summary_options, opts)
      |> assign(:markers, markers)
      |> assign(:rx_led, false)
      |> assign(:last_update_at, nil)

    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Voria2.PubSub, "measurements")
        Process.send_after(self(), :refresh_faults, @fault_refresh_ms)
        push_event(socket, "update_markers", %{markers: markers})
      else
        socket
      end

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <section class="map-page">
      <div id="map-root" phx-hook="LeafletMap" phx-update="ignore"></div>

      <div id="map-controls">
        <div class="map-controls-header">
          <div>
            <p class="map-eyebrow">{gettext("Live map")}</p>
            <label style="margin-bottom: 0px !important;">{gettext("Display")}</label>
          </div>
          <div class={["rx-led", @rx_led && "rx-led--active"]}></div>
        </div>

        <form phx-change="select_field">
          <select name="field">
            <option
              :for={opt <- @summary_options}
              value={opt.value}
              selected={opt.value == @selected_field}
            >
              {opt.label}
            </option>
          </select>
        </form>

        <div class="map-links">
          <a href={~p"/preferences"} id="map-prefs-link">
            <.icon name="hero-cog-6-tooth" class="size-[11px]" />
            {gettext("Preferences")}
          </a>
          <a href={~p"/compare"} id="map-compare-link">
            <.icon name="hero-chart-bar" class="size-[11px]" />
            {gettext("Compare")}
          </a>
          <a href={~p"/webcams"} id="map-webcams-link">
            <.icon name="hero-video-camera" class="size-[11px]" />
            {gettext("All Webcams")}
          </a>
        </div>

        <div id="map-last-update">
          <span class="font-medium">{gettext("Upd. at:")}</span>
          <span :if={@last_update_at}>
            <span
              id="map-last-update-ts"
              phx-hook="LocalTime"
              data-ts={DateTime.to_unix(@last_update_at, :millisecond)}
            >
              —
            </span>
          </span>
          <span :if={is_nil(@last_update_at)}>{gettext("Waiting…")}</span>
        </div>
      </div>
    </section>
    """
  end

  def handle_event("select_field", %{"field" => field}, socket) do
    prefs = socket.assigns.user_preferences
    valid_values = Enum.map(summary_options(prefs), & &1.value)

    field =
      if field in valid_values,
        do: field,
        else: socket.assigns.selected_field

    markers = build_markers(socket.assigns.map_data, field, prefs)

    {:noreply,
     socket
     |> assign(:selected_field, field)
     |> assign(:markers, markers)
     |> push_event("update_markers", %{markers: markers})}
  end

  def handle_info({:new_measurement, %{station_id: _sid, summary_type: st}}, socket)
      when not is_nil(st) do
    if st == field_to_summary_type(socket.assigns.selected_field) do
      prefs = socket.assigns.user_preferences
      markers = build_markers(socket.assigns.map_data, socket.assigns.selected_field, prefs)
      Process.send_after(self(), :clear_rx_led, 600)

      {:noreply,
       socket
       |> assign(:rx_led, true)
       |> assign(:last_update_at, DateTime.utc_now())
       |> assign(:markers, markers)
       |> push_event("update_markers", %{markers: markers})}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:new_measurement, _}, socket), do: {:noreply, socket}

  def handle_info(:clear_rx_led, socket), do: {:noreply, assign(socket, :rx_led, false)}

  def handle_info(:refresh_faults, socket) do
    {:ok, map_data} = Voria2.Network.list_public_map_data()
    prefs = socket.assigns.user_preferences
    markers = build_markers(map_data, socket.assigns.selected_field, prefs)
    Process.send_after(self(), :refresh_faults, @fault_refresh_ms)

    {:noreply,
     socket
     |> assign(:map_data, map_data)
     |> assign(:markers, markers)
     |> push_event("update_markers", %{markers: markers})}
  end

  # -- Private helpers -------------------------------------------------------

  defp build_markers(map_data, selected_field, prefs) do
    Enum.map(map_data, fn entry ->
      {value, value_at} =
        case entry.first_station do
          nil ->
            {"—", nil}

          station ->
            {get_summary_value(station.id, selected_field, prefs),
             get_summary_at(station.id, selected_field)}
        end

      %{
        id: entry.installation.id,
        lat: entry.installation.latitude,
        lng: entry.installation.longitude,
        name: entry.installation.name,
        value: value,
        value_at: value_at,
        has_webcam: entry.has_webcam,
        has_fault: entry.has_fault
      }
    end)
  end

  defp get_summary_value(station_id, field_key, prefs) do
    [type_str, field_str] = String.split(field_key, ".", parts: 2)
    summary_type = String.to_existing_atom(type_str)
    field_atom = String.to_existing_atom(field_str)

    case Voria2.Cache.get_or_compute_summary(station_id, summary_type) do
      {:ok, nil} -> "—"
      {:ok, summary} -> format_value(Map.get(summary, field_atom), field_key, prefs)
    end
  end

  defp format_value(nil, _, _prefs), do: "—"

  defp format_value(v, "temperature.current", prefs) do
    u = prefs.temperature_unit
    "#{r1(Units.convert(:temperature, v * 1.0, :celsius, u))} #{Units.label(u)}"
  end

  defp format_value(v, "temperature.diff_24h", prefs) do
    u = prefs.temperature_unit
    converted = r1(Units.convert_delta(:temperature, v * 1.0, :celsius, u))
    "#{if converted >= 0, do: "+", else: ""}#{converted} #{Units.label(u)}"
  end

  defp format_value(%{value: v}, "temperature.min_today", prefs) do
    u = prefs.temperature_unit
    "#{r1(Units.convert(:temperature, v * 1.0, :celsius, u))} #{Units.label(u)}"
  end

  defp format_value(%{value: v}, "temperature.max_today", prefs) do
    u = prefs.temperature_unit
    "#{r1(Units.convert(:temperature, v * 1.0, :celsius, u))} #{Units.label(u)}"
  end

  defp format_value(v, "humidity_pressure.current_humidity", _prefs), do: "#{round(v)}%"

  defp format_value(v, "humidity_pressure.current_pressure", prefs) do
    u = prefs.pressure_unit
    converted = Units.convert(:pressure, v * 1.0, :hpa, u)

    formatted =
      if u == :inhg, do: "#{Float.round(converted, 2)}", else: "#{Float.round(converted, 1)}"

    "#{formatted} #{Units.label(u)}"
  end

  defp format_value(v, "humidity_pressure.dewpoint", prefs) do
    u = prefs.temperature_unit
    "#{r1(Units.convert(:temperature, v * 1.0, :celsius, u))} #{Units.label(u)}"
  end

  defp format_value(v, "wind.current_speed", prefs) do
    u = prefs.wind_unit
    "#{r1(Units.convert(:wind, v * 1.0, :ms, u))} #{Units.label(u)}"
  end

  defp format_value(v, "wind.current_gust", prefs) do
    u = prefs.wind_unit
    "#{r1(Units.convert(:wind, v * 1.0, :ms, u))} #{Units.label(u)}"
  end

  defp format_value(%{gust: g}, "wind.max_gust_today", prefs) do
    u = prefs.wind_unit
    "#{r1(Units.convert(:wind, g * 1.0, :ms, u))} #{Units.label(u)}"
  end

  defp format_value(v, "wind.current_direction", _prefs) do
    "#{trunc(Float.round(v * 1.0, 0))}° #{degrees_to_cardinal(v)}"
  end

  defp format_value(v, "rain.total_today", prefs) do
    u = prefs.rain_unit
    "#{r1(Units.convert(:rain, v * 1.0, :mm, u))} #{Units.label(u)}"
  end

  defp format_value(v, "rain.rain_rate", prefs) do
    u = prefs.rain_unit
    "#{r1(Units.convert(:rain, v * 1.0, :mm, u))} #{Units.label(u)}/h"
  end

  defp format_value(v, "rain.days_without_rain", _prefs) when is_integer(v) do
    ngettext("%{count} day dry", "%{count} days dry", v)
  end

  defp format_value(v, _, _prefs), do: "#{v}"

  defp r1(v), do: Float.round(v * 1.0, 1)

  @fields_with_at ["temperature.min_today", "temperature.max_today", "wind.max_gust_today"]

  defp get_summary_at(_station_id, field_key) when field_key not in @fields_with_at, do: nil

  defp get_summary_at(station_id, field_key) do
    [type_str, field_str] = String.split(field_key, ".", parts: 2)
    type = String.to_existing_atom(type_str)
    field = String.to_existing_atom(field_str)

    case Voria2.Cache.get_or_compute_summary(station_id, type) do
      {:ok, nil} ->
        nil

      {:ok, summary} ->
        case Map.get(summary, field) do
          %{at: dt} -> DateTime.to_unix(dt, :millisecond)
          _ -> nil
        end
    end
  end

  defp summary_options(prefs) do
    t = Units.label(prefs.temperature_unit)
    w = Units.label(prefs.wind_unit)
    p = Units.label(prefs.pressure_unit)
    r = Units.label(prefs.rain_unit)

    [
      %{value: "temperature.current", label: gettext("Temperature (%{unit})", unit: t)},
      %{value: "temperature.min_today", label: gettext("Temp Min (%{unit})", unit: t)},
      %{value: "temperature.max_today", label: gettext("Temp Max (%{unit})", unit: t)},
      %{value: "temperature.diff_24h", label: gettext("24h Change (%{unit})", unit: t)},
      %{value: "humidity_pressure.current_humidity", label: gettext("Humidity (%)")},
      %{
        value: "humidity_pressure.current_pressure",
        label: gettext("Pressure (%{unit})", unit: p)
      },
      %{value: "humidity_pressure.dewpoint", label: gettext("Dewpoint (%{unit})", unit: t)},
      %{value: "wind.current_speed", label: gettext("Wind Speed (%{unit})", unit: w)},
      %{value: "wind.current_direction", label: gettext("Wind Direction")},
      %{value: "wind.current_gust", label: gettext("Wind Gust (%{unit})", unit: w)},
      %{value: "wind.max_gust_today", label: gettext("Max Gust (%{unit})", unit: w)},
      %{value: "rain.total_today", label: gettext("Rain Today (%{unit})", unit: r)},
      %{value: "rain.rain_rate", label: gettext("Rain Rate (%{unit}/h)", unit: r)},
      %{value: "rain.days_without_rain", label: gettext("Dry Days")}
    ]
  end

  defp degrees_to_cardinal(deg) do
    idx = trunc(Float.floor((:math.fmod(deg, 360.0) + 360.0 + 11.25) / 22.5)) |> rem(16)
    Enum.at(@cardinals, idx)
  end

  defp field_to_summary_type(field_key) do
    field_key |> String.split(".", parts: 2) |> hd() |> String.to_existing_atom()
  end
end
