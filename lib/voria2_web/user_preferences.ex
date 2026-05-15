defmodule Voria2Web.UserPreferences do
  @moduledoc """
  User display preferences stored in the Phoenix session (signed cookie).

  Preferences are display-only and require no database storage. They travel with
  the user's session cookie and fall back gracefully to defaults when absent or
  tampered with.

  Supported preferences:
    - temperature_unit: :celsius | :fahrenheit | :kelvin (default: :celsius)
    - wind_unit: :ms | :kmh | :mph | :knots (default: :ms)
    - pressure_unit: :hpa | :inhg | :mmhg (default: :hpa)
    - rain_unit: :mm | :in (default: :mm)
    - language: :en | :it (default: :en)
  """

  defstruct temperature_unit: :celsius,
            wind_unit: :kmh,
            pressure_unit: :hpa,
            rain_unit: :mm,
            language: :it

  @valid_temperature [:celsius, :fahrenheit, :kelvin]
  @valid_wind [:ms, :kmh, :mph, :knots]
  @valid_pressure [:hpa, :inhg, :mmhg]
  @valid_rain [:mm, :in]
  @valid_language [:en, :it]

  @doc "Serialize to a compact map suitable for storing in the session."
  def serialize(%__MODULE__{} = prefs) do
    %{
      "t" => Atom.to_string(prefs.temperature_unit),
      "w" => Atom.to_string(prefs.wind_unit),
      "p" => Atom.to_string(prefs.pressure_unit),
      "r" => Atom.to_string(prefs.rain_unit),
      "l" => Atom.to_string(prefs.language)
    }
  end

  @doc "Deserialize from a session map. Returns defaults for nil or unknown values."
  def deserialize(nil), do: %__MODULE__{}

  def deserialize(map) when is_map(map) do
    %__MODULE__{
      temperature_unit: parse(:temperature, map["t"]),
      wind_unit: parse(:wind, map["w"]),
      pressure_unit: parse(:pressure, map["p"]),
      rain_unit: parse(:rain, map["r"]),
      language: parse(:language, map["l"])
    }
  end

  @doc "Build preferences from a LiveView session map."
  def from_session(session), do: deserialize(session["user_preferences"])

  @doc "Build preferences from form params (full field names)."
  def from_params(params) when is_map(params) do
    %__MODULE__{
      temperature_unit: parse(:temperature, params["temperature_unit"]),
      wind_unit: parse(:wind, params["wind_unit"]),
      pressure_unit: parse(:pressure, params["pressure_unit"]),
      rain_unit: parse(:rain, params["rain_unit"]),
      language: parse(:language, params["language"])
    }
  end

  @doc "Return the user's preferred unit for a measurement type slug."
  def unit_for(prefs, :temperature), do: prefs.temperature_unit
  def unit_for(prefs, :wind), do: prefs.wind_unit
  def unit_for(prefs, :pressure), do: prefs.pressure_unit
  def unit_for(prefs, :rain), do: prefs.rain_unit
  def unit_for(_prefs, :humidity), do: :percent

  # -- Private helpers -------------------------------------------------------

  defp parse(:temperature, v), do: to_atom_in(v, @valid_temperature, :celsius)
  defp parse(:wind, v), do: to_atom_in(v, @valid_wind, :ms)
  defp parse(:pressure, v), do: to_atom_in(v, @valid_pressure, :hpa)
  defp parse(:rain, v), do: to_atom_in(v, @valid_rain, :mm)
  defp parse(:language, v), do: to_atom_in(v, @valid_language, :en)

  defp to_atom_in(v, valid, default) do
    atom = if is_binary(v), do: String.to_existing_atom(v), else: default
    if atom in valid, do: atom, else: default
  rescue
    ArgumentError -> default
  end
end
