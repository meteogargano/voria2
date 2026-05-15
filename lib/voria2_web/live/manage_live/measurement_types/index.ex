defmodule Voria2Web.ManageLive.MeasurementTypes.Index do
  use Voria2Web, :live_view

  on_mount {Voria2Web.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    types = Voria2.Measurements.list_measurement_types!(actor: socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, gettext("Measurement Types"))
     |> assign(:active_section, :measurement_types)
     |> assign(:types, types)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Voria2.Measurements.get_measurement_type(id, actor: socket.assigns.current_user) do
      {:ok, type} ->
        case Voria2.Measurements.destroy_measurement_type(type,
               actor: socket.assigns.current_user
             ) do
          :ok ->
            types =
              Voria2.Measurements.list_measurement_types!(actor: socket.assigns.current_user)

            {:noreply,
             socket
             |> put_flash(:info, gettext("Measurement type deleted."))
             |> assign(:types, types)}

          {:error, _} ->
            {:noreply,
             put_flash(socket, :error, gettext("Failed to delete type. It may be in use."))}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Type not found."))}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-5xl">
      <.breadcrumb crumbs={[{gettext("Measurement Types"), nil}]} />

      <.header>
        {gettext("Measurement Types")}
        <:subtitle>
          {gettext("Define custom sensor measurement categories for your network.")}
        </:subtitle>
        <:actions>
          <.link navigate={~p"/manage/measurement_types/new"} class="btn btn-primary btn-sm gap-2">
            <.icon name="hero-plus" class="size-4" /> {gettext("New Type")}
          </.link>
        </:actions>
      </.header>

      <div class="mt-4">
        <.resource_table
          id="types-table"
          rows={@types}
          empty_title={gettext("No measurement types yet")}
          empty_message={
            gettext("Create custom types for your sensors, or standard types will be auto-detected.")
          }
          empty_icon="hero-beaker"
        >
          <:empty_actions>
            <.link navigate={~p"/manage/measurement_types/new"} class="btn btn-primary btn-sm gap-2">
              <.icon name="hero-plus" class="size-4" /> {gettext("New Type")}
            </.link>
          </:empty_actions>
          <:col :let={t} label={gettext("Name")}>
            <span class="font-medium">{t.name}</span>
          </:col>
          <:col :let={t} label={gettext("Slug")}>
            <code class="text-xs font-mono text-base-content/50">{t.slug}</code>
          </:col>
          <:col :let={t} label={gettext("Storage Type")}>
            <span class="badge badge-sm badge-ghost capitalize">{t.storage_type}</span>
          </:col>
          <:col :let={t} label={gettext("Unit")}>
            {t.unit || "—"}
          </:col>
          <:col :let={t} label={gettext("Owner")}>
            {if is_nil(t.user_id), do: gettext("System"), else: gettext("User-defined")}
          </:col>
          <:col :let={t} label={gettext("Status")}>
            <.status_badge active={t.is_active} />
          </:col>
          <:action :let={t}>
            <.link
              :if={!is_nil(t.user_id)}
              navigate={~p"/manage/measurement_types/#{t.id}/edit"}
              class="btn btn-ghost btn-xs"
            >
              <.icon name="hero-pencil" class="size-3.5" />
            </.link>
            <button
              :if={!is_nil(t.user_id)}
              class="btn btn-ghost btn-xs text-error hover:bg-error/10"
              onclick={"document.getElementById('del-t-#{t.id}').showModal()"}
            >
              <.icon name="hero-trash" class="size-3.5" />
            </button>
            <.confirm_modal
              :if={!is_nil(t.user_id)}
              id={"del-t-#{t.id}"}
              title={gettext("Delete %{name}?", name: t.name)}
              message={gettext("This type will be removed. Sensors using it may be affected.")}
              confirm_label={gettext("Delete")}
              confirm_event="delete"
              confirm_value={%{id: t.id}}
              danger={true}
            />
          </:action>
        </.resource_table>
      </div>
    </div>
    """
  end
end
