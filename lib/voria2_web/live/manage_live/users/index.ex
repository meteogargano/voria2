defmodule Voria2Web.ManageLive.Users.Index do
  use Voria2Web, :live_view

  on_mount {Voria2Web.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    unless socket.assigns.current_user.admin do
      {:ok,
       socket
       |> put_flash(:error, gettext("Admin access required."))
       |> push_navigate(to: ~p"/manage")}
    else
      users =
        Ash.read!(Voria2.Accounts.User, actor: socket.assigns.current_user, authorize?: false)

      {:ok,
       socket
       |> assign(:page_title, gettext("Users"))
       |> assign(:active_section, :users)
       |> assign(:users, users)}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-5xl">
      <.breadcrumb crumbs={[{gettext("Users"), nil}]} />

      <.header>
        {gettext("Users")}
        <:subtitle>{gettext("All registered users on the platform.")}</:subtitle>
        <:actions>
          <.link navigate={~p"/manage/users/new"} class="btn btn-primary btn-sm gap-2">
            <.icon name="hero-plus" class="size-4" /> {gettext("New User")}
          </.link>
        </:actions>
      </.header>

      <div class="mt-4">
        <.resource_table
          id="users-table"
          rows={@users}
          empty_title={gettext("No users")}
          empty_message={gettext("No users registered yet.")}
          empty_icon="hero-users"
        >
          <:col :let={u} label={gettext("Name")}>
            <span class="font-medium">{u.name || "—"}</span>
          </:col>
          <:col :let={u} label={gettext("Email")}>
            <span class="font-mono text-sm">{u.email}</span>
          </:col>
          <:col :let={u} label={gettext("Role")}>
            <span class={[
              "badge badge-sm",
              u.admin && "badge-warning",
              !u.admin && "badge-ghost"
            ]}>
              {if u.admin, do: gettext("Admin"), else: gettext("User")}
            </span>
          </:col>
          <:col :let={u} label={gettext("Confirmed")}>
            <span class="text-xs text-base-content/50">
              {if u.confirmed_at,
                do: Calendar.strftime(u.confirmed_at, "%b %d, %Y"),
                else: gettext("Pending")}
            </span>
          </:col>
          <:action :let={u}>
            <.link navigate={~p"/manage/users/#{u.id}/edit"} class="btn btn-ghost btn-xs">
              <.icon name="hero-pencil" class="size-3.5" />
            </.link>
          </:action>
        </.resource_table>
      </div>
    </div>
    """
  end
end
