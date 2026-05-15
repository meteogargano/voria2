defmodule Voria2Web.ManageLive.Dashboard do
  use Voria2Web, :live_view

  on_mount {Voria2Web.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Dashboard"))
     |> assign(:active_section, :dashboard)}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-4xl">
      <.header>
        {gettext("Welcome back, %{name}", name: @current_user.name || @current_user.email)}
        <:subtitle>{gettext("Manage your weather network from here.")}</:subtitle>
        <:actions>
          <.link navigate={~p"/manage/installations/new"} class="btn btn-primary btn-sm gap-2">
            <.icon name="hero-plus" class="size-4" /> {gettext("New Installation")}
          </.link>
        </:actions>
      </.header>

      <div class="mt-4z grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
        <.dashboard_card
          title={gettext("Installations")}
          description={gettext("Physical locations hosting stations and webcams")}
          icon="hero-map-pin"
          path={~p"/manage/installations"}
          color="neutral"
        />
        <.dashboard_card
          title={gettext("Measurement Types")}
          description={gettext("Define custom sensor measurement categories")}
          icon="hero-beaker"
          path={~p"/manage/measurement_types"}
          color="neutral"
        />
        <.dashboard_card
          :if={@current_user.admin}
          title={gettext("Fault Monitor")}
          description={gettext("View and resolve active network faults")}
          icon="hero-exclamation-triangle"
          path={~p"/manage/faults"}
          color="error"
        />
        <.dashboard_card
          :if={@current_user.admin}
          title={gettext("Blog Pages")}
          description={gettext("Create and organize blog pages with categories")}
          icon="hero-newspaper"
          path={~p"/manage/blog_pages"}
          color="neutral"
        />
        <.dashboard_card
          :if={@current_user.admin}
          title={gettext("Blog Content")}
          description={gettext("Manage files in the blogcontent folder on R2")}
          icon="hero-document-text"
          path={~p"/manage/blogcontent"}
          color="neutral"
        />
        <.dashboard_card
          :if={@current_user.admin}
          title={gettext("Users")}
          description={gettext("Manage platform users and access")}
          icon="hero-users"
          path={~p"/manage/users"}
          color="neutral"
        />
        <.dashboard_card
          :if={@current_user.admin}
          title={gettext("Webcam Shot Purge")}
          description={gettext("Count and bulk-purge webcam shots in monitored batches")}
          icon="hero-trash"
          path={~p"/manage/webcam-shots/purge"}
          color="error"
        />
        <.dashboard_card
          title={gettext("Profile")}
          description={gettext("Update your name and change your password")}
          icon="hero-user-circle"
          path={~p"/manage/profile"}
          color="neutral"
        />
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :icon, :string, required: true
  attr :path, :string, required: true
  attr :color, :string, default: "primary"
  attr :rest, :global

  defp dashboard_card(assigns) do
    ~H"""
    <.link
      navigate={@path}
      class="group border border-base-300 bg-base-100 p-5 hover:border-primary/40 hover:bg-base-200/50 transition-all duration-150"
    >
      <div class={[
        "size-10 rounded-lg flex items-center justify-center mb-4",
        @color == "primary" && "bg-primary/10 text-base-content",
        @color == "secondary" && "bg-secondary/10 text-base-content",
        @color == "error" && "bg-error/10 text-base-content",
        @color == "accent" && "bg-accent/10 text-base-content",
        @color == "neutral" && "bg-base-300 text-base-content"
      ]}>
        <.icon name={@icon} class="size-5" />
      </div>
      <h3 class="font-semibold text-sm group-hover:text-primary transition-colors">{@title}</h3>
      <p class="text-xs text-base-content/50 mt-1 leading-relaxed">{@description}</p>
    </.link>
    """
  end
end
