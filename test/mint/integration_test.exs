defmodule Mint.IntegrationTest do
  use ExUnit.Case, async: true

  import Mint.HTTP1.TestHelpers

  alias Mint.{TransportError, HTTP}

  describe "httpbin.org" do
    @describetag :integration

    test "SSL - select HTTP1" do
      assert {:ok, conn} =
               HTTP.connect(
                 :https,
                 "httpbin.org",
                 443
               )

      assert conn.__struct__ == Mint.HTTP1
      assert {:ok, conn, request} = HTTP.request(conn, "GET", "/bytes/1", [], nil)
      assert {:ok, _conn, responses} = receive_stream(conn)

      assert [
               {:status, ^request, 200},
               {:headers, ^request, _},
               {:data, ^request, <<_>>},
               {:done, ^request}
             ] = responses
    end

    @tag :capture_log
    test "SSL - fail to select HTTP2" do
      assert {:error, %TransportError{reason: :protocol_not_negotiated}} =
               HTTP.connect(:https, "httpbin.org", 443,
                 protocols: [:http2],
                 transport_opts: [reuse_sessions: false]
               )
    end
  end

  describe "nghttp2.org" do
    @describetag :integration

    test "SSL - select HTTP1" do
      assert {:ok, conn} = HTTP.connect(:https, "nghttp2.org", 443, protocols: [:http1])

      assert conn.__struct__ == Mint.HTTP1
      assert {:ok, conn, request} = HTTP.request(conn, "GET", "/httpbin/bytes/1", [], nil)
      assert {:ok, _conn, responses} = receive_stream(conn)

      assert [
               {:status, ^request, 200},
               {:headers, ^request, _},
               {:data, ^request, <<_>>},
               {:done, ^request}
             ] = responses
    end

    test "SSL - select HTTP2" do
      assert {:ok, conn} = HTTP.connect(:https, "nghttp2.org", 443)

      assert conn.__struct__ == Mint.HTTP2
      assert {:ok, conn, request} = HTTP.request(conn, "GET", "/httpbin/bytes/1", [], nil)
      assert {:ok, _conn, responses} = receive_stream(conn)

      assert [
               {:status, ^request, 200},
               {:headers, ^request, _},
               {:data, ^request, <<_>>},
               {:done, ^request}
             ] = responses
    end
  end

  describe "ssl certificate verification" do
    @describetag :integration

    test "bad certificate - badssl.com" do
      assert {:error, %TransportError{reason: reason}} =
               HTTP.connect(
                 :https,
                 "untrusted-root.badssl.com",
                 443,
                 transport_opts: [log_alert: false, reuse_sessions: false]
               )

      # OTP 21.3 changes the format of SSL errors. Let's support both ways for now.
      assert reason in [
               {:tls_alert, 'unknown ca'},
               {:tls_alert, {:unknown_ca, 'received CLIENT ALERT: Fatal - Unknown CA'}}
             ]

      assert {:ok, _conn} =
               HTTP.connect(
                 :https,
                 "untrusted-root.badssl.com",
                 443,
                 transport_opts: [verify: :verify_none]
               )
    end

    test "bad hostname - badssl.com" do
      assert {:error, %TransportError{reason: reason}} =
               HTTP.connect(
                 :https,
                 "wrong.host.badssl.com",
                 443,
                 transport_opts: [log_alert: false, reuse_sessions: false]
               )

      # OTP 21.3 changes the format of SSL errors. Let's support both ways for now.
      assert reason in [
               {:tls_alert, 'handshake failure'},
               {:tls_alert,
                {:handshake_failure,
                 'received CLIENT ALERT: Fatal - Handshake Failure - {bad_cert,hostname_check_failed}'}}
             ]

      assert {:ok, _conn} =
               HTTP.connect(
                 :https,
                 "wrong.host.badssl.com",
                 443,
                 transport_opts: [verify: :verify_none]
               )
    end
  end

  describe "proxy" do
    @describetag :proxy

    test "200 response - http://httpbin.org" do
      assert {:ok, conn} =
               HTTP.connect(:http, "httpbin.org", 80, proxy: {:http, "localhost", 8888, []})

      assert conn.__struct__ == Mint.UnsafeProxy
      assert {:ok, conn, request} = HTTP.request(conn, "GET", "/", [], nil)
      assert {:ok, _conn, responses} = receive_stream(conn)

      assert [status, headers | responses] = responses
      assert {:status, ^request, 200} = status
      assert {:headers, ^request, headers} = headers
      assert is_list(headers)
      assert merge_body(responses, request) =~ "httpbin"
    end

    test "200 response - https://httpbin.org" do
      assert {:ok, conn} =
               HTTP.connect(:https, "httpbin.org", 443, proxy: {:http, "localhost", 8888, []})

      assert conn.__struct__ == Mint.HTTP1
      assert {:ok, conn, request} = HTTP.request(conn, "GET", "/", [], nil)
      assert {:ok, _conn, responses} = receive_stream(conn)

      assert [status, headers | responses] = responses
      assert {:status, ^request, 200} = status
      assert {:headers, ^request, headers} = headers
      assert is_list(headers)
      assert merge_body(responses, request) =~ "httpbin"
    end

    test "200 response with explicit http2 - https://http2.golang.org" do
      assert {:ok, conn} =
               HTTP.connect(:https, "http2.golang.org", 443,
                 proxy: {:http, "localhost", 8888, []},
                 protocols: [:http2]
               )

      assert conn.__struct__ == Mint.HTTP2
      assert {:ok, conn, request} = HTTP.request(conn, "GET", "/reqinfo", [], nil)
      assert {:ok, _conn, responses} = receive_stream(conn)

      assert [status, headers | responses] = responses
      assert {:status, ^request, 200} = status
      assert {:headers, ^request, headers} = headers
      assert is_list(headers)
      assert merge_body(responses, request) =~ "Protocol: HTTP/2.0"
    end

    test "200 response without explicit http2 - https://http2.golang.org" do
      assert {:ok, conn} =
               HTTP.connect(:https, "http2.golang.org", 443,
                 proxy: {:http, "localhost", 8888, []},
                 protocols: [:http1, :http2]
               )

      assert conn.__struct__ == Mint.HTTP2
      assert {:ok, conn, request} = HTTP.request(conn, "GET", "/reqinfo", [], nil)
      assert {:ok, _conn, responses} = receive_stream(conn)

      assert [status, headers | responses] = responses
      assert {:status, ^request, 200} = status
      assert {:headers, ^request, headers} = headers
      assert is_list(headers)
      assert merge_body(responses, request) =~ "Protocol: HTTP/2.0"
    end
  end
end
