defmodule Voria2.Repo.Migrations.SetupTimescaledbHypertables do
  @moduledoc """
  Converts measurement tables to TimescaleDB hypertables, sets up compression,
  and creates 15-minute continuous aggregates.
  """

  use Ecto.Migration

  @hypertables [
    {"temperature_measurements", "measured_at"},
    {"humidity_measurements", "measured_at"},
    {"pressure_measurements", "measured_at"},
    {"wind_measurements", "measured_at"},
    {"rain_measurements", "measured_at"},
    {"custom_measurements", "measured_at"}
  ]

  @aggregate_views [
    "custom_measurements_15m",
    "rain_15m",
    "wind_15m",
    "pressure_15m",
    "humidity_15m",
    "temperature_15m"
  ]

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE"

    # TimescaleDB requires the time column to be part of the primary key.
    # We drop the UUID-only PK and replace it with a composite (id, measured_at) PK.
    # Ash still addresses rows by :id (unique per row); the composite PK just satisfies
    # TimescaleDB's constraint requirement.
    for {table, time_col} <- @hypertables do
      execute "ALTER TABLE #{table} DROP CONSTRAINT #{table}_pkey"

      execute """
      ALTER TABLE #{table}
        ADD PRIMARY KEY (id, #{time_col})
      """
    end

    for {table, time_col} <- @hypertables do
      execute """
      SELECT create_hypertable(
        '#{table}',
        '#{time_col}',
        chunk_time_interval => INTERVAL '1 day',
        if_not_exists => TRUE
      )
      """
    end

    compress_opts =
      "timescaledb.compress, timescaledb.compress_segmentby = 'sensor_installation_id', timescaledb.compress_orderby = 'measured_at DESC'"

    for {table, _} <- @hypertables do
      execute "ALTER TABLE #{table} SET (#{compress_opts})"
    end

    for {table, _} <- @hypertables do
      execute """
      SELECT add_compression_policy('#{table}', INTERVAL '30 days', if_not_exists => TRUE)
      """
    end

    execute """
    CREATE MATERIALIZED VIEW temperature_15m
    WITH (timescaledb.continuous) AS
    SELECT
      time_bucket('15 minutes', measured_at) AS bucket,
      sensor_installation_id,
      AVG(value)  AS avg_value,
      MIN(value)  AS min_value,
      MAX(value)  AS max_value,
      COUNT(*)    AS sample_count
    FROM temperature_measurements
    GROUP BY bucket, sensor_installation_id
    WITH NO DATA
    """

    execute """
    SELECT add_continuous_aggregate_policy(
      'temperature_15m',
      start_offset => INTERVAL '2 hours',
      end_offset => INTERVAL '15 minutes',
      schedule_interval => INTERVAL '15 minutes',
      if_not_exists => TRUE
    )
    """

    execute """
    CREATE MATERIALIZED VIEW humidity_15m
    WITH (timescaledb.continuous) AS
    SELECT
      time_bucket('15 minutes', measured_at) AS bucket,
      sensor_installation_id,
      AVG(value)  AS avg_value,
      MIN(value)  AS min_value,
      MAX(value)  AS max_value,
      COUNT(*)    AS sample_count
    FROM humidity_measurements
    GROUP BY bucket, sensor_installation_id
    WITH NO DATA
    """

    execute """
    SELECT add_continuous_aggregate_policy(
      'humidity_15m',
      start_offset => INTERVAL '2 hours',
      end_offset => INTERVAL '15 minutes',
      schedule_interval => INTERVAL '15 minutes',
      if_not_exists => TRUE
    )
    """

    execute """
    CREATE MATERIALIZED VIEW pressure_15m
    WITH (timescaledb.continuous) AS
    SELECT
      time_bucket('15 minutes', measured_at) AS bucket,
      sensor_installation_id,
      AVG(value)  AS avg_value,
      MIN(value)  AS min_value,
      MAX(value)  AS max_value,
      COUNT(*)    AS sample_count
    FROM pressure_measurements
    GROUP BY bucket, sensor_installation_id
    WITH NO DATA
    """

    execute """
    SELECT add_continuous_aggregate_policy(
      'pressure_15m',
      start_offset => INTERVAL '2 hours',
      end_offset => INTERVAL '15 minutes',
      schedule_interval => INTERVAL '15 minutes',
      if_not_exists => TRUE
    )
    """

    execute """
    CREATE MATERIALIZED VIEW wind_15m
    WITH (timescaledb.continuous) AS
    SELECT
      time_bucket('15 minutes', measured_at) AS bucket,
      sensor_installation_id,
      AVG(u)      AS avg_u,
      AVG(v)      AS avg_v,
      AVG(SQRT(u * u + v * v)) AS avg_speed,
      MAX(SQRT(u * u + v * v)) AS max_speed,
      MAX(gust)   AS max_gust,
      COUNT(*)    AS sample_count
    FROM wind_measurements
    GROUP BY bucket, sensor_installation_id
    WITH NO DATA
    """

    execute """
    SELECT add_continuous_aggregate_policy(
      'wind_15m',
      start_offset => INTERVAL '2 hours',
      end_offset => INTERVAL '15 minutes',
      schedule_interval => INTERVAL '15 minutes',
      if_not_exists => TRUE
    )
    """

    execute """
    CREATE MATERIALIZED VIEW rain_15m
    WITH (timescaledb.continuous) AS
    SELECT
      time_bucket('15 minutes', measured_at) AS bucket,
      sensor_installation_id,
      SUM(interval_mm)  AS total_mm,
      COUNT(*)          AS sample_count
    FROM rain_measurements
    GROUP BY bucket, sensor_installation_id
    WITH NO DATA
    """

    execute """
    SELECT add_continuous_aggregate_policy(
      'rain_15m',
      start_offset => INTERVAL '2 hours',
      end_offset => INTERVAL '15 minutes',
      schedule_interval => INTERVAL '15 minutes',
      if_not_exists => TRUE
    )
    """

    execute """
    CREATE MATERIALIZED VIEW custom_measurements_15m
    WITH (timescaledb.continuous) AS
    SELECT
      time_bucket('15 minutes', measured_at) AS bucket,
      sensor_installation_id,
      measurement_type_id,
      AVG(value)  AS avg_value,
      MIN(value)  AS min_value,
      MAX(value)  AS max_value,
      COUNT(*)    AS sample_count
    FROM custom_measurements
    GROUP BY bucket, sensor_installation_id, measurement_type_id
    WITH NO DATA
    """

    execute """
    SELECT add_continuous_aggregate_policy(
      'custom_measurements_15m',
      start_offset => INTERVAL '2 hours',
      end_offset => INTERVAL '15 minutes',
      schedule_interval => INTERVAL '15 minutes',
      if_not_exists => TRUE
    )
    """
  end

  def down do
    for view <- @aggregate_views do
      execute "DROP MATERIALIZED VIEW IF EXISTS #{view} CASCADE"
    end

    for {table, _} <- @hypertables do
      execute "SELECT remove_compression_policy('#{table}', if_exists => TRUE)"
    end
  end
end
