defmodule Voria2Web.ManageLive.Faults.Index do
  use Voria2Web, :live_view

  on_mount {Voria2Web.LiveUserAuth, :live_user_required}

  require Ash.Query

  def mount(_params, _session, socket) do
    unless socket.assigns.current_user.admin do
      {:ok,
       socket
       |> put_flash(:error, gettext("Admin access required."))
       |> push_navigate(to: ~p"/manage")}
    else
      {:ok,
       socket
       |> assign(:page, 1)
       |> assign(:per_page, 10)
       |> assign(:fault_type_filter, nil)
       |> load_faults()}
    end
  end

  def handle_params(params, _uri, socket) do
    socket
    |> assign(:page, max(1, Map.get(params, "page", "1") |> String.to_integer()))
    |> assign(:fault_type_filter, Map.get(params, "filter"))
    |> then(&load_faults/1)

    {:noreply, socket}
  end

  def handle_event("filter", %{"filter" => filter}, socket) do
    new_filter = if(filter == "all", do: nil, else: filter)

    {:noreply,
     socket
     |> assign(:page, 1)
     |> assign(:fault_type_filter, new_filter)
     |> load_faults()
     |> push_patch(to: ~p"/manage/faults?page=1&filter=#{filter}")}
  end

  def handle_event("next_page", _, socket) do
    page = socket.assigns.page
    max_page = max_page(socket.assigns.resolved_page)

    if page < max_page do
      {:noreply,
       socket
       |> assign(:page, page + 1)
       |> load_faults()
       |> push_patch(to: ~p"/manage/faults?page=#{page + 1}")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("prev_page", _, socket) do
    page = socket.assigns.page

    if page > 1 do
      {:noreply,
       socket
       |> assign(:page, page - 1)
       |> load_faults()
       |> push_patch(to: ~p"/manage/faults?page=#{page - 1}")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("resolve_fault", %{"id" => fault_id}, socket) do
    all_faults = socket.assigns.active_faults ++ socket.assigns.resolved_page.results

    case Enum.find(all_faults, &(&1.id == fault_id)) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Fault not found."))}

      fault ->
        case Voria2.Network.resolve_fault(
               fault,
               %{resolved_by_id: socket.assigns.current_user.id},
               actor: socket.assigns.current_user
             ) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, gettext("Fault resolved."))
             |> load_faults()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Failed to resolve fault."))}
        end
    end
  end

  defp max_page(%Ash.Page.Offset{count: count, limit: limit}) when is_integer(count) do
    ceil(count / limit)
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-5xl">
      <.breadcrumb crumbs={[{gettext("Faults"), nil}]} />

      <.header>
        {gettext("Fault Monitor")}
        <:subtitle>{gettext("Active and historical faults across the entire network.")}</:subtitle>
      </.header>

      <div :if={@active_faults != []} class="mt-4">
        <div class="flex items-center gap-2 mb-4">
          <.icon name="hero-exclamation-circle" class="size-4 text-error" />
          <h2 class="text-sm font-semibold text-error">
            {gettext("Active Faults")} ({length(@active_faults)})
          </h2>
        </div>
        <div class="border border-error/30 bg-error/5 overflow-hidden">
          <div class="divide-y divide-error/20">
            <div :for={fault <- @active_faults} class="p-4 flex items-start gap-4">
              <.icon name="hero-exclamation-circle" class="size-4 text-error mt-0.5 shrink-0" />
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2 flex-wrap">
                  <span class="font-medium text-sm capitalize">
                    {format_fault_type(fault)}
                  </span>
                  <span class="badge badge-xs badge-error">{gettext("Active")}</span>
                  <span class="text-xs text-base-content/50">
                    {fault_subject_label(fault)}
                  </span>
                </div>
                <p class="text-sm text-base-content/60 mt-0.5">{fault.reason}</p>
                <p class="text-xs text-base-content/40 mt-1">
                  {gettext("Detected %{datetime}", datetime: format_datetime(fault.detected_at))}
                </p>
              </div>
              <button
                class="btn btn-xs btn-ghost text-success hover:bg-success/10 shrink-0"
                onclick={"document.getElementById('resolve-#{fault.id}').showModal()"}
              >
                <.icon name="hero-check" class="size-3.5" /> {gettext("Resolve")}
              </button>
              <.confirm_modal
                id={"resolve-#{fault.id}"}
                title={gettext("Resolve Fault")}
                message={gettext("Mark this fault as resolved?")}
                confirm_label={gettext("Resolve")}
                confirm_event="resolve_fault"
                confirm_value={%{id: fault.id}}
              />
            </div>
          </div>
        </div>
      </div>

      <div class="mt-4">
        <div class="flex items-center gap-4 mb-4">
          <h2 class="text-sm font-semibold text-base-content/60">
            {gettext("Fault History")}
            <span :if={@resolved_page.count} class="text-base-content/50">
              {gettext("(%{count} total)", count: @resolved_page.count)}
            </span>
          </h2>
          <form phx-change="filter" class="shrink-0">
            <select name="filter" class="select select-bordered select-sm">
              <option value="all" selected={@fault_type_filter == nil}>
                {gettext("All Types")}
              </option>
              <option value="auto_offline" selected={@fault_type_filter == "auto_offline"}>
                Auto Offline
              </option>
              <option value="manual" selected={@fault_type_filter == "manual"}>
                Manual
              </option>
            </select>
          </form>
        </div>
        <.resource_table
          id="faults-history"
          rows={@resolved_page.results}
          empty_title={gettext("No fault history")}
          empty_message={gettext("No faults found matching current filter.")}
          empty_icon="hero-check-circle"
        >
          <:col :let={fault} label={gettext("Type")}>
            <span class="capitalize">{format_fault_type(fault)}</span>
          </:col>
          <:col :let={fault} label={gettext("Subject")}>
            <span class="text-sm text-base-content/60">{fault_subject_label(fault)}</span>
          </:col>
          <:col :let={fault} label={gettext("Reason")}>
            <span class="text-sm">{fault.reason}</span>
          </:col>
          <:col :let={fault} label={gettext("Detected")}>
            <span class="text-xs">{format_datetime(fault.detected_at)}</span>
          </:col>
          <:col :let={fault} label={gettext("Resolved")}>
            <span class="text-xs">{format_datetime(fault.resolved_at)}</span>
          </:col>
        </.resource_table>

        <div :if={@resolved_page.count > 0} class="flex items-center justify-between gap-2 mt-4">
          <div class="text-sm text-base-content/60">
            {gettext("Showing page %{page} of %{max_page}",
              page: @page,
              max_page: max_page(@resolved_page)
            )}
          </div>
          <div class="flex gap-1">
            <button
              class="btn btn-sm"
              phx-click="prev_page"
              disabled={@page <= 1}
            >
              <.icon name="hero-chevron-left" class="size-3.5" /> {gettext("Prev")}
            </button>
            <button
              class="btn btn-sm"
              phx-click="next_page"
              disabled={@page >= max_page(@resolved_page)}
            >
              {gettext("Next")} <.icon name="hero-chevron-right" class="size-3.5" />
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp load_faults(socket) do
    actor = socket.assigns.current_user
    page = socket.assigns.page
    per_page = socket.assigns.per_page
    filter = socket.assigns.fault_type_filter

    offset = (page - 1) * per_page

    all_faults = Voria2.Network.list_faults!(actor: actor)
    active_faults = Enum.filter(all_faults, &is_nil(&1.resolved_at))

    resolved_query =
      Voria2.Network.Fault
      |> Ash.Query.sort(detected_at: :desc)

    resolved_query =
      if filter && filter != "all" do
        filter_value = String.to_atom(filter)
        import Ash.Expr, only: [expr: 1]
        Ash.Query.filter(resolved_query, expr(fault_type == ^filter_value))
      else
        resolved_query
      end

    resolved_page =
      resolved_query
      |> Ash.Query.page(limit: per_page, offset: offset, count: true)
      |> Ash.read!(domain: Voria2.Network)

    socket
    |> assign(:page_title, gettext("Fault Monitor"))
    |> assign(:active_section, :faults)
    |> assign(:active_faults, active_faults)
    |> assign(:resolved_page, resolved_page)
  end

  defp fault_subject_label(fault) do
    cond do
      fault.station_id ->
        "Station #{String.slice(fault.station_id, 0, 8)}…"

      fault.webcam_id ->
        "Webcam #{String.slice(fault.webcam_id, 0, 8)}…"

      fault.sensor_installation_id ->
        "Sensor #{String.slice(fault.sensor_installation_id, 0, 8)}…"

      true ->
        "Unknown"
    end
  end

  defp format_fault_type(fault) do
    fault.fault_type
    |> to_string()
    |> String.replace("_", " ")
  end

  defp format_datetime(nil), do: "—"

  defp format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y %H:%M")

  defp format_datetime(%NaiveDateTime{} = ndt), do: Calendar.strftime(ndt, "%b %d, %Y %H:%M")
end
