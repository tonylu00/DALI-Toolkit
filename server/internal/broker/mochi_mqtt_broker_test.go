package broker

import "testing"

func TestNormalizeDeviceKey(t *testing.T) {
	cases := []struct {
		in  string
		out string
	}{
		{"aa:bb:cc:dd:ee:ff", "AABBCCDDEEFF"},
		{"aa-bb-cc-dd-ee-ff", "AABBCCDDEEFF"},
		{"aabb.ccdd.eeff", "AABBCCDDEEFF"},
		{"AABBCCDDEEFF", "AABBCCDDEEFF"},
		{"notamac", "notamac"},
	}
	for _, c := range cases {
		if got := normalizeDeviceKey(c.in); got != c.out {
			t.Fatalf("normalizeDeviceKey(%q) = %q; want %q", c.in, got, c.out)
		}
	}
}

func TestEqualsDeviceID(t *testing.T) {
	if !equalsDeviceID("aa:bb:cc:dd:ee:ff", "AABBCCDDEEFF") {
		t.Fatal("expected MACs to be equal after normalization")
	}
	if equalsDeviceID("AABBCCDDEEFF", "ZZZ") {
		t.Fatal("expected different IDs to not be equal")
	}
}

func TestParseDeviceTopic(t *testing.T) {
	id, kind := parseDeviceTopic("devices/aa:bb:cc:dd:ee:ff/up")
	if id != "AABBCCDDEEFF" || kind != "up" {
		t.Fatalf("parseDeviceTopic unexpected: id=%q kind=%q", id, kind)
	}

	id, kind = parseDeviceTopic("devices/AABBCCDDEEFF/status")
	if id != "AABBCCDDEEFF" || kind != "status" {
		t.Fatalf("parseDeviceTopic unexpected: id=%q kind=%q", id, kind)
	}

	id, kind = parseDeviceTopic("bad/topic")
	if id != "" || kind != "" {
		t.Fatalf("expected empty results for invalid topic, got id=%q kind=%q", id, kind)
	}
}
