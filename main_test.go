package main

import (
	"encoding/json"
	"testing"
)

func TestBuildCLIArgs_DirOnly(t *testing.T) {
	args := buildCLIArgs("/some/dir", map[string]any{})
	if len(args) != 1 || args[0] != "/some/dir" {
		t.Fatalf("expected [/some/dir], got %v", args)
	}
}

func TestBuildCLIArgs_AllOptions(t *testing.T) {
	input := map[string]any{
		"depth":            float64(3),
		"include_ext":      []any{".go", ".zig"},
		"exclude_ext":      []any{".tmp"},
		"exclude_patterns": []any{"vendor", "node_modules"},
		"show_hidden":      true,
		"show_size":        true,
		"show_modified":    true,
		"follow_symlinks":  true,
		"force":            true,
		"performance":      true,
		"output_file":      "/tmp/out.json",
		"token_limit":      float64(5000),
	}

	args := buildCLIArgs("/test", input)

	expected := map[string]string{
		"--depth":       "3",
		"--include-ext": ".go,.zig",
		"--exclude-ext": ".tmp",
		"--exclude":     "vendor,node_modules",
		"--hidden":      "",
		"--size":        "",
		"--modified":    "",
		"--follow-symlinks": "",
		"--force":       "",
		"--performance": "",
		"--output":      "/tmp/out.json",
		"--token-limit": "5000",
	}

	argMap := make(map[string]string)
	for i := 0; i < len(args)-1; i++ {
		if args[i][0] == '-' {
			// Check if next arg is a value or another flag
			if i+1 < len(args)-1 && args[i+1][0] != '-' {
				argMap[args[i]] = args[i+1]
				i++
			} else {
				argMap[args[i]] = ""
			}
		}
	}

	for flag, val := range expected {
		got, ok := argMap[flag]
		if !ok {
			t.Errorf("missing flag %s", flag)
			continue
		}
		if got != val {
			t.Errorf("flag %s: expected %q, got %q", flag, val, got)
		}
	}

	// Last arg should be dir
	if args[len(args)-1] != "/test" {
		t.Errorf("last arg should be dir, got %s", args[len(args)-1])
	}
}

func TestBuildCLIArgs_BoolFalse(t *testing.T) {
	input := map[string]any{
		"show_hidden":   false,
		"show_size":     false,
		"show_modified": false,
	}

	args := buildCLIArgs("/dir", input)

	found := map[string]bool{}
	for _, a := range args {
		found[a] = true
	}

	if !found["--no-hidden"] {
		t.Error("expected --no-hidden for show_hidden=false")
	}
	if !found["--no-size"] {
		t.Error("expected --no-size for show_size=false")
	}
	if !found["--no-modified"] {
		t.Error("expected --no-modified for show_modified=false")
	}
}

func TestToInt(t *testing.T) {
	tests := []struct {
		name string
		in   any
		want int
		ok   bool
	}{
		{"float64", float64(42), 42, true},
		{"int", int(7), 7, true},
		{"json.Number", json.Number("99"), 99, true},
		{"string", "bad", 0, false},
		{"nil", nil, 0, false},
		{"json.Number invalid", json.Number("abc"), 0, false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, ok := toInt(tt.in)
			if ok != tt.ok {
				t.Fatalf("ok: expected %v, got %v", tt.ok, ok)
			}
			if got != tt.want {
				t.Fatalf("value: expected %d, got %d", tt.want, got)
			}
		})
	}
}

func TestToStringSlice(t *testing.T) {
	tests := []struct {
		name string
		in   any
		want int
	}{
		{"valid", []any{"a", "b", "c"}, 3},
		{"mixed", []any{"a", 42, "b"}, 2},
		{"empty", []any{}, 0},
		{"not slice", "bad", 0},
		{"nil", nil, 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := toStringSlice(tt.in)
			if len(got) != tt.want {
				t.Fatalf("len: expected %d, got %d", tt.want, len(got))
			}
		})
	}
}

func TestSendResponse_JSON(t *testing.T) {
	resp := JSONRPCResponse{
		JSONRPC: "2.0",
		ID:      float64(1),
		Result:  map[string]string{"key": "value"},
	}

	data, err := json.Marshal(resp)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}

	var parsed map[string]any
	if err := json.Unmarshal(data, &parsed); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	if parsed["jsonrpc"] != "2.0" {
		t.Errorf("jsonrpc: expected 2.0, got %v", parsed["jsonrpc"])
	}
	if parsed["error"] != nil {
		t.Errorf("error should be nil, got %v", parsed["error"])
	}
}

func TestSendError_JSON(t *testing.T) {
	resp := JSONRPCResponse{
		JSONRPC: "2.0",
		ID:      float64(1),
		Error: &Error{
			Code:    -32602,
			Message: "Invalid params",
		},
	}

	data, err := json.Marshal(resp)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}

	var parsed map[string]any
	if err := json.Unmarshal(data, &parsed); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	errObj, ok := parsed["error"].(map[string]any)
	if !ok {
		t.Fatal("error field missing")
	}
	if errObj["code"].(float64) != -32602 {
		t.Errorf("error code: expected -32602, got %v", errObj["code"])
	}
}

func TestToolCallParams_Unmarshal(t *testing.T) {
	raw := `{"name":"stump","arguments":{"dir":"/tmp","depth":3}}`

	var params ToolCallParams
	if err := json.Unmarshal([]byte(raw), &params); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	if params.Name != "stump" {
		t.Errorf("name: expected stump, got %s", params.Name)
	}

	dir, ok := params.Arguments["dir"].(string)
	if !ok || dir != "/tmp" {
		t.Errorf("dir: expected /tmp, got %v", params.Arguments["dir"])
	}
}

func TestInitializeResult_JSON(t *testing.T) {
	result := InitializeResult{
		ProtocolVersion: "2024-11-05",
		ServerInfo: ServerInfo{
			Name:    "stump",
			Version: "1.0.0",
		},
		Capabilities: Capabilities{
			Tools: map[string]bool{"list": true, "call": true},
		},
	}

	data, err := json.Marshal(result)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}

	var parsed map[string]any
	if err := json.Unmarshal(data, &parsed); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	if parsed["protocolVersion"] != "2024-11-05" {
		t.Errorf("protocolVersion: expected 2024-11-05, got %v", parsed["protocolVersion"])
	}

	serverInfo := parsed["serverInfo"].(map[string]any)
	if serverInfo["name"] != "stump" {
		t.Errorf("serverInfo.name: expected stump, got %v", serverInfo["name"])
	}
}

func TestToolsListResult_JSON(t *testing.T) {
	result := ToolsListResult{
		Tools: []Tool{
			{
				Name:        "stump",
				Description: "Token-efficient directory tree visualization",
				InputSchema: InputSchema{
					Type: "object",
					Properties: map[string]Property{
						"dir": {Type: "string", Description: "Root directory to scan"},
					},
					Required: []string{"dir"},
				},
			},
		},
	}

	data, err := json.Marshal(result)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}

	var parsed map[string]any
	if err := json.Unmarshal(data, &parsed); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	tools := parsed["tools"].([]any)
	if len(tools) != 1 {
		t.Fatalf("expected 1 tool, got %d", len(tools))
	}

	tool := tools[0].(map[string]any)
	if tool["name"] != "stump" {
		t.Errorf("tool name: expected stump, got %v", tool["name"])
	}
}
