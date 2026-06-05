defmodule Voria2Web.Router do
  use Voria2Web, :router

  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {Voria2Web.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
    plug Voria2Web.Plugs.LoadPreferences
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  pipeline :ingest do
    plug :accepts, ["json"]
    plug Voria2Web.Plugs.IngestAuth
  end

  pipeline :webcam_ingest do
    plug :accepts, ["json"]
    plug Voria2Web.Plugs.WebcamIngestAuth
  end

  scope "/api/v1", Voria2Web do
    pipe_through :ingest

    post "/ingest/verify", IngestController, :verify
    post "/ingest", IngestController, :create
    post "/ingest/bulk", IngestController, :bulk
  end

  scope "/api/v1", Voria2Web do
    pipe_through :webcam_ingest

    post "/webcam/ingest/verify", WebcamIngestController, :verify
    post "/webcam/ingest", WebcamIngestController, :create
  end

  scope "/", Voria2Web do
    get "/healthz", HealthController, :show
    get "/sitemap.xml", SitemapController, :index
  end

  scope "/", Voria2Web do
    pipe_through :browser

    get "/", PageController, :home
    get "/associazione", PageController, :associazione
    get "/statuto", PageController, :statuto
    get "/blog", BlogController, :index
    get "/blog/:slug", BlogController, :show
    get "/dailylog", DailyLogController, :index
    get "/dailylog/:slug", DailyLogController, :show

    get "/preferences", PreferencesController, :index
    post "/preferences", PreferencesController, :save

    # Public routes — user may or may not be authenticated
    ash_authentication_live_session :public_routes,
      on_mount: [{Voria2Web.Live.Hooks.PreferencesHook, :default}],
      layout: {Voria2Web.Layouts, :public} do
      live "/map", MapLive, :index
      live "/compare", CompareLive, :index
      live "/installations/:id", InstallationLive, :show
      live "/webcams/:webcam_id/viewer", WebcamViewerLive, :show
      live "/webcams", WebcamsLive, :index
      live "/webcams/:webcam_id", WebcamsLive, :show
    end

    # Back office — requires authentication, uses manage sidebar layout
    ash_authentication_live_session :manage_routes,
      on_mount: [{Voria2Web.Live.Hooks.PreferencesHook, :default}],
      layout: {Voria2Web.Layouts, :manage} do
      # Dashboard
      live "/manage", ManageLive.Dashboard, :index

      # Installations
      live "/manage/installations", ManageLive.Installations.Index, :index
      live "/manage/installations/new", ManageLive.Installations.Form, :new
      live "/manage/installations/:id", ManageLive.Installations.Show, :show
      live "/manage/installations/:id/edit", ManageLive.Installations.Form, :edit
      live "/manage/installations/:id/photos", ManageLive.Installations.Photos, :index

      # Stations (created under an installation, then standalone)
      live "/manage/installations/:installation_id/stations/new", ManageLive.Stations.Form, :new
      live "/manage/stations/:id", ManageLive.Stations.Show, :show
      live "/manage/stations/:id/edit", ManageLive.Stations.Form, :edit

      # Webcams (created under an installation, then standalone)
      live "/manage/installations/:installation_id/webcams/new", ManageLive.Webcams.Form, :new
      live "/manage/webcams/:id", ManageLive.Webcams.Show, :show
      live "/manage/webcams/:id/edit", ManageLive.Webcams.Form, :edit

      # Sensor installations (created under a station, then standalone)
      live "/manage/stations/:station_id/sensors/new", ManageLive.Sensors.Form, :new
      live "/manage/sensors/:id", ManageLive.Sensors.Show, :show
      live "/manage/sensors/:id/edit", ManageLive.Sensors.Form, :edit

      # Measurement Types
      live "/manage/measurement_types", ManageLive.MeasurementTypes.Index, :index
      live "/manage/measurement_types/new", ManageLive.MeasurementTypes.Form, :new
      live "/manage/measurement_types/:id/edit", ManageLive.MeasurementTypes.Form, :edit

      # Measurements Editor (admin-only)
      live "/manage/measurements/editor", ManageLive.MeasurementsEditor, :index

      # Faults (admin-only)
      live "/manage/faults", ManageLive.Faults.Index, :index

      # Webcam shot purge (admin-only)
      live "/manage/webcam-shots/purge", ManageLive.WebcamShots.Purge, :index

      # Blog content (admin-only)
      live "/manage/blogcontent", ManageLive.BlogContent.Index, :index

      # Blog pages (admin-only)
      live "/manage/blog_pages", ManageLive.BlogPages.Index, :index
      live "/manage/blog_pages/new", ManageLive.BlogPages.Form, :new
      live "/manage/blog_pages/:id/edit", ManageLive.BlogPages.Form, :edit

      # User management
      live "/manage/profile", ManageLive.Users.Profile, :profile
      live "/manage/users", ManageLive.Users.Index, :index
      live "/manage/users/new", ManageLive.Users.Form, :new
      live "/manage/users/:id/edit", ManageLive.Users.Form, :edit
    end

    auth_routes AuthController, Voria2.Accounts.User, path: "/auth"
    sign_out_route AuthController

    sign_in_route auth_routes_prefix: "/auth",
                  on_mount: [{Voria2Web.LiveUserAuth, :live_no_user}],
                  overrides: [
                    Voria2Web.AuthOverrides,
                    Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                  ]

    get "/manage/blogcontent/files/*path", BlogContentController, :show

    confirm_route Voria2.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      overrides: [Voria2Web.AuthOverrides, Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI]

    magic_sign_in_route(Voria2.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      overrides: [Voria2Web.AuthOverrides, Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI]
    )
  end

  if Application.compile_env(:voria2, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: Voria2Web.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
