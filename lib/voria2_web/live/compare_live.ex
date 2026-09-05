defmodule Voria2Web.CompareLive do
  use Voria2Web, :live_view

  import Voria2Web.FlatpickrInputComponent

  require Ash.Query
  alias Voria2.Measurements.Units

  on_mount {Voria2Web.LiveUserAuth, :live_user_optional}

  @default_range :h3

  # ─── Mount ──────────────────────────────────────────────────────────────────────

  def mount(_params, _session, socket) do
    stations = list_active_stations_with_sensors()
    measurement_types = list_available_measurement_types()

    now = DateTime.utc_now()
    range = @default_range
    {from, to, live?} = latest_chart_window(range, now)

    user_prefs =
      Map.get(socket.assigns, :user_preferences, %{
        temperature_unit: :celsius,
        pressure_unit: :hpa,
        wind_unit: :ms,
        rain_unit: :mm
      })

    socket =
      socket
      |> assign(:page_title, gettext("Compare Stations"))
      |> assign(:stations, stations)
      |> assign(:measurement_types, measurement_types)
      |> assign(:user_preferences, user_prefs)
      |> assign(:selected_station_ids, MapSet.new())
      |> assign(:selected_measurement_type, "temperature")
      |> assign(:chart_range, range)
      |> assign(:chart_from, from)
      |> assign(:chart_to, to)
      |> assign(:chart_live?, live?)
      |> assign(:chart_window_label, chart_window_label(from, to, live?, range))
      |> assign(:chart_jump_form, Voria2Web.ChartJump.sync_form_from_datetime(from))
      |> assign(:chart_jump_error, nil)
      |> assign(:chart_loading, false)
      |> assign(:chart_data, [])

    socket =
      if connected?(socket) do
        subscribe_to_selected_stations(socket)
      else
        socket
      end

    {:ok, socket}
  end

  # ─── Render ─────────────────────────────────────────────────────────────────────

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100">
      <div class="public-subnav sticky z-20 border-b border-base-300 bg-base-100/95 py-3 backdrop-blur">
        <div class="mx-auto flex max-w-7xl items-center gap-3 px-4 sm:px-6 lg:px-8">
          <.link
            navigate={~p"/map"}
            class="btn btn-ghost btn-sm btn-circle"
            title={gettext("Back to map")}
          >
            <.icon name="hero-arrow-left" class="size-[18px]" />
          </.link>
          <div class="flex-1 min-w-0">
            <h1 class="text-lg font-bold leading-tight">{gettext("Compare Stations")}</h1>
          </div>
        </div>
      </div>

      <div class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
        <%!-- Station selector --%>
        <div class="card bg-base-200 border border-base-300 mb-6">
          <div class="card-body p-4 gap-3">
            <h3 class="font-semibold text-sm uppercase tracking-wider text-base-content/50">
              {gettext("Stations")}
              <span class="ml-2 badge badge-sm badge-neutral">
                {MapSet.size(@selected_station_ids)} {gettext("selected")}
              </span>
            </h3>

            <div class="max-h-64 overflow-y-auto space-y-2">
              <%= for station <- @stations do %>
                <.station_checkbox
                  station={station}
                  selected={MapSet.member?(@selected_station_ids, station.id)}
                />
              <% end %>

              <div
                :if={@stations == []}
                class="text-center py-4 text-base-content/40 text-sm"
              >
                {gettext("No stations available.")}
              </div>
            </div>
          </div>
        </div>

        <%!-- Chart section --%>
        <div class="card bg-base-200 border border-base-300">
          <div class="card-body p-4 gap-3">
            <%!-- Measurement type selector --%>
            <div class="flex flex-wrap gap-1 border-b border-base-300 pb-3">
              <button
                :for={mt <- @measurement_types}
                phx-click="set_measurement_type"
                phx-value-type={mt.slug}
                class={[
                  "btn btn-xs",
                  @selected_measurement_type == mt.slug && "btn-primary",
                  @selected_measurement_type != mt.slug && "btn-ghost"
                ]}
              >
                {mt.label}
              </button>
            </div>

            <%!-- Chart range controls --%>
            <div class="flex flex-wrap items-center gap-2">
              <.form
                for={@chart_jump_form}
                id="compare-chart-jump-form"
                phx-submit="jump_to_datetime"
                class="flex w-full items-center gap-1 sm:w-auto sm:flex-none"
              >
                <.datetime_picker
                  id="compare-chart-jump-input"
                  field_name="jump[utc_iso]"
                  display_name="jump[input]"
                  value={@chart_jump_form[:utc_iso].value}
                  display_value={@chart_jump_form[:input].value}
                  submit_mode={:utc_iso}
                  placeholder="dd/mm/yyyy hh:mm"
                  minute_increment={1}
                  force_custom_mobile={true}
                  class="flex-1 sm:w-56"
                />
                <button
                  type="submit"
                  id="compare-chart-jump-submit"
                  class="btn btn-sm btn-primary btn-square shrink-0"
                  aria-label={gettext("Jump to datetime")}
                  title={gettext("Jump to datetime")}
                >
                  <.icon name="hero-magnifying-glass" class="size-4" />
                </button>
              </.form>
              <div class="flex gap-1 flex-wrap">
                <button
                  :for={range <- [:h1, :h3, :h6, :h12, :h24, :h48, :d7]}
                  phx-click="set_chart_range"
                  phx-value-range={range}
                  class={[
                    "btn btn-xs",
                    @chart_range == range && "btn-primary",
                    @chart_range != range && "btn-ghost"
                  ]}
                >
                  {range_label(range)}
                </button>
              </div>
              <div class="flex gap-1 ml-auto">
                <button
                  phx-click="chart_nav"
                  phx-value-dir="prev"
                  class="btn btn-ghost btn-xs"
                  title={gettext("Go %{range} earlier", range: range_label(@chart_range))}
                >
                  ← {gettext("Prev")}
                </button>
                <button
                  phx-click="chart_nav"
                  phx-value-dir="next"
                  class="btn btn-ghost btn-xs"
                  disabled={@chart_live?}
                  title={gettext("Go %{range} later", range: range_label(@chart_range))}
                >
                  {gettext("Next")} →
                </button>
                <button
                  phx-click="chart_nav"
                  phx-value-dir="now"
                  class={["btn btn-xs", @chart_live? && "btn-success", !@chart_live? && "btn-ghost"]}
                  title={gettext("Jump to latest data")}
                >
                  {if @chart_live?, do: "● #{gettext("Live")}", else: gettext("Live")}
                </button>
              </div>
            </div>

            <p :if={@chart_jump_error} id="compare-chart-jump-error" class="text-sm text-error">
              {@chart_jump_error}
            </p>

            <%!-- Chart content --%>
            <div class="relative">
              <div :if={@chart_loading} class="chart-loading-overlay">
                <span class="loading loading-spinner loading-sm"></span>
              </div>

              <.chart_panel show={MapSet.size(@selected_station_ids) > 0} />

              <.empty_chart_message
                :if={@chart_data == []}
                selected_count={MapSet.size(@selected_station_ids)}
              />
            </div>

            <%!-- Window label --%>
            <div class="text-xs text-base-content/40 italic">
              <%= if @chart_live? do %>
                {@chart_window_label}
              <% else %>
                <span
                  id="ts-chart-from"
                  phx-hook="LocalTime"
                  data-ts={DateTime.to_unix(@chart_from, :millisecond)}
                >
                  —
                </span>
                {" – "}
                <span
                  id="ts-chart-to"
                  phx-hook="LocalTime"
                  data-ts={DateTime.to_unix(@chart_to, :millisecond)}
                >
                  —
                </span>
              <% end %>
            </div>

            <%!-- Legend --%>
            <div :if={@chart_data != []} class="flex flex-wrap gap-2">
              <.legend_item :for={series <- @chart_data} series={series} />
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp station_checkbox(assigns) do
    ~H"""
    <label class="flex items-center gap-2 p-2 rounded hover:bg-base-300 cursor-pointer transition-colors">
      <input
        type="checkbox"
        class="checkbox checkbox-sm"
        checked={@selected}
        phx-click="toggle_station"
        phx-value-id={@station.id}
      />
      <div class="flex-1 min-w-0">
        <div class="font-medium text-sm">{@station.name}</div>
        <div class="text-xs text-base-content/50 truncate">
          {@station.installation.city}, {@station.installation.country}
        </div>
      </div>
    </label>
    """
  end

  defp legend_item(assigns) do
    ~H"""
    <div class="flex items-center gap-2 text-xs">
      <div
        class="w-3 h-3 rounded-full"
        style={"background-color: #{@series.color}"}
      >
      </div>
      <span class="font-medium">{@series.name}</span>
    </div>
    """
  end

  defp chart_panel(assigns) do
    ~H"""
    <div class="chart-container" style={if @show, do: "", else: "display: none;"}>
      <div
        id="chart-compare"
        phx-hook="MultiLineChart"
        phx-update="ignore"
        class="chart-inner"
      >
      </div>
    </div>
    """
  end

  defp empty_chart_message(assigns) do
    ~H"""
    <div class="text-center py-16 text-base-content/40">
      <p class="text-lg">
        <%= if @selected_count == 0 do %>
          {gettext("Select stations to compare their measurements.")}
        <% else %>
          {gettext("No data available for the selected measurement type and time range.")}
        <% end %>
      </p>
    </div>
    """
  end

  # ─── Events ───────────────────────────────────────────────────────────────────────

  def handle_event("toggle_station", %{"id" => id_str}, socket) do
    selected = socket.assigns.selected_station_ids

    new_selected =
      if MapSet.member?(selected, id_str),
        do: MapSet.delete(selected, id_str),
        else: MapSet.put(selected, id_str)

    socket = socket |> assign(:selected_station_ids, new_selected) |> assign(:chart_loading, true)

    {:noreply, refresh_chart(socket) |> assign(:chart_loading, false)}
  end

  def handle_event("set_measurement_type", %{"type" => type}, socket) do
    valid_types = Enum.map(socket.assigns.measurement_types, & &1.slug)

    if type in valid_types do
      socket = socket |> assign(:selected_measurement_type, type) |> assign(:chart_loading, true)

      {:noreply, refresh_chart(socket) |> assign(:chart_loading, false)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("set_chart_range", %{"range" => range_str}, socket) do
    range = parse_range(range_str)

    {from, to, live?} =
      if socket.assigns.chart_live? do
        latest_chart_window(range, DateTime.utc_now())
      else
        resize_chart_window(socket.assigns.chart_from, range)
      end

    socket =
      socket
      |> assign(:chart_range, range)
      |> assign(:chart_from, from)
      |> assign(:chart_to, to)
      |> assign(:chart_live?, live?)
      |> assign(:chart_window_label, chart_window_label(from, to, live?, range))
      |> assign(:chart_jump_form, Voria2Web.ChartJump.sync_form_from_datetime(from))
      |> assign(:chart_jump_error, nil)
      |> assign(:chart_loading, true)

    {:noreply, push_chart_data(socket) |> assign(:chart_loading, false)}
  end

  def handle_event("jump_to_datetime", %{"jump" => params}, socket) do
    now = DateTime.utc_now()

    case Voria2Web.ChartJump.resolve_target_datetime(params, now) do
      {:ok, %{target: from, form: form}} ->
        {from, to, live?} = resize_chart_window(from, socket.assigns.chart_range, now)

        socket =
          socket
          |> assign(:chart_from, from)
          |> assign(:chart_to, to)
          |> assign(:chart_live?, live?)
          |> assign(
            :chart_window_label,
            chart_window_label(from, to, live?, socket.assigns.chart_range)
          )
          |> assign(:chart_jump_form, form)
          |> assign(:chart_jump_error, nil)
          |> assign(:chart_loading, true)

        {:noreply, push_chart_data(socket) |> assign(:chart_loading, false)}

      {:error, result} ->
        {:noreply,
         socket
         |> assign(:chart_jump_form, result.form)
         |> assign(:chart_jump_error, result.error)}
    end
  end

  def handle_event("chart_nav", %{"dir" => dir}, socket) do
    range = socket.assigns.chart_range
    secs = range_seconds(range)
    now = DateTime.utc_now()

    {from, to, live?} =
      case dir do
        "prev" ->
          from = DateTime.add(socket.assigns.chart_from, -secs, :second)
          to = DateTime.add(from, secs, :second)
          {from, to, false}

        "next" ->
          from = min_datetime(DateTime.add(socket.assigns.chart_from, secs, :second), now)
          resize_chart_window(from, range, now)

        "now" ->
          latest_chart_window(range, now)

        _ ->
          {socket.assigns.chart_from, socket.assigns.chart_to, socket.assigns.chart_live?}
      end

    socket =
      socket
      |> assign(:chart_from, from)
      |> assign(:chart_to, to)
      |> assign(:chart_live?, live?)
      |> assign(:chart_window_label, chart_window_label(from, to, live?, range))
      |> assign(:chart_jump_form, Voria2Web.ChartJump.sync_form_from_datetime(from))
      |> assign(:chart_jump_error, nil)
      |> assign(:chart_loading, true)

    {:noreply, push_chart_data(socket) |> assign(:chart_loading, false)}
  end

  # ─── PubSub handlers ──────────────────────────────────────────────────────────────

  def handle_info({:new_measurement, %{station_id: station_id}}, socket) do
    if MapSet.member?(socket.assigns.selected_station_ids, station_id) do
      Process.send_after(self(), :clear_rx_led, 600)

      {:noreply,
       socket
       |> assign(:rx_led, true)
       |> assign(:last_update_at, DateTime.utc_now())
       |> maybe_append_chart_point(station_id)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:new_measurement, _}, socket), do: {:noreply, socket}

  def handle_info(:clear_rx_led, socket), do: {:noreply, assign(socket, :rx_led, false)}

  # ─── Data loading ─────────────────────────────────────────────────────────────────

  defp list_active_stations_with_sensors do
    Voria2.Network.Station
    |> Ash.Query.filter(is_active == true)
    |> Ash.Query.load(:installation)
    |> Ash.read!(authorize?: false)
    |> Enum.map(fn station ->
      sensors =
        Voria2.Measurements.SensorInstallation
        |> Ash.Query.filter(station_id == ^station.id)
        |> Ash.Query.load(:measurement_type)
        |> Ash.read!(authorize?: false)
        |> Enum.filter(&is_nil(&1.removed_at))

      Map.merge(station, %{sensors: sensors})
    end)
  end

  defp list_available_measurement_types do
    # System types
    system_types = [
      %{slug: "temperature", label: gettext("Temperature")},
      %{slug: "humidity", label: gettext("Humidity")},
      %{slug: "pressure", label: gettext("Pressure")},
      %{slug: "wind", label: gettext("Wind")},
      %{slug: "rain", label: gettext("Rain")}
    ]

    # Active custom types
    custom_types =
      Voria2.Measurements.MeasurementType
      |> Ash.Query.filter(is_active == true)
      |> Ash.Query.filter(not is_nil(user_id))
      |> Ash.read!(authorize?: false)
      |> Enum.map(fn mt ->
        %{slug: mt.slug, label: mt.name}
      end)

    system_types ++ custom_types
  end

  defp subscribe_to_selected_stations(socket) do
    Enum.each(socket.assigns.selected_station_ids, fn station_id ->
      Phoenix.PubSub.subscribe(Voria2.PubSub, "station:#{station_id}")
    end)

    socket
  end

  defp unsubscribe_from_selected_stations(socket) do
    Enum.each(socket.assigns.selected_station_ids, fn station_id ->
      Phoenix.PubSub.unsubscribe(Voria2.PubSub, "station:#{station_id}")
    end)

    socket
  end

  defp refresh_chart(socket) do
    socket
    |> unsubscribe_from_selected_stations()
    |> subscribe_to_selected_stations()
    |> push_chart_data()
  end

  defp push_chart_data(socket) do
    station_ids = socket.assigns.selected_station_ids
    mt_slug = socket.assigns.selected_measurement_type
    from = socket.assigns.chart_from
    to = socket.assigns.chart_to

    if MapSet.size(station_ids) == 0 or is_nil(mt_slug) do
      assign(socket, :chart_data, [])
    else
      stations_with_sensors = filter_stations_by_id(socket.assigns.stations, station_ids)

      series_list =
        Enum.map(stations_with_sensors, fn station ->
          sensor = find_sensor_by_type(station.sensors, mt_slug)

          if sensor do
            data = fetch_sensor_data(sensor, mt_slug, from, to, socket.assigns.user_preferences)
            %{id: station.id, name: station.name, data: data}
          else
            nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      colors = assign_chart_colors(length(series_list))

      series_with_colors =
        Enum.zip(series_list, colors)
        |> Enum.map(fn {%{id: id, name: name, data: data}, color} ->
          %{id: id, name: name, data: data, color: color}
        end)

      unit = get_unit_for_type(mt_slug, socket.assigns.user_preferences)

      result =
        push_event(socket, "multi_line_chart_data", %{
          series: series_with_colors,
          unit: unit,
          from: unix_ms(from),
          to: unix_ms(to)
        })

      result |> assign(:chart_data, series_with_colors)
    end
  end

  defp filter_stations_by_id(stations, station_ids) do
    Enum.filter(stations, &MapSet.member?(station_ids, &1.id))
  end

  defp find_sensor_by_type(sensors, type_slug) do
    Enum.find(sensors, fn s ->
      s.measurement_type.slug == type_slug
    end)
  end

  defp fetch_sensor_data(sensor, type_slug, from, to, prefs) do
    case type_slug do
      "temperature" ->
        r = Voria2.Measurements.temperature_for_sensor!(sensor.id, from, to, authorize?: false)
        Enum.map(r, &%{t: unix_ms(&1.measured_at), v: convert_temp(&1.value, prefs)})

      "humidity" ->
        r = Voria2.Measurements.humidity_for_sensor!(sensor.id, from, to, authorize?: false)
        Enum.map(r, &%{t: unix_ms(&1.measured_at), v: r1(&1.value)})

      "pressure" ->
        r = Voria2.Measurements.pressure_for_sensor!(sensor.id, from, to, authorize?: false)
        Enum.map(r, &%{t: unix_ms(&1.measured_at), v: convert_pressure(&1.value, prefs)})

      "wind" ->
        readings = Voria2.Measurements.wind_for_sensor!(sensor.id, from, to, authorize?: false)
        wu = prefs.wind_unit

        Enum.map(readings, fn r ->
          speed = :math.sqrt(r.u * r.u + r.v * r.v)
          %{t: unix_ms(r.measured_at), v: r1(Units.convert(:wind, speed, :ms, wu))}
        end)

      "rain" ->
        readings = Voria2.Measurements.rain_for_sensor!(sensor.id, from, to, authorize?: false)
        ru = prefs.rain_unit

        Enum.map(readings, fn r ->
          %{t: unix_ms(r.measured_at), v: r1(Units.convert(:rain, r.interval_mm, :mm, ru))}
        end)

      _ ->
        r = Voria2.Measurements.custom_for_sensor!(sensor.id, from, to, authorize?: false)
        Enum.map(r, &%{t: unix_ms(&1.measured_at), v: r1(&1.value)})
    end
  end

  defp assign_chart_colors(count) when count == 0, do: []

  defp assign_chart_colors(count) do
    [
      "#6366f1",
      "#f97316",
      "#10b981",
      "#8b5cf6",
      "#ec4899",
      "#14b8a6",
      "#f59e0b",
      "#ef4444",
      "#6366f1",
      "#f97316"
    ]
    |> Enum.take(count)
  end

  defp get_unit_for_type(type_slug, prefs) do
    case type_slug do
      "temperature" -> Units.label(prefs.temperature_unit)
      "humidity" -> "%"
      "pressure" -> Units.label(prefs.pressure_unit)
      "wind" -> Units.label(prefs.wind_unit)
      "rain" -> Units.label(prefs.rain_unit)
      _ -> ""
    end
  end

  defp maybe_append_chart_point(socket, station_id) do
    if socket.assigns.chart_live? do
      mt_slug = socket.assigns.selected_measurement_type

      stations =
        filter_stations_by_id(socket.assigns.stations, socket.assigns.selected_station_ids)

      station = Enum.find(stations, &(&1.id == station_id))
      sensor = station && find_sensor_by_type(station.sensors, mt_slug)

      if sensor do
        now = DateTime.utc_now()
        now_ms = unix_ms(now)
        one_min_ago = DateTime.add(now, -60, :second)
        range_secs = range_seconds(socket.assigns.chart_range)
        slide_from_ms = now_ms - range_secs * 1000

        case mt_slug do
          "wind" ->
            readings =
              Voria2.Measurements.wind_for_sensor!(sensor.id, one_min_ago, now, authorize?: false)

            case List.last(readings) do
              nil ->
                socket

              r ->
                wu = socket.assigns.user_preferences.wind_unit
                speed = :math.sqrt(r.u * r.u + r.v * r.v)

                point = %{
                  series_id: station_id,
                  point: %{t: unix_ms(r.measured_at), v: r1(Units.convert(:wind, speed, :ms, wu))}
                }

                push_event(socket, "multi_line_chart_append", %{
                  point: point,
                  from: slide_from_ms,
                  to: now_ms
                })
            end

          "rain" ->
            readings =
              Voria2.Measurements.rain_for_sensor!(sensor.id, one_min_ago, now, authorize?: false)

            case List.last(readings) do
              nil ->
                socket

              r ->
                ru = socket.assigns.user_preferences.rain_unit

                point = %{
                  series_id: station_id,
                  point: %{
                    t: unix_ms(r.measured_at),
                    v: r1(Units.convert(:rain, r.interval_mm, :mm, ru))
                  }
                }

                push_event(socket, "multi_line_chart_append", %{
                  point: point,
                  from: slide_from_ms,
                  to: now_ms
                })
            end

          _ ->
            readings =
              case mt_slug do
                "temperature" ->
                  Voria2.Measurements.temperature_for_sensor!(sensor.id, one_min_ago, now,
                    authorize?: false
                  )

                "humidity" ->
                  Voria2.Measurements.humidity_for_sensor!(sensor.id, one_min_ago, now,
                    authorize?: false
                  )

                "pressure" ->
                  Voria2.Measurements.pressure_for_sensor!(sensor.id, one_min_ago, now,
                    authorize?: false
                  )

                _ ->
                  Voria2.Measurements.custom_for_sensor!(sensor.id, one_min_ago, now,
                    authorize?: false
                  )
              end

            case List.last(readings) do
              nil ->
                socket

              r ->
                v =
                  case mt_slug do
                    "temperature" -> convert_temp(r.value, socket.assigns.user_preferences)
                    "pressure" -> convert_pressure(r.value, socket.assigns.user_preferences)
                    _ -> r1(r.value)
                  end

                point = %{
                  series_id: station_id,
                  point: %{t: unix_ms(r.measured_at), v: v}
                }

                push_event(socket, "multi_line_chart_append", %{
                  point: point,
                  from: slide_from_ms,
                  to: now_ms
                })
            end
        end
      else
        socket
      end
    else
      socket
    end
  end

  # ─── Format helpers ───────────────────────────────────────────────────────────────

  defp convert_temp(v, prefs),
    do: r1(Units.convert(:temperature, v * 1.0, :celsius, prefs.temperature_unit))

  defp convert_pressure(v, prefs) do
    converted = Units.convert(:pressure, v * 1.0, :hpa, prefs.pressure_unit)

    if prefs.pressure_unit == :inhg,
      do: Float.round(converted, 2),
      else: Float.round(converted, 1)
  end

  defp r1(v), do: Float.round(v * 1.0, 1)

  # ─── Time helpers ─────────────────────────────────────────────────────────────

  defp chart_window_label(_from, _to, true, range),
    do: gettext("Last %{range}", range: range_label(range))

  defp chart_window_label(from, to, false, _range) do
    f = Calendar.strftime(from, "%d %b %H:%M")
    t = Calendar.strftime(to, "%d %b %H:%M")
    "#{f} – #{t} UTC"
  end

  defp chart_window(from, range) do
    secs = range_seconds(range)
    {from, DateTime.add(from, secs, :second)}
  end

  defp latest_chart_window(range, now) do
    from = DateTime.add(now, -range_seconds(range), :second)
    {from, now, true}
  end

  defp resize_chart_window(from, range, now \\ DateTime.utc_now()) do
    {from, unclamped_to} = chart_window(from, range)
    to = min_datetime(unclamped_to, now)
    live? = DateTime.compare(unclamped_to, now) != :gt and DateTime.diff(now, to, :second) < 30
    {from, to, live?}
  end

  defp range_seconds(:h1), do: 3_600
  defp range_seconds(:h3), do: 3 * 3_600
  defp range_seconds(:h6), do: 6 * 3_600
  defp range_seconds(:h12), do: 12 * 3_600
  defp range_seconds(:h24), do: 24 * 3_600
  defp range_seconds(:h48), do: 48 * 3_600
  defp range_seconds(:d7), do: 7 * 24 * 3_600

  defp range_label(:h1), do: "1h"
  defp range_label(:h3), do: "3h"
  defp range_label(:h6), do: "6h"
  defp range_label(:h12), do: "12h"
  defp range_label(:h24), do: "24h"
  defp range_label(:h48), do: "48h"
  defp range_label(:d7), do: "7d"

  defp parse_range("h1"), do: :h1
  defp parse_range("h3"), do: :h3
  defp parse_range("h6"), do: :h6
  defp parse_range("h12"), do: :h12
  defp parse_range("h24"), do: :h24
  defp parse_range("h48"), do: :h48
  defp parse_range("d7"), do: :d7
  defp parse_range(_), do: @default_range

  defp unix_ms(dt), do: DateTime.to_unix(dt, :millisecond)

  defp min_datetime(a, b) do
    if DateTime.compare(a, b) == :gt, do: b, else: a
  end
end
