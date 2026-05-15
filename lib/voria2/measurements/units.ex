defmodule Voria2.Measurements.Units do
  @moduledoc """
  Unit conversion and metadata for weather measurements.

  All measurements are stored in system units. This module converts them to
  user-preferred units for display purposes.

  System units:
    - temperature: :celsius (°C)
    - wind: :ms (m/s)
    - pressure: :hpa (hPa)
    - rain: :mm (mm)
    - humidity: :percent (%)
  """

  @doc """
  Convert a *difference* value (e.g. 24h temperature change) from the system
  storage unit to a user-preferred unit.

  Difference conversions skip additive offsets — e.g. ΔC→ΔF multiplies by 9/5
  but does NOT add 32.
  """
  # Temperature differences
  def convert_delta(:temperature, v, :celsius, :celsius), do: v
  def convert_delta(:temperature, v, :celsius, :fahrenheit), do: v * 9 / 5
  def convert_delta(:temperature, v, :celsius, :kelvin), do: v

  @doc "Convert a value from the system storage unit to a user-preferred unit."
  # Temperature (stored in °C)
  def convert(:temperature, v, :celsius, :celsius), do: v
  def convert(:temperature, v, :celsius, :fahrenheit), do: v * 9 / 5 + 32
  def convert(:temperature, v, :celsius, :kelvin), do: v + 273.15

  # Wind speed (stored in m/s)
  def convert(:wind, v, :ms, :ms), do: v
  def convert(:wind, v, :ms, :kmh), do: v * 3.6
  def convert(:wind, v, :ms, :mph), do: v * 2.23694
  def convert(:wind, v, :ms, :knots), do: v * 1.94384

  # Pressure (stored in hPa)
  def convert(:pressure, v, :hpa, :hpa), do: v
  def convert(:pressure, v, :hpa, :inhg), do: v * 0.02953
  def convert(:pressure, v, :hpa, :mmhg), do: v * 0.75006

  # Rain (stored in mm)
  def convert(:rain, v, :mm, :mm), do: v
  def convert(:rain, v, :mm, :in), do: v * 0.03937

  # Humidity — no alternative unit
  def convert(:humidity, v, :percent, :percent), do: v

  @doc "Display label for a unit atom."
  def label(:celsius), do: "°C"
  def label(:fahrenheit), do: "°F"
  def label(:kelvin), do: "K"
  def label(:ms), do: "m/s"
  def label(:kmh), do: "km/h"
  def label(:mph), do: "mph"
  def label(:knots), do: "knots"
  def label(:hpa), do: "hPa"
  def label(:inhg), do: "inHg"
  def label(:mmhg), do: "mmHg"
  def label(:mm), do: "mm"
  def label(:in), do: "in"
  def label(:percent), do: "%"

  @doc "All supported unit options for a measurement type slug."
  def options(:temperature), do: [:celsius, :fahrenheit, :kelvin]
  def options(:wind), do: [:ms, :kmh, :mph, :knots]
  def options(:pressure), do: [:hpa, :inhg, :mmhg]
  def options(:rain), do: [:mm, :in]
  def options(:humidity), do: [:percent]

  @doc "The system storage unit for a measurement type slug."
  def system_unit(:temperature), do: :celsius
  def system_unit(:wind), do: :ms
  def system_unit(:pressure), do: :hpa
  def system_unit(:rain), do: :mm
  def system_unit(:humidity), do: :percent
end
