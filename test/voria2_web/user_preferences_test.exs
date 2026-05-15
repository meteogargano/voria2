defmodule Voria2Web.UserPreferencesTest do
  use ExUnit.Case, async: true

  alias Voria2Web.UserPreferences

  describe "defaults" do
    test "nil deserializes to all defaults" do
      prefs = UserPreferences.deserialize(nil)
      assert prefs.temperature_unit == :celsius
      assert prefs.wind_unit == :kmh
      assert prefs.pressure_unit == :hpa
      assert prefs.rain_unit == :mm
      assert prefs.language == :it
    end
  end

  describe "serialize/deserialize roundtrip" do
    test "roundtrips default struct" do
      prefs = %UserPreferences{}
      assert UserPreferences.deserialize(UserPreferences.serialize(prefs)) == prefs
    end

    test "roundtrips custom values" do
      prefs = %UserPreferences{
        temperature_unit: :fahrenheit,
        wind_unit: :knots,
        pressure_unit: :inhg,
        rain_unit: :in,
        language: :it
      }

      assert UserPreferences.deserialize(UserPreferences.serialize(prefs)) == prefs
    end
  end

  describe "deserialize/1 with invalid or unknown values" do
    test "unknown temperature unit falls back to celsius" do
      prefs = UserPreferences.deserialize(%{"t" => "rankine"})
      assert prefs.temperature_unit == :celsius
    end

    test "unknown wind unit falls back to ms" do
      prefs = UserPreferences.deserialize(%{"w" => "warp"})
      assert prefs.wind_unit == :ms
    end

    test "nil values fall back to defaults" do
      prefs = UserPreferences.deserialize(%{"t" => nil, "w" => nil})
      assert prefs.temperature_unit == :celsius
      assert prefs.wind_unit == :ms
    end
  end

  describe "from_session/1" do
    test "returns defaults when key missing" do
      assert UserPreferences.from_session(%{}) == %UserPreferences{}
    end

    test "returns defaults when key is nil" do
      assert UserPreferences.from_session(%{"user_preferences" => nil}) == %UserPreferences{}
    end

    test "deserializes stored map" do
      prefs = %UserPreferences{temperature_unit: :kelvin}
      session = %{"user_preferences" => UserPreferences.serialize(prefs)}
      assert UserPreferences.from_session(session).temperature_unit == :kelvin
    end
  end

  describe "unit_for/2" do
    test "returns correct units for each type" do
      prefs = %UserPreferences{
        temperature_unit: :fahrenheit,
        wind_unit: :mph,
        pressure_unit: :mmhg,
        rain_unit: :in
      }

      assert UserPreferences.unit_for(prefs, :temperature) == :fahrenheit
      assert UserPreferences.unit_for(prefs, :wind) == :mph
      assert UserPreferences.unit_for(prefs, :pressure) == :mmhg
      assert UserPreferences.unit_for(prefs, :rain) == :in
      assert UserPreferences.unit_for(prefs, :humidity) == :percent
    end
  end
end
