#!/usr/bin/env python3
# mock_telemetry.py - Create fake telemetry server to avoid CLI errors
# Created: 2025-09-06

import http.server
import socketserver
import json
import threading
import time
import sys
from urllib.parse import urlparse, parse_qs

class MockTelemetryHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        """Handle POST requests (telemetry data submission)"""
        # Read telemetry data
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length)
        
        # Log what we're intercepting
        timestamp = time.strftime('%Y-%m-%d %H:%M:%S')
        data_size = len(post_data)
        client_ip = self.client_address[0]
        
        print(f"[{timestamp}] INTERCEPTED telemetry from {client_ip}")
        print(f"  Size: {data_size} bytes")
        print(f"  Headers: {dict(self.headers)}")
        
        # Try to decode and analyze content
        try:
            if self.headers.get('Content-Type', '').startswith('application/json'):
                decoded = post_data.decode('utf-8')
                json_data = json.loads(decoded)
                print(f"  JSON Data: {json_data}")
            elif self.headers.get('Content-Type', '').startswith('application/x-protobuf'):
                print(f"  Protocol Buffers data (binary): {data_size} bytes")
                print(f"  Sample: {post_data[:100]}...")
            else:
                decoded = post_data.decode('utf-8', errors='ignore')
                print(f"  Raw data: {decoded[:200]}...")
        except Exception as e:
            print(f"  Data parsing error: {e}")
        
        # Write to log file
        with open('intercepted_telemetry.log', 'a') as f:
            f.write(f"{timestamp} - {data_size} bytes from {client_ip}\n")
            f.write(f"Headers: {dict(self.headers)}\n")
            try:
                decoded_data = post_data.decode('utf-8', errors='ignore')
                f.write(f"Data: {decoded_data}\n")
            except:
                f.write(f"Binary data: {data_size} bytes\n")
            f.write("---\n")
        
        # Return success response to prevent CLI errors
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        
        # Send fake success response
        response = {
            "status": "ok",
            "message": "telemetry received",
            "timestamp": timestamp
        }
        self.wfile.write(json.dumps(response).encode())
    
    def do_GET(self):
        """Handle GET requests (health checks, etc.)"""
        timestamp = time.strftime('%Y-%m-%d %H:%M:%S')
        print(f"[{timestamp}] GET request from {self.client_address[0]}: {self.path}")
        
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        
        response = {
            "status": "healthy",
            "service": "mock-telemetry-server",
            "timestamp": timestamp
        }
        self.wfile.write(json.dumps(response).encode())
    
    def log_message(self, format, *args):
        """Suppress default HTTP server logs"""
        pass

def start_server(port, server_name):
    """Start mock telemetry server on specified port"""
    try:
        with socketserver.TCPServer(("127.0.0.1", port), MockTelemetryHandler) as httpd:
            print(f"Mock {server_name} server running on localhost:{port}")
            httpd.serve_forever()
    except OSError as e:
        if e.errno == 98:  # Address already in use
            print(f"Port {port} already in use - {server_name} server not started")
        else:
            print(f"Error starting {server_name} server on port {port}: {e}")
    except KeyboardInterrupt:
        print(f"\n{server_name} server shutting down...")

def main():
    """Main function to start multiple mock servers"""
    print("=== Mock Telemetry Server ===")
    print("This server intercepts and logs telemetry data while preventing CLI errors.")
    print("Press Ctrl+C to stop all servers.")
    print("")
    
    # Clean previous log
    with open('intercepted_telemetry.log', 'w') as f:
        f.write(f"Mock Telemetry Server Log Started: {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write("="*50 + "\n")
    
    # Start servers for different telemetry ports
    servers = [
        (4317, "OpenTelemetry GRPC"),
        (4318, "OpenTelemetry HTTP"), 
        (16686, "Jaeger UI")
    ]
    
    threads = []
    
    for port, name in servers:
        thread = threading.Thread(target=start_server, args=(port, name))
        thread.daemon = True
        thread.start()
        threads.append(thread)
        time.sleep(0.1)  # Small delay between server starts
    
    print("")
    print("Mock servers started. Monitoring telemetry interception...")
    print("Log file: intercepted_telemetry.log")
    print("")
    print("Test with Gemini CLI:")
    print("  gemini 'test command'")
    print("")
    print("Watch live interception:")
    print("  tail -f intercepted_telemetry.log")
    print("")
    
    try:
        # Keep main thread alive
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nShutting down mock telemetry servers...")
        sys.exit(0)

if __name__ == "__main__":
    main()