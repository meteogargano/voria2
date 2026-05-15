defmodule Voria2Web.ManageLive.Installations.Index do
  use Voria2Web, :live_view

  on_mount {Voria2Web.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    installations = Voria2.Network.list_installations!(actor: socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, gettext("Installations"))
     |> assign(:active_section, :installations)
     |> assign(:installations, installations)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Voria2.Network.get_installation(id, actor: socket.assigns.current_user) do
      {:ok, installation} ->
        case Voria2.Network.destroy_installation(installation, actor: socket.assigns.current_user) do
          :ok ->
            installations =
              Voria2.Network.list_installations!(actor: socket.assigns.current_user)

            {:noreply,
             socket
             |> put_flash(:info, gettext("Installation deleted."))
             |> assign(:installations, installations)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Failed to delete installation."))}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Installation not found."))}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-5xl">
      <.breadcrumb crumbs={[{gettext("Installations"), nil}]} />

      <.header>
        {gettext("Installations")}
        <:subtitle>
          {gettext("Physical locations hosting your weather stations and webcams.")}
        </:subtitle>
        <:actions>
          <.link navigate={~p"/manage/installations/new"} class="btn btn-primary btn-sm gap-2">
            <.icon name="hero-plus" class="size-4" /> {gettext("New Installation")}
          </.link>
        </:actions>
      </.header>

      <div class="mt-4">
        <.resource_table
          id="installations-table"
          rows={@installations}
          empty_title={gettext("No installations yet")}
          empty_message={
            gettext("Create your first installation to start managing stations and webcams.")
          }
          empty_icon="hero-map-pin"
        >
          <:empty_actions>
            <.link navigate={~p"/manage/installations/new"} class="btn btn-primary btn-sm gap-2">
              <.icon name="hero-plus" class="size-4" /> {gettext("New Installation")}
            </.link>
          </:empty_actions>
          <:col :let={i} label={gettext("Name")}>
            <.link navigate={~p"/manage/installations/#{i.id}"} class="font-medium hover:text-primary">
              {i.name}
            </.link>
          </:col>
          <:col :let={i} label={gettext("Location")}>
            <span class="text-base-content/60">
              {[i.city, i.country] |> Enum.reject(&is_nil/1) |> Enum.join(", ")}
            </span>
          </:col>
          <:col :let={i} label={gettext("Coordinates")}>
            <span class="font-mono text-xs text-base-content/50">
              {format_coord(i.latitude)}, {format_coord(i.longitude)}
            </span>
          </:col>
          <:col :let={i} label={gettext("Status")}>
            <.status_badge active={i.is_active} />
          </:col>
          <:action :let={i}>
            <.link navigate={~p"/manage/installations/#{i.id}"} class="btn btn-ghost btn-xs gap-1">
              <.icon name="hero-eye" class="size-3.5" />
            </.link>
            <.link
              navigate={~p"/manage/installations/#{i.id}/edit"}
              class="btn btn-ghost btn-xs gap-1"
            >
              <.icon name="hero-pencil" class="size-3.5" />
            </.link>
            <button
              class="btn btn-ghost btn-xs text-error hover:bg-error/10"
              onclick={"document.getElementById('del-#{i.id}').showModal()"}
            >
              <.icon name="hero-trash" class="size-3.5" />
            </button>
            <.confirm_modal
              id={"del-#{i.id}"}
              title={gettext("Delete %{name}?", name: i.name)}
              message={
                gettext(
                  "This will also delete all stations, webcams, and sensors under this installation."
                )
              }
              confirm_label={gettext("Delete")}
              confirm_event="delete"
              confirm_value={%{id: i.id}}
              danger={true}
            />
          </:action>
        </.resource_table>
      </div>
    </div>
    """
  end

  defp format_coord(nil), do: "—"
  defp format_coord(v), do: :erlang.float_to_binary(v, decimals: 4)
end
