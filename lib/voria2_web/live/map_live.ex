defmodule Voria2Web.MapLive do
  use Voria2Web, :live_view

  alias Voria2.Measurements.Units

  on_mount {Voria2Web.LiveUserAuth, :live_user_optional}

  @fault_refresh_ms 2 * 60 * 1000

  @radar_product_ids ~w(VMI SRI SRT1 CUM3 CUM6 CUM12 CUM24 TEMP IR_108)
  @radar_default_opacity 0.85
  @radar_min_opacity 0.4
  @radar_max_opacity 1.0

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
      |> assign(:radar_enabled, false)
      |> assign(:radar_product, "VMI")
      |> assign(:radar_opacity, @radar_default_opacity)
      |> assign(:radar_products, radar_product_options())
      |> assign(:radar_time, nil)
      |> assign(:radar_live, true)

    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Voria2.PubSub, "measurements")
        Process.send_after(self(), :refresh_faults, @fault_refresh_ms)
        push_event(socket, "update_markers", %{markers: markers})
      else
        socket
      end

    socket =
      if connected?(socket) do
        push_radar_state(socket)
      else
        socket
      end

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <section class="map-page">
      <div id="map-root" phx-hook="MaplibreMap" phx-update="ignore"></div>

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

        <div id="map-radar">
          <form id="radar-form" phx-change="radar_update">
            <div class="radar-enable-row">
              <input
                id="radar-enable"
                type="checkbox"
                name="radar_enabled"
                checked={@radar_enabled}
              />
              <label for="radar-enable" style="margin-bottom: 0px !important;">
                {gettext("Radar DPC")}
              </label>
            </div>

            <select id="radar-product" name="product" disabled={!@radar_enabled}>
              <option
                :for={opt <- @radar_products}
                value={opt.id}
                selected={opt.id == @radar_product}
              >
                {opt.label}
              </option>
            </select>

            <div class="flex flex-row gap-2">
              <label for="radar-opacity" style="margin-top:3px">{gettext("Opacity")}</label>
              <input
                id="radar-opacity"
                name="opacity"
                type="range"
                class="mb-0"
                min="40"
                max="100"
                step="5"
                value={round(@radar_opacity * 100)}
                disabled={!@radar_enabled}
                phx-debounce="150"
              />
            </div>

            <p class="radar-credit !mt-0">
              {gettext("Source:")}
              <a
                href="https://radar.protezionecivile.it/"
                target="_blank"
                rel="noopener"
              >
                Radar-DPC
              </a>
              · CC-BY-SA
            </p>
          </form>
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

      <div
        id="radar-timeline"
        phx-hook="RadarTimeline"
        phx-update="ignore"
        data-time={@radar_time}
        data-live={to_string(@radar_live)}
      >
      </div>

      <div id="radar-legend" phx-update="ignore">
        <img id="radar-legend-img" alt={gettext("Radar color legend")} />
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

  def handle_event("radar_update", params, socket) do
    enabled = params["radar_enabled"] not in [nil, "false"]

    product =
      if params["product"] in @radar_product_ids,
        do: params["product"],
        else: socket.assigns.radar_product

    opacity = parse_opacity(params["opacity"], socket.assigns.radar_opacity)

    {:noreply,
     socket
     |> assign(:radar_enabled, enabled)
     |> assign(:radar_product, product)
     |> assign(:radar_opacity, opacity)
     |> push_radar_state()}
  end

  def handle_event("radar_time_changed", %{"time" => time, "live" => live}, socket)
      when is_integer(time) do
    {:noreply,
     socket
     |> assign(:radar_time, time)
     |> assign(:radar_live, live == true)}
  end

  def handle_event("radar_time_changed", _params, socket), do: {:noreply, socket}

  def handle_event("radar_go_live", _params, socket) do
    {:noreply,
     socket
     |> assign(:radar_time, nil)
     |> assign(:radar_live, true)}
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

  defp radar_product_options do
    [
      %{id: "VMI", label: gettext("VMI — Max reflectivity (dBZ)")},
      %{id: "SRI", label: gettext("SRI — Rain intensity (mm/h)")},
      %{id: "SRT1", label: gettext("SRT1 — Rain 1h (mm)")},
      %{id: "CUM3", label: gettext("CUM3 — Rain 3h (mm)")},
      %{id: "CUM6", label: gettext("CUM6 — Rain 6h (mm)")},
      %{id: "CUM12", label: gettext("CUM12 — Rain 12h (mm)")},
      %{id: "CUM24", label: gettext("CUM24 — Rain 24h (mm)")},
      %{id: "TEMP", label: gettext("TEMP — Temperature (°C)")},
      %{id: "IR_108", label: gettext("IR — Cloud coverage")}
    ]
  end

  defp parse_opacity(nil, default), do: default

  defp parse_opacity(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} ->
        (n / 100) |> max(@radar_min_opacity) |> min(@radar_max_opacity)

      _ ->
        default
    end
  end

  defp parse_opacity(_, default), do: default

  defp push_radar_state(socket) do
    push_event(socket, "radar_state", %{
      enabled: socket.assigns.radar_enabled,
      product: socket.assigns.radar_product,
      opacity: socket.assigns.radar_opacity
    })
  end

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
