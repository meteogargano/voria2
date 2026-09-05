# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :ash,
  allow_forbidden_field_for_relationships_by_default?: true,
  include_embedded_source_by_default?: false,
  show_keysets_for_all_actions?: false,
  default_page_type: :keyset,
  policies: [no_filter_static_forbidden_reads?: false],
  keep_read_action_loads_when_loading?: false,
  default_actions_require_atomic?: true,
  read_action_after_action_hooks_in_order?: true,
  bulk_actions_default_to_errors?: true,
  transaction_rollback_on_error?: true,
  known_types: [AshPostgres.Timestamptz, AshPostgres.TimestamptzUsec]

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :admin,
        :authentication,
        :token,
        :user_identity,
        :postgres,
        :resource,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [
      section_order: [:admin, :resources, :policies, :authorization, :domain, :execution]
    ]
  ]

config :voria2,
  ecto_repos: [Voria2.Repo],
  generators: [timestamp_type: :utc_datetime],
  ash_domains: [Voria2.Accounts, Voria2.Network, Voria2.Measurements, Voria2.Blog],
  registration_enabled: false,
  dailylog_in_local: false,
  dailylog_wind_in_kmh: false,
  storage_adapter: Voria2.Storage.R2,
  storage_bucket: "voria2-media",
  storage_public_endpoint: nil,
  max_webcam_upload_bytes: 5 * 1024 * 1024,
  fault_staleness_threshold_s: 900,
  fault_check_interval_ms: 60_000

config :elixir, :time_zone_database, TimeZoneInfo.TimeZoneDatabase

# Configure the endpoint
config :voria2, Voria2Web.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: Voria2Web.ErrorHTML, json: Voria2Web.ErrorJSON],
    root_layout: {Voria2Web.Layouts, :root},
    layout: false
  ],
  pubsub_server: Voria2.PubSub,
  live_view: [signing_salt: "Jv4b+TW3"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :voria2, Voria2.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  voria2: [
    args:
      ~w(js/app.js js/maplibre_worker.js --bundle --format=esm --splitting --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  voria2: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
