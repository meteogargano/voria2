import Config
config :voria2, token_signing_secret: "a8ynnR8O0pfQ2JheLNagRkr+y8FUEK+g"
config :voria2, storage_adapter: Voria2.Storage.Stub
config :voria2, fault_staleness_threshold_s: 5, fault_check_interval_ms: :timer.hours(24)
config :voria2, start_background_processes?: false
config :bcrypt_elixir, log_rounds: 1
config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :voria2, Voria2.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "voria2_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :voria2, Voria2Web.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "gj9d7Jp4Mfnxtjig8FtkCwYBRc1QtFUANUhFS8b7T/ymlxm99WJVrqldWRZBxpzT",
  server: false

# In test we don't send emails
config :voria2, Voria2.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
