defmodule Voria2.Seeds do
  @moduledoc false

  require Ash.Query

  alias Voria2.Accounts
  alias Voria2.Measurements
  alias Voria2.Accounts.User

  @system_types [
    %{
      name: "Temperature",
      slug: "temperature",
      unit: "°C",
      storage_type: :scalar,
      description: "Air temperature"
    },
    %{
      name: "Humidity",
      slug: "humidity",
      unit: "%",
      storage_type: :scalar,
      description: "Relative humidity"
    },
    %{
      name: "Pressure",
      slug: "pressure",
      unit: "hPa",
      storage_type: :scalar,
      description: "Atmospheric pressure"
    },
    %{
      name: "Wind",
      slug: "wind",
      unit: "m/s",
      storage_type: :wind,
      description: "Wind speed and direction (u/v components)"
    },
    %{
      name: "Rain",
      slug: "rain",
      unit: "mm",
      storage_type: :rain,
      description: "Precipitation accumulation"
    }
  ]

  def run(opts \\ []) do
    seed_measurement_types()
    seed_admin(opts)
  end

  defp seed_measurement_types do
    for attrs <- @system_types do
      case Measurements.get_measurement_type_by_slug(attrs.slug, authorize?: false) do
        {:ok, _existing} ->
          :ok

        {:error, _} ->
          Measurements.create_measurement_type!(attrs, authorize?: false)
          IO.puts("Created measurement type: #{attrs.name}")
      end
    end
  end

  defp seed_admin(opts) do
    admin_email = System.get_env("ADMIN_EMAIL", "admin@localhost")
    admin_name = System.get_env("ADMIN_NAME", "Admin")
    admin_password = System.get_env("ADMIN_PASSWORD")
    require_admin_password? = Keyword.get(opts, :require_admin_password?, true)

    case any_admin_user() do
      {:ok, nil} ->
        maybe_seed_configured_admin(
          admin_email,
          admin_name,
          admin_password,
          require_admin_password?
        )

      {:ok, _admin} ->
        IO.puts("Skipping admin seed: an admin user already exists")
    end
  end

  defp any_admin_user do
    User
    |> Ash.Query.filter(admin == true)
    |> Ash.read_one(authorize?: false)
  end

  defp maybe_seed_configured_admin(
         admin_email,
         admin_name,
         admin_password,
         require_admin_password?
       ) do
    case Accounts.get_by_email(admin_email, authorize?: false) do
      {:ok, existing} ->
        ensure_admin_user(existing, admin_email)

      {:error, _} ->
        maybe_create_admin(admin_email, admin_name, admin_password, require_admin_password?)
    end
  end

  defp ensure_admin_user(user, admin_email) do
    attrs = %{}
    attrs = if user.admin, do: attrs, else: Map.put(attrs, :admin, true)

    attrs =
      if user.confirmed_at, do: attrs, else: Map.put(attrs, :confirmed_at, DateTime.utc_now())

    if attrs == %{} do
      IO.puts("Admin user already exists: #{admin_email}")
    else
      Ash.update!(user, attrs, authorize?: false)
      IO.puts("Updated admin user: #{admin_email}")
    end
  end

  defp maybe_create_admin(_admin_email, _admin_name, nil, true) do
    raise "ADMIN_PASSWORD env var required for seeding admin"
  end

  defp maybe_create_admin(admin_email, _admin_name, nil, false) do
    IO.puts("Skipping admin seed for #{admin_email}: ADMIN_PASSWORD is not set")
  end

  defp maybe_create_admin(admin_email, admin_name, admin_password, _require_admin_password?) do
    Ash.Seed.seed!(User, %{
      email: admin_email,
      name: admin_name,
      hashed_password: Bcrypt.hash_pwd_salt(admin_password),
      admin: true,
      confirmed_at: DateTime.utc_now()
    })

    IO.puts("Created admin user: #{admin_email}")
  end
end
