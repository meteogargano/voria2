defmodule Voria2.MeasurementsHelpers do
  @moduledoc "Factory helpers for measurements-related tests."

  def create_user(opts \\ []) do
    n = System.unique_integer([:positive])

    Ash.Seed.seed!(Voria2.Accounts.User, %{
      email: Keyword.get(opts, :email, "user#{n}@test.com"),
      name: Keyword.get(opts, :name, "User #{n}"),
      hashed_password: "x",
      admin: Keyword.get(opts, :admin, false),
      confirmed_at: DateTime.utc_now()
    })
  end

  def create_admin(opts \\ []) do
    create_user(Keyword.put(opts, :admin, true))
  end

  def create_installation(user, opts \\ []) do
    n = System.unique_integer([:positive])

    Voria2.Network.create_installation!(
      %{
        user_id: user.id,
        name: Keyword.get(opts, :name, "Installation #{n}"),
        latitude: Keyword.get(opts, :latitude, 45.0),
        longitude: Keyword.get(opts, :longitude, 9.0)
      },
      authorize?: false
    )
  end

  def create_station(installation, opts \\ []) do
    n = System.unique_integer([:positive])

    Voria2.Network.create_station!(
      %{
        installation_id: installation.id,
        name: Keyword.get(opts, :name, "Station #{n}"),
        slug: Keyword.get(opts, :slug, "station-#{n}")
      },
      authorize?: false
    )
  end

  def create_measurement_type(opts \\ []) do
    n = System.unique_integer([:positive])

    Ash.Seed.seed!(Voria2.Measurements.MeasurementType, %{
      name: Keyword.get(opts, :name, "Type #{n}"),
      slug: Keyword.get(opts, :slug, "type-#{n}"),
      storage_type: Keyword.get(opts, :storage_type, :scalar),
      user_id: Keyword.get(opts, :user_id)
    })
  end

  def create_sensor_installation(station, measurement_type, opts \\ []) do
    Voria2.Measurements.create_sensor_installation!(
      %{
        station_id: station.id,
        measurement_type_id: measurement_type.id,
        installed_at: Keyword.get(opts, :installed_at, Date.utc_today()),
        rain_mode: Keyword.get(opts, :rain_mode)
      },
      authorize?: false
    )
  end

  def record_temperature!(sensor, value, measured_at \\ nil) do
    at = measured_at || DateTime.utc_now()

    Voria2.Measurements.record_temperature!(
      %{sensor_installation_id: sensor.id, measured_at: at, value: value},
      authorize?: false
    )
  end

  def record_humidity!(sensor, value, measured_at \\ nil) do
    at = measured_at || DateTime.utc_now()

    Voria2.Measurements.record_humidity!(
      %{sensor_installation_id: sensor.id, measured_at: at, value: value},
      authorize?: false
    )
  end

  def record_pressure!(sensor, value, measured_at \\ nil) do
    at = measured_at || DateTime.utc_now()

    Voria2.Measurements.record_pressure!(
      %{sensor_installation_id: sensor.id, measured_at: at, value: value},
      authorize?: false
    )
  end

  def record_wind!(sensor, u, v, opts \\ []) do
    at = Keyword.get(opts, :measured_at, DateTime.utc_now())
    gust = Keyword.get(opts, :gust)

    Voria2.Measurements.record_wind!(
      %{sensor_installation_id: sensor.id, measured_at: at, u: u, v: v, gust: gust},
      authorize?: false
    )
  end

  def record_rain_interval!(sensor, interval_mm, measured_at \\ nil) do
    at = measured_at || DateTime.utc_now()

    Voria2.Measurements.record_rain_interval!(
      %{sensor_installation_id: sensor.id, measured_at: at, interval_mm: interval_mm},
      authorize?: false
    )
  end

  def create_webcam(installation, opts \\ []) do
    n = System.unique_integer([:positive])

    Voria2.Network.create_webcam!(
      %{
        installation_id: installation.id,
        name: Keyword.get(opts, :name, "Webcam #{n}"),
        slug: Keyword.get(opts, :slug, "webcam-#{n}")
      },
      authorize?: false
    )
  end

  def generate_webcam_api_key(webcam, user) do
    {:ok, api_key} = Voria2.Network.generate_webcam_api_key(webcam.id, actor: user)
    api_key
  end

  def create_auto_fault_for_station(station, opts \\ []) do
    detected_at = Keyword.get(opts, :detected_at, DateTime.utc_now())

    Voria2.Network.detect_offline_fault!(
      %{station_id: station.id, detected_at: detected_at},
      authorize?: false
    )
  end

  def create_auto_fault_for_webcam(webcam, opts \\ []) do
    detected_at = Keyword.get(opts, :detected_at, DateTime.utc_now())

    Voria2.Network.detect_offline_fault!(
      %{webcam_id: webcam.id, detected_at: detected_at},
      authorize?: false
    )
  end

  def create_auto_fault_for_sensor(sensor, opts \\ []) do
    detected_at = Keyword.get(opts, :detected_at, DateTime.utc_now())

    Voria2.Network.detect_offline_fault!(
      %{sensor_installation_id: sensor.id, detected_at: detected_at},
      authorize?: false
    )
  end

  def create_manual_fault_for_station(station, reason, opts \\ []) do
    detected_at = Keyword.get(opts, :detected_at, DateTime.utc_now())

    Voria2.Network.report_manual_fault!(
      %{station_id: station.id, reason: reason, detected_at: detected_at},
      authorize?: false
    )
  end

  def create_manual_fault_for_webcam(webcam, reason, opts \\ []) do
    detected_at = Keyword.get(opts, :detected_at, DateTime.utc_now())

    Voria2.Network.report_manual_fault!(
      %{webcam_id: webcam.id, reason: reason, detected_at: detected_at},
      authorize?: false
    )
  end

  def create_manual_fault_for_sensor(sensor, reason, opts \\ []) do
    detected_at = Keyword.get(opts, :detected_at, DateTime.utc_now())

    Voria2.Network.report_manual_fault!(
      %{sensor_installation_id: sensor.id, reason: reason, detected_at: detected_at},
      authorize?: false
    )
  end

  def create_blog_category(opts \\ []) do
    n = System.unique_integer([:positive])

    Ash.Seed.seed!(Voria2.Blog.Category, %{
      name: Keyword.get(opts, :name, "Category #{n}")
    })
  end

  def create_blog_article(opts \\ []) do
    n = System.unique_integer([:positive])

    defaults = %{
      title: Keyword.get(opts, :title, "Article #{n}"),
      slug: Keyword.get(opts, :slug, "article-#{n}"),
      body: Keyword.get(opts, :body, "<p>Body #{n}</p>"),
      cover_image_url: Keyword.get(opts, :cover_image_url),
      published: Keyword.get(opts, :published, false)
    }

    category_ids = Keyword.get(opts, :category_ids, [])

    Voria2.Blog.create_article!(
      Map.put(defaults, :category_ids, category_ids),
      authorize?: false,
      actor: Keyword.get(opts, :actor)
    )
  end
end
