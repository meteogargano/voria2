defmodule Voria2.Measurements.UnitsTest do
  use ExUnit.Case, async: true

  alias Voria2.Measurements.Units

  describe "temperature conversions" do
    test "celsius to celsius is identity" do
      assert Units.convert(:temperature, 0.0, :celsius, :celsius) == 0.0
    end

    test "0°C = 32°F" do
      assert_in_delta Units.convert(:temperature, 0.0, :celsius, :fahrenheit), 32.0, 0.001
    end

    test "100°C = 212°F" do
      assert_in_delta Units.convert(:temperature, 100.0, :celsius, :fahrenheit), 212.0, 0.001
    end

    test "-40°C = -40°F" do
      assert_in_delta Units.convert(:temperature, -40.0, :celsius, :fahrenheit), -40.0, 0.001
    end

    test "0°C = 273.15 K" do
      assert_in_delta Units.convert(:temperature, 0.0, :celsius, :kelvin), 273.15, 0.001
    end
  end

  describe "wind speed conversions" do
    test "m/s identity" do
      assert Units.convert(:wind, 10.0, :ms, :ms) == 10.0
    end

    test "1 m/s = 3.6 km/h" do
      assert_in_delta Units.convert(:wind, 1.0, :ms, :kmh), 3.6, 0.001
    end

    test "1 m/s ≈ 2.237 mph" do
      assert_in_delta Units.convert(:wind, 1.0, :ms, :mph), 2.23694, 0.001
    end

    test "1 m/s ≈ 1.944 knots" do
      assert_in_delta Units.convert(:wind, 1.0, :ms, :knots), 1.94384, 0.001
    end
  end

  describe "pressure conversions" do
    test "hPa identity" do
      assert Units.convert(:pressure, 1013.25, :hpa, :hpa) == 1013.25
    end

    test "1013.25 hPa ≈ 29.92 inHg (standard atmosphere)" do
      assert_in_delta Units.convert(:pressure, 1013.25, :hpa, :inhg), 29.921, 0.01
    end

    test "1 hPa ≈ 0.75006 mmHg" do
      assert_in_delta Units.convert(:pressure, 1.0, :hpa, :mmhg), 0.75006, 0.0001
    end
  end

  describe "rain conversions" do
    test "mm identity" do
      assert Units.convert(:rain, 25.4, :mm, :mm) == 25.4
    end

    test "25.4 mm = 1 inch" do
      assert_in_delta Units.convert(:rain, 25.4, :mm, :in), 1.0, 0.001
    end
  end

  describe "humidity" do
    test "percent identity" do
      assert Units.convert(:humidity, 65.0, :percent, :percent) == 65.0
    end
  end

  describe "label/1" do
    test "returns correct labels" do
      assert Units.label(:celsius) == "°C"
      assert Units.label(:fahrenheit) == "°F"
      assert Units.label(:kelvin) == "K"
      assert Units.label(:ms) == "m/s"
      assert Units.label(:kmh) == "km/h"
      assert Units.label(:mph) == "mph"
      assert Units.label(:knots) == "knots"
      assert Units.label(:hpa) == "hPa"
      assert Units.label(:inhg) == "inHg"
      assert Units.label(:mmhg) == "mmHg"
      assert Units.label(:mm) == "mm"
      assert Units.label(:in) == "in"
      assert Units.label(:percent) == "%"
    end
  end

  describe "options/1 and system_unit/1" do
    test "options lists include system unit as first element" do
      for type <- [:temperature, :wind, :pressure, :rain, :humidity] do
        sys = Units.system_unit(type)
        assert sys in Units.options(type), "system unit #{sys} not in options for #{type}"
      end
    end
  end
end
