package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"strconv"
	"strings"
	"sync"
	"syscall"
)

// JSON-RPC 2.0 types

type JSONRPCRequest struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      any             `json:"id"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
}

type JSONRPCResponse struct {
	JSONRPC string `json:"jsonrpc"`
	ID      any    `json:"id"`
	Result  any    `json:"result,omitempty"`
	Error   *Error `json:"error,omitempty"`
}

type Error struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

// MCP types

type InitializeResult struct {
	ProtocolVersion string       `json:"protocolVersion"`
	ServerInfo      ServerInfo   `json:"serverInfo"`
	Capabilities    Capabilities `json:"capabilities"`
}

type ServerInfo struct {
	Name    string `json:"name"`
	Version string `json:"version"`
}

type Capabilities struct {
	Tools map[string]bool `json:"tools"`
}

type ToolsListResult struct {
	Tools []Tool `json:"tools"`
}

type Tool struct {
	Name        string      `json:"name"`
	Description string      `json:"description"`
	InputSchema InputSchema `json:"inputSchema"`
}

type InputSchema struct {
	Type       string              `json:"type"`
	Properties map[string]Property `json:"properties"`
	Required   []string            `json:"required"`
}

type Property struct {
	Type        string `json:"type"`
	Description string `json:"description,omitempty"`
	Items       *Items `json:"items,omitempty"`
}

type Items struct {
	Type string `json:"type"`
}

type ToolCallParams struct {
	Name      string         `json:"name"`
	Arguments map[string]any `json:"arguments"`
}

type ToolCallResult struct {
	Content []ContentItem `json:"content"`
	IsError bool          `json:"isError,omitempty"`
}

type ContentItem struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

// stdout mutex for concurrent goroutine writes
var writeMu sync.Mutex

// wg tracks in-flight tools/call goroutines
var wg sync.WaitGroup

func sendResponse(id any, result any) {
	resp := JSONRPCResponse{
		JSONRPC: "2.0",
		ID:      id,
		Result:  result,
	}
	data, err := json.Marshal(resp)
	if err != nil {
		fmt.Fprintf(os.Stderr, "marshal response: %v\n", err)
		return
	}
	writeMu.Lock()
	fmt.Println(string(data))
	writeMu.Unlock()
}

func sendError(id any, code int, message string) {
	resp := JSONRPCResponse{
		JSONRPC: "2.0",
		ID:      id,
		Error: &Error{
			Code:    code,
			Message: message,
		},
	}
	data, _ := json.Marshal(resp)
	writeMu.Lock()
	fmt.Println(string(data))
	writeMu.Unlock()
}

func handleInitialize(req JSONRPCRequest) {
	sendResponse(req.ID, InitializeResult{
		ProtocolVersion: "2024-11-05",
		ServerInfo: ServerInfo{
			Name:    "stump",
			Version: "1.0.0",
		},
		Capabilities: Capabilities{
			Tools: map[string]bool{
				"list": true,
				"call": true,
			},
		},
	})
}

func handleToolsList(req JSONRPCRequest) {
	stringArray := &Items{Type: "string"}
	sendResponse(req.ID, ToolsListResult{
		Tools: []Tool{
			{
				Name:        "stump",
				Description: "Token-efficient directory tree visualization",
				InputSchema: InputSchema{
					Type: "object",
					Properties: map[string]Property{
						"dir":              {Type: "string", Description: "Root directory to scan"},
						"depth":            {Type: "integer", Description: "Max traversal depth (-1 for unlimited)"},
						"include_ext":      {Type: "array", Items: stringArray},
						"exclude_ext":      {Type: "array", Items: stringArray},
						"exclude_patterns": {Type: "array", Items: stringArray},
						"show_hidden":      {Type: "boolean"},
						"show_size":        {Type: "boolean"},
						"show_modified":    {Type: "boolean", Description: "Include modification timestamps"},
						"follow_symlinks":  {Type: "boolean"},
						"force":            {Type: "boolean"},
						"performance":      {Type: "boolean"},
						"output_file":      {Type: "string"},
						"token_limit":      {Type: "integer"},
					},
					Required: []string{"dir"},
				},
			},
		},
	})
}

func handleToolsCall(ctx context.Context, req JSONRPCRequest) {
	var params ToolCallParams
	if err := json.Unmarshal(req.Params, &params); err != nil {
		sendError(req.ID, -32602, "Invalid params")
		return
	}

	if params.Name != "stump" {
		sendError(req.ID, -32602, "Unknown tool: only 'stump' is available")
		return
	}

	args := params.Arguments

	dir, ok := args["dir"].(string)
	if !ok || dir == "" {
		sendError(req.ID, -32602, "Missing required 'dir' parameter")
		return
	}

	// Build CLI args for stump-core
	cliArgs := buildCLIArgs(dir, args)

	cmd := exec.CommandContext(ctx, "stump-core", cliArgs...)
	out, err := cmd.Output()
	if err != nil {
		// stump-core exits 1 for tool errors (large dir, token limit) but still
		// writes valid JSON to stdout. Only treat as a real failure if no output.
		if len(out) == 0 {
			sendError(req.ID, -32603, fmt.Sprintf("stump-core: %v", err))
			return
		}
	}

	// stump-core outputs JSON. Determine if it's an error response by checking
	// the exit code (err != nil means exit 1).
	isError := err != nil

	sendResponse(req.ID, ToolCallResult{
		Content: []ContentItem{
			{Type: "text", Text: string(out)},
		},
		IsError: isError,
	})
}

func buildCLIArgs(dir string, args map[string]any) []string {
	var cliArgs []string

	if v, ok := args["depth"]; ok {
		if depth, ok := toInt(v); ok {
			cliArgs = append(cliArgs, "--depth", strconv.Itoa(depth))
		}
	}

	if v, ok := args["include_ext"]; ok {
		if list := toStringSlice(v); len(list) > 0 {
			cliArgs = append(cliArgs, "--include-ext", strings.Join(list, ","))
		}
	}

	if v, ok := args["exclude_ext"]; ok {
		if list := toStringSlice(v); len(list) > 0 {
			cliArgs = append(cliArgs, "--exclude-ext", strings.Join(list, ","))
		}
	}

	if v, ok := args["exclude_patterns"]; ok {
		if list := toStringSlice(v); len(list) > 0 {
			cliArgs = append(cliArgs, "--exclude", strings.Join(list, ","))
		}
	}

	if v, ok := args["show_hidden"]; ok {
		if b, ok := v.(bool); ok {
			if b {
				cliArgs = append(cliArgs, "--hidden")
			} else {
				cliArgs = append(cliArgs, "--no-hidden")
			}
		}
	}

	if v, ok := args["show_size"]; ok {
		if b, ok := v.(bool); ok {
			if b {
				cliArgs = append(cliArgs, "--size")
			} else {
				cliArgs = append(cliArgs, "--no-size")
			}
		}
	}

	if v, ok := args["show_modified"]; ok {
		if b, ok := v.(bool); ok {
			if b {
				cliArgs = append(cliArgs, "--modified")
			} else {
				cliArgs = append(cliArgs, "--no-modified")
			}
		}
	}

	if v, ok := args["follow_symlinks"]; ok {
		if b, ok := v.(bool); ok && b {
			cliArgs = append(cliArgs, "--follow-symlinks")
		}
	}

	if v, ok := args["force"]; ok {
		if b, ok := v.(bool); ok && b {
			cliArgs = append(cliArgs, "--force")
		}
	}

	if v, ok := args["performance"]; ok {
		if b, ok := v.(bool); ok && b {
			cliArgs = append(cliArgs, "--performance")
		}
	}

	if v, ok := args["output_file"]; ok {
		if s, ok := v.(string); ok && s != "" {
			cliArgs = append(cliArgs, "--output", s)
		}
	}

	if v, ok := args["token_limit"]; ok {
		if limit, ok := toInt(v); ok {
			cliArgs = append(cliArgs, "--token-limit", strconv.Itoa(limit))
		}
	}

	// dir is always the last positional arg
	cliArgs = append(cliArgs, dir)

	return cliArgs
}

func toInt(v any) (int, bool) {
	switch n := v.(type) {
	case float64:
		return int(n), true
	case int:
		return n, true
	case json.Number:
		i, err := n.Int64()
		if err != nil {
			return 0, false
		}
		return int(i), true
	}
	return 0, false
}

func toStringSlice(v any) []string {
	arr, ok := v.([]any)
	if !ok {
		return nil
	}
	result := make([]string, 0, len(arr))
	for _, item := range arr {
		if s, ok := item.(string); ok {
			result = append(result, s)
		}
	}
	return result
}

func handleRequest(ctx context.Context, req JSONRPCRequest) {
	switch req.Method {
	case "initialize":
		handleInitialize(req)
	case "notifications/initialized", "initialized":
		// no response for notifications
	case "ping":
		sendResponse(req.ID, struct{}{})
	case "tools/list":
		handleToolsList(req)
	case "tools/call":
		// Spawn goroutine for concurrent execution
		wg.Add(1)
		go func() {
			defer wg.Done()
			handleToolsCall(ctx, req)
		}()
	default:
		if req.ID != nil {
			sendError(req.ID, -32601, "Method not found")
		}
	}
}

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		<-sigChan
		cancel()
	}()

	scanner := bufio.NewScanner(os.Stdin)
	buf := make([]byte, 0, 64*1024)
	scanner.Buffer(buf, 10*1024*1024)

	lineChan := make(chan string)
	go func() {
		for scanner.Scan() {
			lineChan <- scanner.Text()
		}
		close(lineChan)
	}()

	for {
		select {
		case <-ctx.Done():
			wg.Wait()
			return
		case line, ok := <-lineChan:
			if !ok {
				wg.Wait()
				return
			}
			if line == "" {
				continue
			}

			var req JSONRPCRequest
			if err := json.Unmarshal([]byte(line), &req); err != nil {
				sendError(nil, -32700, "Parse error")
				continue
			}

			handleRequest(ctx, req)
		}
	}
}
