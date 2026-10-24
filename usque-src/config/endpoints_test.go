package config

import (
	"net"
	"testing"
)

func TestSelectHTTP2EndpointDefaultsAndOverrides(t *testing.T) {
	original := AppConfig
	t.Cleanup(func() { AppConfig = original })

	AppConfig = Config{EndpointH2V4: "162.159.198.1"}
	endpoint, err := SelectEndpointFromConfig(true, false, 443)
	if err != nil {
		t.Fatalf("default HTTP/2 endpoint: %v", err)
	}
	assertTCPEndpoint(t, endpoint, "162.159.198.1:443")

	OverrideHTTP2Endpoints("162.159.197.2", "2606:4700:102::2")
	endpoint, err = SelectEndpointFromConfig(true, true, 8443)
	if err != nil {
		t.Fatalf("overridden HTTP/2 IPv6 endpoint: %v", err)
	}
	assertTCPEndpoint(t, endpoint, "[2606:4700:102::2]:8443")
}

func TestSelectHTTP2IPv6RequiresEndpoint(t *testing.T) {
	original := AppConfig
	t.Cleanup(func() { AppConfig = original })

	AppConfig = Config{}
	_, err := SelectEndpointFromConfig(true, true, 443)
	if err == nil {
		t.Fatal("expected an error when endpoint_h2_v6 is empty")
	}
}

func assertTCPEndpoint(t *testing.T, endpoint net.Addr, want string) {
	t.Helper()

	if endpoint == nil {
		t.Fatal("endpoint is nil")
	}
	if endpoint.Network() != "tcp" {
		t.Fatalf("network = %q, want tcp", endpoint.Network())
	}
	if endpoint.String() != want {
		t.Fatalf("endpoint = %q, want %q", endpoint.String(), want)
	}
}
