defmodule Voria2Web.ManageLive.Installations.Show do
  use Voria2Web, :live_view

  on_mount {Voria2Web.LiveUserAuth, :live_user_required}

  def mount(%{"id" => id}, _session, socket) do
    case Voria2.Network.get_installation(id, actor: socket.assigns.current_user) do
      {:ok, installation} ->
        all_stations = Voria2.Network.list_stations!(actor: socket.assigns.current_user)
        stations = Enum.filter(all_stations, &(&1.installation_id == installation.id))

        all_webcams = Voria2.Network.list_webcams!(actor: socket.assigns.current_user)
        webcams = Enum.filter(all_webcams, &(&1.installation_id == installation.id))

        {:ok,
         socket
         |> assign(:page_title, installation.name)
         |> assign(:active_section, :installations)
         |> assign(:installation, installation)
         |> assign(:stations, stations)
         |> assign(:webcams, webcams)
         |> assign(:active_tab, :overview)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Installation not found."))
         |> push_navigate(to: ~p"/manage/installations")}
    end
  end

  def handle_params(params, _uri, socket) do
    tab =
      case params["tab"] do
        "photos" -> :photos
        "stations" -> :stations
        "webcams" -> :webcams
        _ -> :overview
      end

    {:noreply, assign(socket, :active_tab, tab)}
  end

  def handle_event("delete_station", %{"id" => id}, socket) do
    case Voria2.Network.get_station(id, actor: socket.assigns.current_user) do
      {:ok, station} ->
        case Voria2.Network.destroy_station(station, actor: socket.assigns.current_user) do
          :ok ->
            all_stations = Voria2.Network.list_stations!(actor: socket.assigns.current_user)

            stations =
              Enum.filter(all_stations, &(&1.installation_id == socket.assigns.installation.id))

            {:noreply,
             socket
             |> put_flash(:info, gettext("Station deleted."))
             |> assign(:stations, stations)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Failed to delete station."))}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Station not found."))}
    end
  end

  def handle_event("delete_webcam", %{"id" => id}, socket) do
    case Voria2.Network.get_webcam(id, actor: socket.assigns.current_user) do
      {:ok, webcam} ->
        case Voria2.Network.destroy_webcam(webcam, actor: socket.assigns.current_user) do
          :ok ->
            all_webcams = Voria2.Network.list_webcams!(actor: socket.assigns.current_user)

            webcams =
              Enum.filter(all_webcams, &(&1.installation_id == socket.assigns.installation.id))

            {:noreply,
             socket
             |> put_flash(:info, gettext("Webcam deleted."))
             |> assign(:webcams, webcams)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Failed to delete webcam."))}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Webcam not found."))}
    end
  end

  def handle_event("delete_installation", _params, socket) do
    case Voria2.Network.destroy_installation(
           socket.assigns.installation,
           actor: socket.assigns.current_user
         ) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Installation deleted."))
         |> push_navigate(to: ~p"/manage/installations")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to delete installation."))}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-5xl">
      <.breadcrumb crumbs={[
        {gettext("Installations"), ~p"/manage/installations"},
        {@installation.name, nil}
      ]} />

      <.header>
        {@installation.name}
        <:subtitle>
          {[@installation.city, @installation.country]
          |> Enum.reject(&is_nil/1)
          |> Enum.join(", ")}
        </:subtitle>
        <:actions>
          <.link
            navigate={~p"/manage/installations/#{@installation.id}/edit"}
            class="btn btn-ghost btn-sm gap-2"
          >
            <.icon name="hero-pencil" class="size-4" /> {gettext("Edit")}
          </.link>
          <button
            class="btn btn-ghost btn-sm text-error hover:bg-error/10 gap-2"
            onclick="document.getElementById('del-installation').showModal()"
          >
            <.icon name="hero-trash" class="size-4" /> {gettext("Delete")}
          </button>
        </:actions>
      </.header>

      <.confirm_modal
        id="del-installation"
        title={gettext("Delete %{name}?", name: @installation.name)}
        message={
          gettext(
            "This will permanently delete all stations, webcams, sensors, and API keys under this installation."
          )
        }
        confirm_label={gettext("Delete Installation")}
        confirm_event="delete_installation"
        confirm_value={%{}}
        danger={true}
      />

      <.tab_bar
        tabs={[
          {:overview, gettext("Overview"), ~p"/manage/installations/#{@installation.id}"},
          {:photos, gettext("Photos (%{count})", count: length(@installation.picture_keys)),
           ~p"/manage/installations/#{@installation.id}/photos"},
          {:stations, gettext("Stations (%{count})", count: length(@stations)),
           ~p"/manage/installations/#{@installation.id}?tab=stations"},
          {:webcams, gettext("Webcams (%{count})", count: length(@webcams)),
           ~p"/manage/installations/#{@installation.id}?tab=webcams"}
        ]}
        active_tab={@active_tab}
      />

      <%!-- Overview Tab --%>
      <div :if={@active_tab == :overview}>
        <.detail_section title={gettext("Details")}>
          <:item label={gettext("Status")}><.status_badge active={@installation.is_active} /></:item>
          <:item label={gettext("Description")}>
            {if @installation.description, do: @installation.description, else: "—"}
          </:item>
          <:item label={gettext("City")}>{@installation.city || "—"}</:item>
          <:item label={gettext("Country")}>{@installation.country || "—"}</:item>
          <:item label={gettext("Timezone")}>{@installation.timezone || "—"}</:item>
          <:item label={gettext("Latitude")}>
            {if @installation.latitude, do: Float.to_string(@installation.latitude), else: "—"}
          </:item>
          <:item label={gettext("Longitude")}>
            {if @installation.longitude, do: Float.to_string(@installation.longitude), else: "—"}
          </:item>
          <:item label={gettext("Altitude")}>
            {if @installation.altitude,
              do: "#{Float.to_string(@installation.altitude)} m",
              else: "—"}
          </:item>
          <:item label={gettext("Created")}>
            {Calendar.strftime(@installation.inserted_at, "%b %d, %Y")}
          </:item>
        </.detail_section>
      </div>

      <%!-- Stations Tab --%>
      <div :if={@active_tab == :stations}>
        <div class="flex justify-end mb-4">
          <.link
            navigate={~p"/manage/installations/#{@installation.id}/stations/new"}
            class="btn btn-primary btn-sm gap-2"
          >
            <.icon name="hero-plus" class="size-4" /> {gettext("New Station")}
          </.link>
        </div>
        <.resource_table
          id="stations-table"
          rows={@stations}
          empty_title={gettext("No stations yet")}
          empty_message={gettext("Add a weather station to start collecting measurements.")}
          empty_icon="hero-signal"
        >
          <:empty_actions>
            <.link
              navigate={~p"/manage/installations/#{@installation.id}/stations/new"}
              class="btn btn-primary btn-sm gap-2"
            >
              <.icon name="hero-plus" class="size-4" /> {gettext("New Station")}
            </.link>
          </:empty_actions>
          <:col :let={s} label={gettext("Name")}>
            <.link navigate={~p"/manage/stations/#{s.id}"} class="font-medium hover:text-primary">
              {s.name}
            </.link>
          </:col>
          <:col :let={s} label={gettext("Slug")}>
            <code class="text-xs font-mono text-base-content/50">{s.slug}</code>
          </:col>
          <:col :let={s} label={gettext("Status")}>
            <.status_badge active={s.is_active} />
          </:col>
          <:action :let={s}>
            <.link navigate={~p"/manage/stations/#{s.id}"} class="btn btn-ghost btn-xs">
              <.icon name="hero-eye" class="size-3.5" />
            </.link>
            <.link navigate={~p"/manage/stations/#{s.id}/edit"} class="btn btn-ghost btn-xs">
              <.icon name="hero-pencil" class="size-3.5" />
            </.link>
            <button
              class="btn btn-ghost btn-xs text-error hover:bg-error/10"
              onclick={"document.getElementById('del-s-#{s.id}').showModal()"}
            >
              <.icon name="hero-trash" class="size-3.5" />
            </button>
            <.confirm_modal
              id={"del-s-#{s.id}"}
              title={gettext("Delete %{name}?", name: s.name)}
              message={gettext("This will also delete all sensors and API keys for this station.")}
              confirm_label={gettext("Delete")}
              confirm_event="delete_station"
              confirm_value={%{id: s.id}}
              danger={true}
            />
          </:action>
        </.resource_table>
      </div>

      <%!-- Webcams Tab --%>
      <div :if={@active_tab == :webcams}>
        <div class="flex justify-end mb-4">
          <.link
            navigate={~p"/manage/installations/#{@installation.id}/webcams/new"}
            class="btn btn-primary btn-sm gap-2"
          >
            <.icon name="hero-plus" class="size-4" /> {gettext("New Webcam")}
          </.link>
        </div>
        <.resource_table
          id="webcams-table"
          rows={@webcams}
          empty_title={gettext("No webcams yet")}
          empty_message={gettext("Add a webcam to start capturing images.")}
          empty_icon="hero-camera"
        >
          <:empty_actions>
            <.link
              navigate={~p"/manage/installations/#{@installation.id}/webcams/new"}
              class="btn btn-primary btn-sm gap-2"
            >
              <.icon name="hero-plus" class="size-4" /> {gettext("New Webcam")}
            </.link>
          </:empty_actions>
          <:col :let={w} label={gettext("Name")}>
            <.link navigate={~p"/manage/webcams/#{w.id}"} class="font-medium hover:text-primary">
              {w.name}
            </.link>
          </:col>
          <:col :let={w} label={gettext("Slug")}>
            <code class="text-xs font-mono text-base-content/50">{w.slug}</code>
          </:col>
          <:col :let={w} label={gettext("Status")}>
            <.status_badge active={w.is_active} />
          </:col>
          <:action :let={w}>
            <.link navigate={~p"/manage/webcams/#{w.id}"} class="btn btn-ghost btn-xs">
              <.icon name="hero-eye" class="size-3.5" />
            </.link>
            <.link navigate={~p"/manage/webcams/#{w.id}/edit"} class="btn btn-ghost btn-xs">
              <.icon name="hero-pencil" class="size-3.5" />
            </.link>
            <button
              class="btn btn-ghost btn-xs text-error hover:bg-error/10"
              onclick={"document.getElementById('del-w-#{w.id}').showModal()"}
            >
              <.icon name="hero-trash" class="size-3.5" />
            </button>
            <.confirm_modal
              id={"del-w-#{w.id}"}
              title={gettext("Delete %{name}?", name: w.name)}
              message={gettext("This will also delete all API keys for this webcam.")}
              confirm_label={gettext("Delete")}
              confirm_event="delete_webcam"
              confirm_value={%{id: w.id}}
              danger={true}
            />
          </:action>
        </.resource_table>
      </div>

      <%!-- Photos Tab --%>
      <div :if={@active_tab == :photos}>
        <div class="flex justify-end mb-4">
          <.link
            navigate={~p"/manage/installations/#{@installation.id}/photos"}
            class="btn btn-primary btn-sm gap-2"
          >
            <.icon name="hero-plus" class="size-4" /> {gettext("Manage Photos")}
          </.link>
        </div>
        <div class="card bg-base-200 border border-base-300">
          <div class="card-body p-6">
            <.installation_photos_grid
              id="photos-preview"
              pictures={@installation.picture_keys}
              editable={false}
              empty_title={gettext("No photos yet")}
              empty_message={gettext("Click 'Manage Photos' to upload your first photo.")}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end
end
