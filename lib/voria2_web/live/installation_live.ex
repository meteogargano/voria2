defmodule Voria2Web.InstallationLive do
  use Voria2Web, :live_view

  import Voria2Web.FlatpickrInputComponent

  require Ash.Query
  alias Voria2.Measurements.Units

  on_mount {Voria2Web.LiveUserAuth, :live_user_optional}

  @cardinals ~w(N NNE NE ENE E ESE SE SSE S SSW SW WSW W WNW NW NNW)
  @system_slugs ~w(temperature humidity pressure wind rain)
  @default_range :h3

  # ─── Mount ────────────────────────────────────────────────────────────────

  def mount(%{"id" => id}, _session, socket) do
    case load_installation(id) do
      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Installation not found."))
         |> push_navigate(to: ~p"/map")}

      {:ok, data} ->
        now = DateTime.utc_now()
        range = @default_range
        {from, to, live?} = latest_chart_window(range, now)

        summaries = if data.station, do: load_all_summaries(data.station.id), else: %{}
        chart_tabs = build_chart_tabs(data.sensors)
        first_tab = chart_tabs |> List.first() |> then(fn t -> if t, do: t.slug, else: nil end)

        webcam_data = load_webcam_data(data.installation.webcams)

        {active_faults, fault_history, sensor_fault_ids} =
          load_faults(data.station, data.installation.webcams, data.sensors)

        socket =
          socket
          |> assign(:installation, data.installation)
          |> assign(:station, data.station)
          |> assign(:sensors, data.sensors)
          |> assign(:sensor_map, data.sensor_map)
          |> assign(:active_tab, :station_data)
          |> assign(:summaries, summaries)
          |> assign(:chart_tabs, chart_tabs)
          |> assign(:chart_tab, first_tab)
          |> assign(:chart_range, range)
          |> assign(:chart_from, from)
          |> assign(:chart_to, to)
          |> assign(:chart_live?, live?)
          |> assign(:chart_window_label, chart_window_label(from, to, live?, range))
          |> assign(:chart_jump_form, Voria2Web.ChartJump.sync_form_from_datetime(from))
          |> assign(:chart_jump_error, nil)
          |> assign(:chart_loading, false)
          |> assign(:webcam_data, webcam_data)
          |> assign(:active_faults, active_faults)
          |> assign(:fault_history, fault_history)
          |> assign(:sensor_fault_ids, sensor_fault_ids)
          |> assign(:show_fault_history, false)
          |> assign(:rx_led, false)
          |> assign(:last_update_at, nil)
          |> assign(:page_title, data.installation.name)

        socket =
          if connected?(socket) do
            if data.station do
              Phoenix.PubSub.subscribe(Voria2.PubSub, "station:#{data.station.id}")
            end

            Phoenix.PubSub.subscribe(Voria2.PubSub, "webcam_shots")
            push_chart_data(socket)
          else
            socket
          end

        {:ok, socket}
    end
  end

  def handle_params(params, _uri, socket) do
    tab =
      case params["tab"] do
        "webcams" -> :webcams
        "info" -> :station_info
        _ -> :station_data
      end

    {:noreply, assign(socket, :active_tab, tab)}
  end

  # ─── Render ───────────────────────────────────────────────────────────────

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100">
      <%!-- Header --%>
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
            <h1 class="text-lg font-bold leading-tight truncate">{@installation.name}</h1>
            <p
              :if={location_string(@installation) != ""}
              class="text-xs text-base-content/50 truncate"
            >
              {location_string(@installation)}
            </p>
          </div>
          <div :if={@station && @station.is_active == false} class="badge badge-warning badge-sm">
            {gettext("Inactive")}
          </div>
          <div class={["rx-led", @rx_led && "rx-led--active"]}></div>
        </div>
      </div>

      <%!-- Tab bar --%>
      <div class="border-b border-base-300 bg-base-100">
        <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <div role="tablist" class="tabs tabs-bordered">
            <.link
              navigate={~p"/installations/#{@installation.id}"}
              role="tab"
              class={["tab", @active_tab == :station_data && "tab-active"]}
            >
              {gettext("Station Data")}
            </.link>
            <.link
              navigate={~p"/installations/#{@installation.id}?tab=webcams"}
              role="tab"
              class={["tab", @active_tab == :webcams && "tab-active"]}
            >
              <span>{gettext("Webcams")}</span>
              <span :if={@webcam_data != []} class="ml-1 badge badge-xs">{length(@webcam_data)}</span>
            </.link>
            <.link
              navigate={~p"/installations/#{@installation.id}?tab=info"}
              role="tab"
              class={["tab", @active_tab == :station_info && "tab-active"]}
            >
              <span>{gettext("Installation Info")}</span>
              <span
                :if={@active_faults != []}
                class="ml-1 text-warning"
                title={gettext("Active faults")}
              >
                ⚠
              </span>
            </.link>
          </div>
        </div>
      </div>

      <%!-- Tab content --%>
      <div class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
        <div :if={@active_tab == :station_data}>
          <.station_data_tab {assigns} />
        </div>
        <div :if={@active_tab == :webcams}>
          <.webcams_tab {assigns} />
        </div>
        <div :if={@active_tab == :station_info}>
          <.station_info_tab {assigns} />
        </div>
      </div>
    </div>
    """
  end

  # ─── Station Data Tab ─────────────────────────────────────────────────────

  defp station_data_tab(assigns) do
    ~H"""
    <div :if={is_nil(@station)} class="text-center py-16 text-base-content/40">
      <p class="text-lg">{gettext("No station configured for this installation.")}</p>
    </div>

    <div :if={@station}>
      <%!-- Summary cards --%>
      <div class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4 mb-6">
        <.temperature_card
          summaries={@summaries}
          prefs={@user_preferences}
          sensor_map={@sensor_map}
          sensor_fault_ids={@sensor_fault_ids}
        />
        <.humidity_pressure_card
          summaries={@summaries}
          prefs={@user_preferences}
          sensor_map={@sensor_map}
          sensor_fault_ids={@sensor_fault_ids}
        />
        <.wind_card
          summaries={@summaries}
          prefs={@user_preferences}
          sensor_map={@sensor_map}
          sensor_fault_ids={@sensor_fault_ids}
        />
        <.rain_card
          summaries={@summaries}
          prefs={@user_preferences}
          sensor_map={@sensor_map}
          sensor_fault_ids={@sensor_fault_ids}
        />
      </div>

      <%!-- Chart controls --%>
      <div :if={@chart_tabs != []} class="card bg-base-200 border border-base-300">
        <div class="card-body p-4 gap-3">
          <%!-- Chart sub-tab row --%>
          <div class="flex flex-wrap gap-1 border-b border-base-300 pb-3">
            <button
              :for={tab <- @chart_tabs}
              phx-click="set_chart_tab"
              phx-value-tab={tab.slug}
              class={[
                "btn btn-xs",
                @chart_tab == tab.slug && "btn-primary",
                @chart_tab != tab.slug && "btn-ghost"
              ]}
            >
              {tab.label}
            </button>
          </div>

          <%!-- Row A: range pills + prev/next/live --%>
          <div class="flex flex-wrap items-center gap-2">
            <.form
              for={@chart_jump_form}
              id="installation-chart-jump-form"
              phx-submit="jump_to_datetime"
              class="flex w-full items-center gap-1 sm:w-auto sm:flex-none"
            >
              <.datetime_picker
                id="installation-chart-jump-input"
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
                id="installation-chart-jump-submit"
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
                {if @chart_live?, do: "● " <> gettext("Live"), else: gettext("Live")}
              </button>
            </div>
          </div>

          <p :if={@chart_jump_error} id="installation-chart-jump-error" class="text-sm text-error">
            {@chart_jump_error}
          </p>

          <%!-- Chart loading or content --%>
          <div class="relative">
            <div :if={@chart_loading} class="chart-loading-overlay">
              <span class="loading loading-spinner loading-sm"></span>
            </div>
            <.chart_panel
              chart_tab={@chart_tab}
              chart_tabs={@chart_tabs}
              chart_loading={@chart_loading}
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
        </div>
      </div>

      <div :if={@chart_tabs == []} class="text-center py-8 text-base-content/40">
        {gettext("No sensors configured yet.")}
      </div>

      <%!-- Live status --%>
      <div class="flex justify-end items-center gap-2 mt-2 text-xs text-base-content/40">
        <div class={["rx-led", @rx_led && "rx-led--active"]}></div>
        <span :if={@last_update_at}>
          {gettext("Last update:")}
          <span
            id="last-update-ts"
            phx-hook="LocalTime"
            data-ts={DateTime.to_unix(@last_update_at, :millisecond)}
          >
            {format_datetime(@last_update_at)}
          </span>
        </span>
        <span :if={is_nil(@last_update_at)} class="italic">{gettext("Waiting for data…")}</span>
      </div>
    </div>
    """
  end

  defp chart_panel(assigns) do
    assigns =
      assign(
        assigns,
        :active_tab_def,
        Enum.find(assigns.chart_tabs, &(&1.slug == assigns.chart_tab))
      )

    ~H"""
    <div :if={@active_tab_def} class="chart-container">
      <%= case @active_tab_def.chart_type do %>
        <% :wind -> %>
          <div id="chart-wind" phx-hook="WindChart" phx-update="ignore" class="chart-inner"></div>
        <% :rain -> %>
          <div id="chart-rain" phx-hook="RainChart" phx-update="ignore" class="chart-inner"></div>
        <% _ -> %>
          <div
            id={"chart-#{@active_tab_def.slug}"}
            phx-hook="LineChart"
            phx-update="ignore"
            class="chart-inner"
          >
          </div>
      <% end %>
    </div>
    """
  end

  # ─── Summary Cards ────────────────────────────────────────────────────────

  defp temperature_card(assigns) do
    t = assigns.summaries[:temperature]
    prefs = assigns.prefs
    u = prefs.temperature_unit
    sensor = Map.get(assigns.sensor_map, "temperature")
    has_fault = sensor && MapSet.member?(assigns.sensor_fault_ids, sensor.id)

    current = format_temp(t && t.current, u)
    trend = t && t.trend
    min_today = format_temp(t && t.min_today && t.min_today.value, u)
    max_today = format_temp(t && t.max_today && t.max_today.value, u)
    diff_24h = format_temp_delta(t && t.diff_24h, u)

    assigns =
      assign(assigns,
        current: current,
        trend: trend,
        min_today: min_today,
        max_today: max_today,
        min_today_at:
          t && t.min_today && t.min_today.at && DateTime.to_unix(t.min_today.at, :millisecond),
        max_today_at:
          t && t.max_today && t.max_today.at && DateTime.to_unix(t.max_today.at, :millisecond),
        diff_24h: diff_24h,
        unit_label: Units.label(u),
        has_fault: has_fault
      )

    ~H"""
    <div class="card bg-base-200 border border-base-300">
      <div class="card-body p-4 gap-2">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-1">
            <span class="text-xs font-semibold uppercase tracking-wider text-base-content/50">
              {gettext("Temperature")}
            </span>
            <span :if={@has_fault} class="text-warning text-xs" title={gettext("Active fault")}>
              ⚠
            </span>
          </div>
          <.trend_icon trend={@trend} />
        </div>
        <div class="text-3xl font-bold tabular-nums">{@current}</div>
        <div class="grid grid-cols-2 gap-x-4 gap-y-1 text-xs text-base-content/60">
          <span>
            {gettext("Min:")}
            <strong class="text-info">{@min_today}</strong>
            <span
              id="ts-min-temp"
              phx-hook="LocalTime"
              data-ts={@min_today_at || ""}
              data-format="time"
              class="text-base-content/40"
            >
              —
            </span>
          </span>
          <span>
            {gettext("Max:")}
            <strong class="text-error">{@max_today}</strong>
            <span
              id="ts-max-temp"
              phx-hook="LocalTime"
              data-ts={@max_today_at || ""}
              data-format="time"
              class="text-base-content/40"
            >
              —
            </span>
          </span>
          <span class="col-span-2">
            {gettext("24h change:")}
            <strong class={[diff_24h_color(@diff_24h)]}>{@diff_24h}</strong>
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp humidity_pressure_card(assigns) do
    hp = assigns.summaries[:humidity_pressure]
    prefs = assigns.prefs
    pu = prefs.pressure_unit
    tu = prefs.temperature_unit
    hum_sensor = Map.get(assigns.sensor_map, "humidity")
    pres_sensor = Map.get(assigns.sensor_map, "pressure")

    has_fault =
      (hum_sensor && MapSet.member?(assigns.sensor_fault_ids, hum_sensor.id)) ||
        (pres_sensor && MapSet.member?(assigns.sensor_fault_ids, pres_sensor.id))

    assigns =
      assign(assigns,
        humidity: format_humidity(hp && hp.current_humidity),
        hum_trend: hp && hp.humidity_trend,
        min_hum: format_humidity(hp && hp.min_humidity_today && hp.min_humidity_today.value),
        max_hum: format_humidity(hp && hp.max_humidity_today && hp.max_humidity_today.value),
        min_hum_at:
          hp && hp.min_humidity_today && hp.min_humidity_today.at &&
            DateTime.to_unix(hp.min_humidity_today.at, :millisecond),
        max_hum_at:
          hp && hp.max_humidity_today && hp.max_humidity_today.at &&
            DateTime.to_unix(hp.max_humidity_today.at, :millisecond),
        pressure_val: format_pressure_value(hp && hp.current_pressure, pu),
        pres_unit: Units.label(pu),
        pres_trend: hp && hp.pressure_trend,
        min_pres_v:
          format_pressure_value(hp && hp.min_pressure_today && hp.min_pressure_today.value, pu),
        max_pres_v:
          format_pressure_value(hp && hp.max_pressure_today && hp.max_pressure_today.value, pu),
        min_pres_at:
          hp && hp.min_pressure_today && hp.min_pressure_today.at &&
            DateTime.to_unix(hp.min_pressure_today.at, :millisecond),
        max_pres_at:
          hp && hp.max_pressure_today && hp.max_pressure_today.at &&
            DateTime.to_unix(hp.max_pressure_today.at, :millisecond),
        dewpoint: format_temp(hp && hp.dewpoint, tu),
        has_fault: has_fault
      )

    ~H"""
    <div class="card bg-base-200 border border-base-300">
      <div class="card-body p-4 gap-2">
        <div class="flex items-center gap-1">
          <span class="text-xs font-semibold uppercase tracking-wider text-base-content/50">
            {gettext("Humidity / Pressure")}
          </span>
          <span :if={@has_fault} class="text-warning text-xs" title={gettext("Active fault")}>⚠</span>
        </div>
        <div class="grid grid-cols-2 gap-2">
          <div>
            <div class="flex items-center gap-1">
              <span class="text-2xl font-bold tabular-nums">{@humidity}</span>
              <.trend_icon trend={@hum_trend} />
            </div>
            <div class="text-xs text-base-content/60 space-y-0.5">
              <div>
                <span class="text-info font-medium">{@min_hum}</span>
                <span
                  id="ts-min-hum"
                  phx-hook="LocalTime"
                  data-ts={@min_hum_at || ""}
                  data-format="time"
                  class="text-base-content/40"
                >
                  —
                </span>
              </div>
              <div>
                <span class="text-error font-medium">{@max_hum}</span>
                <span
                  id="ts-max-hum"
                  phx-hook="LocalTime"
                  data-ts={@max_hum_at || ""}
                  data-format="time"
                  class="text-base-content/40"
                >
                  —
                </span>
              </div>
            </div>
          </div>
          <div>
            <div class="flex items-center gap-1">
              <span class="text-2xl font-bold tabular-nums">{@pressure_val}</span>
              <span class="text-xs text-base-content/50 font-medium self-end mb-0.5">
                {@pres_unit}
              </span>
              <.trend_icon trend={@pres_trend} />
            </div>
            <div class="text-xs text-base-content/60 space-y-0.5">
              <div>
                <span class="text-info font-medium">{@min_pres_v}</span>
                <span
                  id="ts-min-pres"
                  phx-hook="LocalTime"
                  data-ts={@min_pres_at || ""}
                  data-format="time"
                  class="text-base-content/40"
                >
                  —
                </span>
              </div>
              <div>
                <span class="text-error font-medium">{@max_pres_v}</span>
                <span
                  id="ts-max-pres"
                  phx-hook="LocalTime"
                  data-ts={@max_pres_at || ""}
                  data-format="time"
                  class="text-base-content/40"
                >
                  —
                </span>
              </div>
            </div>
          </div>
        </div>
        <div class="text-xs text-base-content/60">
          {gettext("Dewpoint:")} <strong class="text-base-content">{@dewpoint}</strong>
        </div>
      </div>
    </div>
    """
  end

  defp wind_card(assigns) do
    w = assigns.summaries[:wind]
    prefs = assigns.prefs
    wu = prefs.wind_unit
    sensor = Map.get(assigns.sensor_map, "wind")
    has_fault = sensor && MapSet.member?(assigns.sensor_fault_ids, sensor.id)

    speed = format_wind(w && w.current_speed, wu)
    gust = format_wind(w && w.current_gust, wu)
    dir = w && w.current_direction
    dir_str = if dir, do: "#{trunc(dir)}° #{degrees_to_cardinal(dir)}", else: "—"
    max_gust = format_wind(w && w.max_gust_today && w.max_gust_today.gust, wu)

    assigns =
      assign(assigns,
        speed: speed,
        gust: gust,
        dir_str: dir_str,
        max_gust: max_gust,
        max_gust_at:
          w && w.max_gust_today && w.max_gust_today.at &&
            DateTime.to_unix(w.max_gust_today.at, :millisecond),
        dir: dir,
        has_fault: has_fault
      )

    ~H"""
    <div class="card bg-base-200 border border-base-300">
      <div class="card-body p-4 gap-2">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-1">
            <span class="text-xs font-semibold uppercase tracking-wider text-base-content/50">
              {gettext("Wind")}
            </span>
            <span :if={@has_fault} class="text-warning text-xs" title={gettext("Active fault")}>
              ⚠
            </span>
          </div>
          <.compass_needle dir={@dir} />
        </div>
        <div class="text-3xl font-bold tabular-nums">{@speed}</div>
        <div class="grid grid-cols-2 gap-x-4 gap-y-1 text-xs text-base-content/60">
          <span>{gettext("Dir:")} <strong class="text-base-content">{@dir_str}</strong></span>
          <span>{gettext("Gust:")} <strong class="text-base-content">{@gust}</strong></span>
          <span class="col-span-2">
            {gettext("Max gust:")} <strong class="text-base-content">{@max_gust}</strong>
            <span
              id="ts-max-gust"
              phx-hook="LocalTime"
              data-ts={@max_gust_at || ""}
              data-format="time"
              class="text-base-content/40"
            >
              —
            </span>
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp rain_card(assigns) do
    r = assigns.summaries[:rain]
    prefs = assigns.prefs
    ru = prefs.rain_unit
    sensor = Map.get(assigns.sensor_map, "rain")
    has_fault = sensor && MapSet.member?(assigns.sensor_fault_ids, sensor.id)

    assigns =
      assign(assigns,
        total_today: format_rain(r && r.total_today, ru),
        rain_rate: format_rain_rate(r && r.rain_rate, ru),
        instant: format_rain(r && r.instant_rain, ru),
        days_dry: r && r.days_without_rain,
        has_fault: has_fault
      )

    ~H"""
    <div class="card bg-base-200 border border-base-300">
      <div class="card-body p-4 gap-2">
        <div class="flex items-center gap-1">
          <span class="text-xs font-semibold uppercase tracking-wider text-base-content/50">
            {gettext("Rain Today")}
          </span>
          <span :if={@has_fault} class="text-warning text-xs" title={gettext("Active fault")}>⚠</span>
        </div>
        <div class="text-3xl font-bold tabular-nums">{@total_today}</div>
        <div class="grid grid-cols-2 gap-x-4 gap-y-1 text-xs text-base-content/60">
          <span>{gettext("Rate:")} <strong class="text-base-content">{@rain_rate}</strong></span>
          <span>{gettext("Now:")} <strong class="text-base-content">{@instant}</strong></span>
          <span class="col-span-2">
            <strong class="text-base-content">
              {ngettext("%{count} day without rain", "%{count} days without rain", @days_dry || 0)}
            </strong>
          </span>
        </div>
      </div>
    </div>
    """
  end

  # ─── Webcams Tab ──────────────────────────────────────────────────────────

  defp webcams_tab(assigns) do
    ~H"""
    <div :if={@webcam_data == []} class="text-center py-16 text-base-content/40">
      <p class="text-lg">{gettext("No webcams configured for this installation.")}</p>
    </div>

    <div :if={@webcam_data != []} class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
      <.webcam_card :for={entry <- @webcam_data} entry={entry} />
    </div>
    """
  end

  defp webcam_card(assigns) do
    shot = assigns.entry.latest_shot
    url = shot && Voria2.Storage.public_url(shot.s3_key)
    assigns = assign(assigns, shot: shot, url: url)

    ~H"""
    <.link
      navigate={~p"/webcams/#{@entry.webcam.id}/viewer"}
      class="card bg-base-200 border border-base-300 hover:border-primary transition-colors cursor-pointer overflow-hidden"
    >
      <figure class="aspect-video bg-base-300 overflow-hidden">
        <img
          :if={@url}
          src={@url}
          alt={@entry.webcam.name}
          class="w-full h-full object-cover"
          loading="lazy"
        />
        <div
          :if={!@url}
          class="w-full h-full flex items-center justify-center text-base-content/30 text-sm"
        >
          {gettext("No image")}
        </div>
      </figure>
      <div class="card-body p-3">
        <h3 class="font-semibold text-sm leading-tight">{@entry.webcam.name}</h3>
        <p :if={@shot} class="text-xs text-base-content/50">
          <span
            id={"ts-wc-#{@entry.webcam.id}"}
            phx-hook="LocalTime"
            data-ts={DateTime.to_unix(@shot.captured_at, :millisecond)}
          >
            —
          </span>
        </p>
        <p :if={!@shot} class="text-xs text-base-content/40">{gettext("No shots yet")}</p>
      </div>
    </.link>
    """
  end

  # ─── Station Info Tab ─────────────────────────────────────────────────────

  defp station_info_tab(assigns) do
    ~H"""
    <div class="space-y-3">
      <%!-- Installation info --%>
      <div class="card bg-base-200 border border-base-300">
        <div class="card-body p-5">
          <h2 class="card-title text-base">{gettext("Installation")}</h2>
          <dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-2 text-sm">
            <.info_row label={gettext("Name")} value={@installation.name} />
            <.info_row
              :if={@installation.description}
              label={gettext("Description")}
              value={@installation.description}
            />
            <.info_row
              label={gettext("Location")}
              value={"#{@installation.latitude}, #{@installation.longitude}"}
            />
            <.info_row
              :if={@installation.altitude}
              label={gettext("Altitude")}
              value={"#{@installation.altitude} m"}
            />
            <.info_row
              :if={@installation.country}
              label={gettext("Country")}
              value={@installation.country}
            />
            <.info_row :if={@installation.city} label={gettext("City")} value={@installation.city} />
          </dl>
        </div>
      </div>

      <%!-- Photos --%>
      <div :if={@installation.picture_keys != []} class="card bg-base-200 border border-base-300">
        <div class="card-body p-5">
          <h2 class="card-title text-base">{gettext("Photos")}</h2>
          <.installation_photos_grid
            id="public-photos"
            pictures={@installation.picture_keys}
            editable={false}
          />
        </div>
      </div>

      <%!-- Station description --%>
      <div :if={@station && @station.description} class="card bg-base-200 border border-base-300">
        <div class="card-body p-5">
          <h2 class="card-title text-base">{gettext("Station description")}</h2>
          <p class="text-sm text-base-content/70">{@station.description}</p>
        </div>
      </div>

      <%!-- Sensors --%>
      <div :if={@sensors != []} class="card bg-base-200 border border-base-300">
        <div class="card-body p-5">
          <h2 class="card-title text-base">{gettext("Sensors")}</h2>
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Type")}</th>
                  <th>{gettext("Model")}</th>
                  <th>{gettext("Installed")}</th>
                  <th>{gettext("Notes")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={s <- @sensors}>
                  <td class="font-medium">
                    {s.measurement_type.name}
                    <span
                      :if={MapSet.member?(@sensor_fault_ids, s.id)}
                      class="text-warning ml-1"
                      title="Active fault"
                    >
                      ⚠
                    </span>
                  </td>
                  <td>{s.model || "—"}</td>
                  <td class="text-xs">{Calendar.strftime(s.installed_at, "%d %b %Y")}</td>
                  <td class="text-xs text-base-content/60 max-w-xs truncate">{s.notes || "—"}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <%!-- Webcams table --%>
      <div :if={@webcam_data != []} class="card bg-base-200 border border-base-300">
        <div class="card-body p-5">
          <h2 class="card-title text-base">{gettext("Webcams")}</h2>
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Name")}</th>
                  <th>{gettext("Description")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={entry <- @webcam_data}>
                  <td class="font-medium">{entry.webcam.name}</td>
                  <td class="text-xs text-base-content/60 max-w-xs truncate">
                    {entry.webcam.description || "—"}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <%!-- Active faults --%>
      <div :if={@active_faults != []} class="card bg-base-200 border border-error/40">
        <div class="card-body p-5">
          <h2 class="card-title text-base text-error">{gettext("Active Faults")}</h2>
          <div class="space-y-2">
            <div
              :for={{f, source} <- @active_faults}
              class="alert alert-error alert-soft text-sm py-2 px-3"
            >
              <div>
                <span class="badge badge-neutral badge-sm mr-1">{source}</span>
                <span class="badge badge-error badge-sm mr-2">{f.fault_type}</span>
                <strong>{f.reason}</strong>
                <span class="ml-2 text-xs opacity-70">
                  {gettext("since")}
                  <span
                    id={"ts-fault-#{f.id}"}
                    phx-hook="LocalTime"
                    data-ts={DateTime.to_unix(f.detected_at, :millisecond)}
                  >
                    —
                  </span>
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Fault history (collapsible) --%>
      <div :if={@fault_history != []} class="card bg-base-200 border border-base-300">
        <div class="card-body p-5">
          <button
            phx-click="toggle_fault_history"
            class="card-title text-base flex items-center justify-between w-full text-left"
          >
            <div class="flex-1">
              <span>{gettext("Fault History (%{count})", count: length(@fault_history))}</span>
              <p class="text-xs text-base-content/40 mt-1 italic">
                {gettext("Showing faults from this year only")}
              </p>
            </div>
            <.icon
              name="hero-chevron-down"
              class={[@show_fault_history && "rotate-180", "transition-transform"]}
            />
          </button>
          <div :if={@show_fault_history} class="overflow-x-auto mt-2">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Type")}</th>
                  <th>{gettext("Reason")}</th>
                  <th>{gettext("Detected")}</th>
                  <th>{gettext("Resolved")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={f <- @fault_history}>
                  <td><span class="badge badge-sm">{f.fault_type}</span></td>
                  <td class="text-sm">{f.reason}</td>
                  <td class="text-xs">
                    <span
                      id={"ts-fh-det-#{f.id}"}
                      phx-hook="LocalTime"
                      data-ts={DateTime.to_unix(f.detected_at, :millisecond)}
                    >
                      —
                    </span>
                  </td>
                  <td class="text-xs">
                    <%= if f.resolved_at do %>
                      <span
                        id={"ts-fh-res-#{f.id}"}
                        phx-hook="LocalTime"
                        data-ts={DateTime.to_unix(f.resolved_at, :millisecond)}
                      >
                        —
                      </span>
                    <% else %>
                      {gettext("Active")}
                    <% end %>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ─── Small components ─────────────────────────────────────────────────────

  defp trend_icon(%{trend: :rising} = assigns) do
    ~H"""
    <span class="text-error text-sm font-bold" title={gettext("Rising")}>↑</span>
    """
  end

  defp trend_icon(%{trend: :falling} = assigns) do
    ~H"""
    <span class="text-info text-sm font-bold" title={gettext("Falling")}>↓</span>
    """
  end

  defp trend_icon(assigns) do
    ~H"""
    <span class="text-base-content/30 text-sm" title={gettext("Stable")}>→</span>
    """
  end

  defp compass_needle(%{dir: nil} = assigns) do
    ~H"""
    <span class="text-base-content/30 text-lg">◎</span>
    """
  end

  defp compass_needle(assigns) do
    ~H"""
    <span
      class="inline-block text-primary text-lg"
      style={"transform: rotate(#{@dir}deg); display: inline-block;"}
      title={"#{trunc(@dir)}° #{degrees_to_cardinal(@dir)}"}
    >
      ↑
    </span>
    """
  end

  defp info_row(assigns) do
    ~H"""
    <div>
      <dt class="text-xs text-base-content/50 uppercase tracking-wide">{@label}</dt>
      <dd class="font-medium">{@value}</dd>
    </div>
    """
  end

  # ─── Events ───────────────────────────────────────────────────────────────

  def handle_event("set_chart_tab", %{"tab" => tab}, socket) do
    valid_tabs = Enum.map(socket.assigns.chart_tabs, & &1.slug)

    if tab in valid_tabs do
      socket = socket |> assign(:chart_tab, tab) |> assign(:chart_loading, true)
      {:noreply, push_chart_data(socket) |> assign(:chart_loading, false)}
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

  def handle_event("toggle_fault_history", _, socket) do
    {:noreply, assign(socket, :show_fault_history, !socket.assigns.show_fault_history)}
  end

  # ─── PubSub handlers ──────────────────────────────────────────────────────

  def handle_info({:new_measurement, %{summary_type: st}}, socket) when not is_nil(st) do
    summaries =
      if socket.assigns.station do
        updated = fetch_summary(socket.assigns.station.id, st)
        Map.put(socket.assigns.summaries, st, updated)
      else
        socket.assigns.summaries
      end

    Process.send_after(self(), :clear_rx_led, 600)

    socket =
      socket
      |> assign(:summaries, summaries)
      |> assign(:rx_led, true)
      |> assign(:last_update_at, DateTime.utc_now())

    # If live and matching active chart tab, append new point
    socket =
      if socket.assigns.chart_live? do
        append_chart_point(socket, st)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:new_measurement, _}, socket), do: {:noreply, socket}

  def handle_info({:new_webcam_shot, %{webcam_id: wid}}, socket) do
    webcam_ids = Enum.map(socket.assigns.installation.webcams, & &1.id)

    if wid in webcam_ids do
      {:ok, shot} = Voria2.Cache.latest_shot_for_webcam(wid)

      updated =
        Enum.map(socket.assigns.webcam_data, fn entry ->
          if entry.webcam.id == wid, do: %{entry | latest_shot: shot}, else: entry
        end)

      {:noreply, assign(socket, :webcam_data, updated)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:clear_rx_led, socket), do: {:noreply, assign(socket, :rx_led, false)}

  # ─── Data loading ─────────────────────────────────────────────────────────

  defp load_installation(id) do
    case Voria2.Network.get_installation(id, authorize?: false, not_found_error?: false) do
      {:ok, nil} ->
        {:error, :not_found}

      {:ok, installation} ->
        installation =
          Ash.load!(
            installation,
            [
              stations: Ash.Query.filter(Voria2.Network.Station, is_active == true),
              webcams: Ash.Query.filter(Voria2.Network.Webcam, is_active == true)
            ],
            authorize?: false
          )

        station = List.first(installation.stations)
        {sensors, sensor_map} = load_sensors(station)

        {:ok,
         %{
           installation: installation,
           station: station,
           sensors: sensors,
           sensor_map: sensor_map
         }}

      {:error, _} = err ->
        err
    end
  end

  defp load_sensors(nil), do: {[], %{}}

  defp load_sensors(station) do
    sensors =
      Voria2.Measurements.SensorInstallation
      |> Ash.Query.filter(station_id == ^station.id)
      |> Ash.Query.load(:measurement_type)
      |> Ash.read!(authorize?: false)
      |> Enum.filter(&is_nil(&1.removed_at))

    sensor_map = Map.new(sensors, fn s -> {s.measurement_type.slug, s} end)
    {sensors, sensor_map}
  end

  defp load_all_summaries(station_id) do
    %{
      temperature: fetch_summary(station_id, :temperature),
      humidity_pressure: fetch_summary(station_id, :humidity_pressure),
      wind: fetch_summary(station_id, :wind),
      rain: fetch_summary(station_id, :rain)
    }
  end

  defp fetch_summary(station_id, type) do
    {:ok, summary} = Voria2.Cache.get_or_compute_summary(station_id, type)
    summary
  end

  defp load_webcam_data(webcams) do
    Enum.map(webcams, fn webcam ->
      {:ok, shot} = Voria2.Cache.latest_shot_for_webcam(webcam.id)
      %{webcam: webcam, latest_shot: shot}
    end)
  end

  defp load_faults(nil, _webcams, _sensors), do: {[], [], MapSet.new()}

  defp load_faults(station, webcams, sensors) do
    station_active =
      case Voria2.Network.active_faults_for_station(station.id, authorize?: false) do
        {:ok, faults} -> Enum.map(faults, &{&1, "Station"})
        _ -> []
      end

    webcam_active =
      Enum.flat_map(webcams, fn webcam ->
        case Voria2.Network.active_faults_for_webcam(webcam.id, authorize?: false) do
          {:ok, faults} -> Enum.map(faults, &{&1, webcam.name})
          _ -> []
        end
      end)

    station_history =
      Voria2.Network.Fault
      |> Ash.Query.filter(station_id == ^station.id and detected_at >= ^start_of_year())
      |> Ash.Query.sort(detected_at: :desc)
      |> Ash.read!(authorize?: false)

    webcam_history =
      Enum.flat_map(webcams, fn webcam ->
        Voria2.Network.Fault
        |> Ash.Query.filter(webcam_id == ^webcam.id and detected_at >= ^start_of_year())
        |> Ash.Query.sort(detected_at: :desc)
        |> Ash.read(authorize?: false)
        |> case do
          {:ok, faults} -> faults
          _ -> []
        end
      end)

    sensor_ids = Enum.map(sensors, & &1.id)

    {sensor_active, sensor_history, sensor_fault_ids} =
      if sensor_ids == [] do
        {[], [], MapSet.new()}
      else
        active =
          case Voria2.Network.active_faults_for_sensor_list(sensor_ids, authorize?: false) do
            {:ok, faults} ->
              Enum.map(faults, fn f ->
                sensor = Enum.find(sensors, &(&1.id == f.sensor_installation_id))
                label = if sensor, do: sensor.measurement_type.slug, else: "sensor"
                {f, label}
              end)

            _ ->
              []
          end

        history =
          Voria2.Network.Fault
          |> Ash.Query.filter(
            sensor_installation_id in ^sensor_ids and detected_at >= ^start_of_year()
          )
          |> Ash.Query.sort(detected_at: :desc)
          |> Ash.read!(authorize?: false)

        ids = active |> Enum.map(fn {f, _} -> f.sensor_installation_id end) |> MapSet.new()
        {active, history, ids}
      end

    {station_active ++ webcam_active ++ sensor_active,
     station_history ++ webcam_history ++ sensor_history, sensor_fault_ids}
  end

  defp start_of_year do
    now = DateTime.utc_now()
    DateTime.new!(Date.new!(now.year, 1, 1), Time.new!(0, 0, 0), "Etc/UTC")
  end

  defp build_chart_tabs(sensors) do
    system_order = @system_slugs

    system_tabs =
      system_order
      |> Enum.flat_map(fn slug ->
        case Enum.find(sensors, fn s -> s.measurement_type.slug == slug end) do
          nil ->
            []

          s ->
            [
              %{
                slug: slug,
                label: system_label(slug),
                chart_type: chart_type_for(s.measurement_type.storage_type, slug)
              }
            ]
        end
      end)

    custom_tabs =
      sensors
      |> Enum.reject(fn s -> s.measurement_type.slug in @system_slugs end)
      |> Enum.map(fn s ->
        %{slug: s.measurement_type.slug, label: s.measurement_type.name, chart_type: :line}
      end)

    system_tabs ++ custom_tabs
  end

  defp chart_type_for(:wind, _), do: :wind
  defp chart_type_for(:rain, _), do: :rain
  defp chart_type_for(_, _), do: :line

  defp system_label("temperature"), do: gettext("Temperature")
  defp system_label("humidity"), do: gettext("Humidity")
  defp system_label("pressure"), do: gettext("Pressure")
  defp system_label("wind"), do: gettext("Wind")
  defp system_label("rain"), do: gettext("Rain")
  defp system_label(slug), do: slug

  # ─── Chart data push ──────────────────────────────────────────────────────

  defp push_chart_data(socket) do
    tab = socket.assigns.chart_tab
    if is_nil(tab) or is_nil(socket.assigns.station), do: socket, else: do_push_chart(socket, tab)
  end

  defp do_push_chart(socket, tab) do
    sensor_map = socket.assigns.sensor_map
    prefs = socket.assigns.user_preferences
    from = socket.assigns.chart_from
    to = socket.assigns.chart_to

    case Map.get(sensor_map, tab) do
      nil ->
        socket

      sensor ->
        mt = sensor.measurement_type

        case mt.storage_type do
          :wind -> push_wind_chart(socket, sensor, prefs, from, to)
          :rain -> push_rain_chart(socket, sensor, prefs, from, to)
          _ -> push_line_chart(socket, sensor, prefs, from, to)
        end
    end
  end

  defp push_line_chart(socket, sensor, prefs, from, to) do
    mt = sensor.measurement_type
    {data, unit, label} = fetch_scalar_data(sensor, mt, prefs, from, to)
    chart_id = "chart-#{mt.slug}"

    push_event(socket, "line_chart_data", %{
      id: chart_id,
      data: data,
      unit: unit,
      label: label,
      from: unix_ms(from),
      to: unix_ms(to)
    })
  end

  defp fetch_scalar_data(sensor, mt, prefs, from, to) do
    {raw, unit, label} =
      case mt.slug do
        "temperature" ->
          r = Voria2.Measurements.temperature_for_sensor!(sensor.id, from, to, authorize?: false)

          {Enum.map(r, &%{t: unix_ms(&1.measured_at), v: convert_temp(&1.value, prefs)}),
           Units.label(prefs.temperature_unit), gettext("Temperature")}

        "humidity" ->
          r = Voria2.Measurements.humidity_for_sensor!(sensor.id, from, to, authorize?: false)
          {Enum.map(r, &%{t: unix_ms(&1.measured_at), v: r1(&1.value)}), "%", gettext("Humidity")}

        "pressure" ->
          r = Voria2.Measurements.pressure_for_sensor!(sensor.id, from, to, authorize?: false)

          {Enum.map(r, &%{t: unix_ms(&1.measured_at), v: convert_pressure(&1.value, prefs)}),
           Units.label(prefs.pressure_unit), gettext("Pressure")}

        _ ->
          # Custom scalar: use measurement_type.unit as-is
          r = Voria2.Measurements.custom_for_sensor!(sensor.id, from, to, authorize?: false)
          {Enum.map(r, &%{t: unix_ms(&1.measured_at), v: r1(&1.value)}), mt.unit || "", mt.name}
      end

    {raw, unit, label}
  end

  defp push_wind_chart(socket, sensor, prefs, from, to) do
    readings = Voria2.Measurements.wind_for_sensor!(sensor.id, from, to, authorize?: false)
    wu = prefs.wind_unit

    data =
      Enum.map(readings, fn r ->
        speed = :math.sqrt(r.u * r.u + r.v * r.v)
        dir = wind_direction(r.u, r.v)

        %{
          t: unix_ms(r.measured_at),
          speed: r1(Units.convert(:wind, speed, :ms, wu)),
          gust: r.gust && r1(Units.convert(:wind, r.gust, :ms, wu)),
          dir: Float.round(dir, 0)
        }
      end)

    # Build wind rose from this window
    rose = build_rose(readings)

    push_event(socket, "wind_chart_data", %{
      data: data,
      unit: Units.label(wu),
      rose: rose,
      from: unix_ms(from),
      to: unix_ms(to)
    })
  end

  defp push_rain_chart(socket, sensor, prefs, from, to) do
    readings = Voria2.Measurements.rain_for_sensor!(sensor.id, from, to, authorize?: false)
    ru = prefs.rain_unit

    data =
      Enum.map(readings, fn r ->
        %{t: unix_ms(r.measured_at), v: r1(Units.convert(:rain, r.interval_mm, :mm, ru))}
      end)

    push_event(socket, "rain_chart_data", %{
      data: data,
      unit: Units.label(ru),
      from: unix_ms(from),
      to: unix_ms(to)
    })
  end

  defp append_chart_point(socket, summary_type) do
    tab = socket.assigns.chart_tab
    sensor_map = socket.assigns.sensor_map
    prefs = socket.assigns.user_preferences

    # Check if active tab matches the updated summary type
    tab_matches? =
      case {summary_type, tab} do
        {:temperature, "temperature"} -> true
        {:humidity_pressure, "humidity"} -> true
        {:humidity_pressure, "pressure"} -> true
        {:wind, "wind"} -> true
        {:rain, "rain"} -> true
        _ -> false
      end

    if tab_matches? do
      case Map.get(sensor_map, tab) do
        nil ->
          socket

        sensor ->
          mt = sensor.measurement_type
          now = DateTime.utc_now()
          now_ms = unix_ms(now)
          one_min_ago = DateTime.add(now, -60, :second)
          range_secs = range_seconds(socket.assigns.chart_range)
          slide_from_ms = now_ms - range_secs * 1000

          case mt.storage_type do
            :wind ->
              readings =
                Voria2.Measurements.wind_for_sensor!(sensor.id, one_min_ago, now,
                  authorize?: false
                )

              case List.last(readings) do
                nil ->
                  socket

                r ->
                  wu = prefs.wind_unit
                  speed = :math.sqrt(r.u * r.u + r.v * r.v)

                  point = %{
                    t: unix_ms(r.measured_at),
                    speed: r1(Units.convert(:wind, speed, :ms, wu)),
                    gust: r.gust && r1(Units.convert(:wind, r.gust, :ms, wu)),
                    dir: Float.round(wind_direction(r.u, r.v), 0)
                  }

                  # Rebuild rose from full window for accuracy
                  rose =
                    build_rose(
                      Voria2.Measurements.wind_for_sensor!(
                        sensor.id,
                        socket.assigns.chart_from,
                        now,
                        authorize?: false
                      )
                    )

                  push_event(socket, "wind_chart_append", %{
                    point: point,
                    rose: rose,
                    from: slide_from_ms,
                    to: now_ms
                  })
              end

            :rain ->
              readings =
                Voria2.Measurements.rain_for_sensor!(sensor.id, one_min_ago, now,
                  authorize?: false
                )

              case List.last(readings) do
                nil ->
                  socket

                r ->
                  ru = prefs.rain_unit

                  point = %{
                    t: unix_ms(r.measured_at),
                    v: r1(Units.convert(:rain, r.interval_mm, :mm, ru))
                  }

                  push_event(socket, "rain_chart_append", %{
                    point: point,
                    from: slide_from_ms,
                    to: now_ms
                  })
              end

            _ ->
              # scalar / custom
              readings =
                case mt.slug do
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
                    case mt.slug do
                      "temperature" -> convert_temp(r.value, prefs)
                      "pressure" -> convert_pressure(r.value, prefs)
                      _ -> r1(r.value)
                    end

                  chart_id = "chart-#{mt.slug}"

                  push_event(socket, "line_chart_append", %{
                    id: chart_id,
                    point: %{t: unix_ms(r.measured_at), v: v},
                    from: slide_from_ms,
                    to: now_ms
                  })
              end
          end
      end
    else
      socket
    end
  end

  defp build_rose(readings) when readings == [], do: []

  defp build_rose(readings) do
    total = length(readings)
    # Only include readings with meaningful wind speed (>0.3 m/s) to avoid
    # mapping all calm conditions to a single arbitrary direction
    windy = Enum.filter(readings, fn r -> :math.sqrt(r.u * r.u + r.v * r.v) > 0.3 end)

    if windy == [] do
      []
    else
      windy
      |> Enum.group_by(fn r -> sector_for(wind_direction(r.u, r.v)) end)
      |> Enum.map(fn {name, rs} ->
        %{sector: name, count: length(rs), pct: length(rs) / total * 100.0}
      end)
      |> Enum.sort_by(& &1.sector)
    end
  end

  # ─── Format helpers ───────────────────────────────────────────────────────

  defp format_temp(nil, _u), do: "—"

  defp format_temp(v, u),
    do: "#{r1(Units.convert(:temperature, v * 1.0, :celsius, u))} #{Units.label(u)}"

  defp format_temp_delta(nil, _u), do: "—"

  defp format_temp_delta(v, u) do
    converted = r1(Units.convert_delta(:temperature, v * 1.0, :celsius, u))
    "#{if converted >= 0, do: "+", else: ""}#{converted} #{Units.label(u)}"
  end

  defp format_humidity(nil), do: "—"
  defp format_humidity(v), do: "#{round(v)}%"

  defp format_pressure_value(nil, _u), do: "—"

  defp format_pressure_value(v, u) do
    converted = Units.convert(:pressure, v * 1.0, :hpa, u)
    if u == :inhg, do: "#{Float.round(converted, 2)}", else: "#{Float.round(converted, 1)}"
  end

  defp format_wind(nil, _u), do: "—"
  defp format_wind(v, u), do: "#{r1(Units.convert(:wind, v * 1.0, :ms, u))} #{Units.label(u)}"

  defp format_rain(nil, _u), do: "—"
  defp format_rain(v, u), do: "#{r1(Units.convert(:rain, v * 1.0, :mm, u))} #{Units.label(u)}"

  defp format_rain_rate(nil, _u), do: "—"

  defp format_rain_rate(v, u),
    do: "#{r1(Units.convert(:rain, v * 1.0, :mm, u))} #{Units.label(u)}/h"

  defp format_datetime(dt), do: Calendar.strftime(dt, "%d %b %Y %H:%M")

  defp convert_temp(v, prefs),
    do: r1(Units.convert(:temperature, v * 1.0, :celsius, prefs.temperature_unit))

  defp convert_pressure(v, prefs) do
    converted = Units.convert(:pressure, v * 1.0, :hpa, prefs.pressure_unit)

    if prefs.pressure_unit == :inhg,
      do: Float.round(converted, 2),
      else: Float.round(converted, 1)
  end

  defp diff_24h_color("—"), do: "text-base-content"

  defp diff_24h_color(s) do
    cond do
      String.starts_with?(s, "+") -> "text-error"
      String.starts_with?(s, "-") -> "text-info"
      true -> "text-base-content"
    end
  end

  defp location_string(installation) do
    [installation.city, installation.country]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  defp r1(v), do: Float.round(v * 1.0, 1)

  # ─── Time helpers ─────────────────────────────────────────────────────────

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

  # ─── Wind helpers ─────────────────────────────────────────────────────────

  @sectors [
    {"N", 0},
    {"NNE", 22.5},
    {"NE", 45},
    {"ENE", 67.5},
    {"E", 90},
    {"ESE", 112.5},
    {"SE", 135},
    {"SSE", 157.5},
    {"S", 180},
    {"SSW", 202.5},
    {"SW", 225},
    {"WSW", 247.5},
    {"W", 270},
    {"WNW", 292.5},
    {"NW", 315},
    {"NNW", 337.5}
  ]

  defp wind_direction(u, v) do
    deg = :math.atan2(u, v) * 180.0 / :math.pi()
    mod = :math.fmod(deg + 180.0, 360.0)
    if mod < 0, do: mod + 360.0, else: mod
  end

  defp sector_for(deg) do
    idx = trunc(Float.floor((:math.fmod(deg, 360.0) + 360.0 + 11.25) / 22.5)) |> rem(16)
    {name, _} = Enum.at(@sectors, idx)
    name
  end

  defp degrees_to_cardinal(deg) do
    idx = trunc(Float.floor((:math.fmod(deg, 360.0) + 360.0 + 11.25) / 22.5)) |> rem(16)
    Enum.at(@cardinals, idx)
  end
end
