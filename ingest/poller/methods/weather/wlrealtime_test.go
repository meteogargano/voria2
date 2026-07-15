package weather

import (
	"math"
	"strings"
	"testing"
)

// makeWLRealtime builds a 44-field pipe-delimited realtime payload with sensible
// defaults, applying any per-offset overrides. A trailing "|" is appended to mimic
// real WeatherLink realtime.txt output.
func makeWLRealtime(overrides map[int]string) []byte {
	f := make([]string, 44)
	for i := range f {
		f[i] = "-"
	}
	f[2] = "30.1"    // temperature
	f[3] = "69"      // humidity
	f[5] = "14.5"    // wind avg
	f[7] = "46"      // wind direction
	f[10] = "1015.6" // pressure
	f[13] = "km/hr"  // wind unit
	f[14] = "°C"     // temperature unit
	f[15] = "hPa"    // pressure unit
	f[16] = "mm"     // rain unit
	f[20] = "390.2"  // yearly rain
	f[40] = "22.5"   // gust
	for i, v := range overrides {
		if i >= 0 && i < len(f) {
			f[i] = v
		}
	}
	return []byte(strings.Join(f, "|") + "|")
}

func floatEquals(a, b float64) bool {
	return math.Abs(a-b) < 1e-6
}

func TestParseWLRealtimeCelsiusAsIs(t *testing.T) {
	resp, err := parseWLRealtime(makeWLRealtime(nil))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !floatEquals(resp.TemperatureCelsius, 30.1) {
		t.Errorf("temperature: got %v, want 30.1", resp.TemperatureCelsius)
	}
	if !floatEquals(resp.HumidityPercent, 69) {
		t.Errorf("humidity: got %v, want 69", resp.HumidityPercent)
	}
	if !floatEquals(resp.PressureHPa, 1015.6) {
		t.Errorf("pressure: got %v, want 1015.6", resp.PressureHPa)
	}
	if !floatEquals(resp.WindDirectionDeg, 46) {
		t.Errorf("wind direction: got %v, want 46", resp.WindDirectionDeg)
	}
	if !floatEquals(resp.RainCumulativeMM, 390.2) {
		t.Errorf("rain: got %v, want 390.2", resp.RainCumulativeMM)
	}
	// km/hr -> kmh as-is, ms = /3.6, gust ms = /3.6
	if !floatEquals(resp.WindSpeedKmh, 14.5) {
		t.Errorf("wind kmh: got %v, want 14.5", resp.WindSpeedKmh)
	}
	if !floatEquals(resp.WindSpeedMs, 14.5/3.6) {
		t.Errorf("wind ms: got %v, want %v", resp.WindSpeedMs, 14.5/3.6)
	}
	if !floatEquals(resp.WindGustMs, 22.5/3.6) {
		t.Errorf("gust ms: got %v, want %v", resp.WindGustMs, 22.5/3.6)
	}
}

func TestParseWLRealtimeFahrenheitToCelsius(t *testing.T) {
	resp, err := parseWLRealtime(makeWLRealtime(map[int]string{
		2:  "86.0",
		14: "°F",
	}))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !floatEquals(resp.TemperatureCelsius, 30.0) {
		t.Errorf("temperature: got %v, want 30.0", resp.TemperatureCelsius)
	}
}

func TestParseWLRealtimeWindMetresPerSecond(t *testing.T) {
	resp, err := parseWLRealtime(makeWLRealtime(map[int]string{
		5:  "5.0",
		13: "m/s",
		40: "8.0",
	}))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !floatEquals(resp.WindSpeedMs, 5.0) {
		t.Errorf("wind ms: got %v, want 5.0", resp.WindSpeedMs)
	}
	if !floatEquals(resp.WindSpeedKmh, 18.0) {
		t.Errorf("wind kmh: got %v, want 18.0", resp.WindSpeedKmh)
	}
	if !floatEquals(resp.WindGustMs, 8.0) {
		t.Errorf("gust ms: got %v, want 8.0", resp.WindGustMs)
	}
}

func TestParseWLRealtimeWindKmHAlias(t *testing.T) {
	resp, err := parseWLRealtime(makeWLRealtime(map[int]string{
		13: "km/h",
	}))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !floatEquals(resp.WindSpeedKmh, 14.5) {
		t.Errorf("wind kmh: got %v, want 14.5", resp.WindSpeedKmh)
	}
	if !floatEquals(resp.WindSpeedMs, 14.5/3.6) {
		t.Errorf("wind ms: got %v, want %v", resp.WindSpeedMs, 14.5/3.6)
	}
}

func TestParseWLRealtimeMissingTempUnitTreatedAsCelsius(t *testing.T) {
	resp, err := parseWLRealtime(makeWLRealtime(map[int]string{
		14: "-",
	}))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !floatEquals(resp.TemperatureCelsius, 30.1) {
		t.Errorf("temperature: got %v, want 30.1 (treated as Celsius)", resp.TemperatureCelsius)
	}
}

func TestParseWLRealtimeTooFewFields(t *testing.T) {
	short := strings.Join(make([]string, 40), "|")
	_, err := parseWLRealtime([]byte(short))
	if err == nil {
		t.Fatal("expected error for too few fields, got nil")
	}
}

func TestParseWLRealtimeUnsupportedWindUnit(t *testing.T) {
	_, err := parseWLRealtime(makeWLRealtime(map[int]string{
		13: "mph",
	}))
	if err == nil {
		t.Fatal("expected error for unsupported wind unit, got nil")
	}
}
