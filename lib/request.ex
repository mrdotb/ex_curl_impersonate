defmodule ExCurlImpersonate.Request do
  @moduledoc false
  # build script lives outside lib/ so it is not part of the runtime app
  @external_resource Path.expand("../build/curl_impersonate.ex", __DIR__)
  Code.require_file("../build/curl_impersonate.ex", __DIR__)

  use Zig,
    otp_app: :ex_curl_impersonate,
    c: ExCurlImpersonate.Build.zig_c_opts(),
    nifs: [request: [:dirty_io], curl_version: []]

  ~Z"""
  const beam = @import("beam");
  const std = @import("std");
  const cURL = @cImport({
      @cInclude("curl/curl.h");
  });

  pub const Header = struct { key: []u8, value: []u8 };

  pub const RequestFlags = struct {
      follow_location: bool,
      ssl_verifyhost: bool,
      ssl_verifypeer: bool,
      return_metrics: bool,
      verbose: bool,
      proxy: ?[]u8,
      impersonate: ?[]u8,
      impersonate_default_headers: bool,
      http_version: ?i64,
  };

  pub const LongOpts = struct {
      http2_no_priority: ?i64,
      http2_window_update: ?i64,
      http3_ssl_permute_extensions: ?i64,
      proxy_credential_no_reuse: ?i64,
      quic_initial_packet_number: ?i64,
      split_cookies: ?i64,
      ssl_enable_alps: ?i64,
      ssl_enable_ticket: ?i64,
      ssl_permute_extensions: ?i64,
      stream_exclusive: ?i64,
      tls_grease: ?i64,
      tls_key_shares_limit: ?i64,
      tls_key_usage_no_check: ?i64,
      tls_record_size_limit: ?i64,
      tls_signed_cert_timestamps: ?i64,
      tls_status_request: ?i64,
      tls_use_new_alps_codepoint: ?i64,
      ws_ssl_disable_ticket: ?i64,
  };

  pub const StringOpts = struct {
      form_boundary: ?[]u8,
      http2_pseudo_headers_order: ?[]u8,
      http2_settings: ?[]u8,
      http2_streams: ?[]u8,
      http3_httpheader_order: ?[]u8,
      http3_pseudo_headers_order: ?[]u8,
      http3_settings: ?[]u8,
      http3_sig_hash_algs: ?[]u8,
      http3_ssl_ec_curves: ?[]u8,
      http3_tls_extension_order: ?[]u8,
      httpheader_order: ?[]u8,
      quic_cid_length: ?[]u8,
      quic_transport_parameters: ?[]u8,
      ssl_cert_compression: ?[]u8,
      ssl_sig_hash_algs: ?[]u8,
      tls_delegated_credentials: ?[]u8,
      tls_extension_order: ?[]u8,
      tls_trust_anchors: ?[]u8,
      ws_httpheader_order: ?[]u8,
      ws_ssl_cert_compression: ?[]u8,
  };

  pub const SlistOpts = struct {
      httpbaseheader: ?[][]u8,
      http3_httpheader: ?[][]u8,
      ws_httpheader: ?[][]u8,
  };

  pub const RequestConfiguration = struct {
      headers: []Header,
      url: []u8,
      method: []u8,
      body: []u8,
      flags: RequestFlags,
      long_opts: LongOpts,
      string_opts: StringOpts,
      slist_opts: SlistOpts,
  };

  pub const ResponseMetrics = struct {
      namelookup_time: f64,
      connect_time: f64,
      appconnect_time: f64,
      pretransfer_time: f64,
      starttransfer_time: f64,
      total_time: f64,
  };

  pub const Response = struct {
      body: []u8,
      status_code: u64,
      headers: []u8,
      http_version: i64,
      metrics: ?ResponseMetrics,
  };

  pub fn curl_version() []const u8 {
      return std.mem.sliceTo(cURL.curl_version(), 0);
  }

  pub fn request(config: RequestConfiguration) !beam.term {
      // initialize curl and vars
      var arena_state = std.heap.ArenaAllocator.init(std.heap.c_allocator);
      defer arena_state.deinit();

      const allocator = arena_state.allocator();

      const handle = cURL.curl_easy_init() orelse return beam.make_error_pair("init_failed", .{});
      defer cURL.curl_easy_cleanup(handle);

      var slists = [_][*c]cURL.curl_slist{null} ** slist_opts.len;
      defer for (slists) |list| cURL.curl_slist_free_all(list);

      var response_buffer = std.array_list.Managed(u8).init(allocator);
      var headers_buffer = std.array_list.Managed(u8).init(allocator);

      // superfluous when using an arena allocator, but
      // important if the allocator implementation changes
      defer response_buffer.deinit();
      defer headers_buffer.deinit();

      // set curl opts & callbacks
      const opts_result = try setCurlOpts(allocator, handle, config, &slists);
      if (opts_result != cURL.CURLE_OK)
          return beam.make_error_pair(opts_result, .{});
      // set headers
      var header_slist: [*c]cURL.curl_slist = null;
      defer cURL.curl_slist_free_all(header_slist);
      for (config.headers) |header| {
          const buf = try allocator.alloc(u8, header.key.len + 3 + header.value.len);
          _ = try std.fmt.bufPrint(buf, "{s}: {s}\x00", .{ header.key, header.value });
          header_slist = cURL.curl_slist_append(header_slist, buf.ptr);
          allocator.free(buf);
      }

      // Response body callback
      if (cURL.curl_easy_setopt(handle, cURL.CURLOPT_HTTPHEADER, header_slist) != cURL.CURLE_OK)
          unreachable;

      // Response body callback
      if (cURL.curl_easy_setopt(handle, cURL.CURLOPT_WRITEFUNCTION, writeToArrayListCallback) != cURL.CURLE_OK)
          unreachable;
      if (cURL.curl_easy_setopt(handle, cURL.CURLOPT_WRITEDATA, &response_buffer) != cURL.CURLE_OK)
          unreachable;

      // Headers callback
      if (cURL.curl_easy_setopt(handle, cURL.CURLOPT_HEADERFUNCTION, writeToArrayListCallback) != cURL.CURLE_OK)
          unreachable;
      if (cURL.curl_easy_setopt(handle, cURL.CURLOPT_HEADERDATA, &headers_buffer) != cURL.CURLE_OK)
          unreachable;

      // Request body
      if (!std.mem.eql(u8, config.body, "")) {
          if (cURL.curl_easy_setopt(handle, cURL.CURLOPT_READFUNCTION, readFn) != cURL.CURLE_OK)
              unreachable;
          if (cURL.curl_easy_setopt(handle, cURL.CURLOPT_READDATA, &config) != cURL.CURLE_OK)
              unreachable;
      }

      // 3. perform request
      const result = cURL.curl_easy_perform(handle);
      if (result != cURL.CURLE_OK)
          return beam.make_error_pair(result, .{});

      // 4. getinfo and create response
      const response = try makeResponse(handle, response_buffer, headers_buffer, config);
      return beam.make(.{ .ok, response }, .{});
  }

  fn makeResponse(handle: *cURL.CURL, response_buffer: std.array_list.Managed(u8), headers_buffer: std.array_list.Managed(u8), config: RequestConfiguration) !Response {
      var status_code: u64 = 0;
      if (cURL.curl_easy_getinfo(handle, cURL.CURLINFO_RESPONSE_CODE, &status_code) != cURL.CURLE_OK)
          return error.CURLGETINFO_FAILED;

      var http_version: c_long = 0;
      if (cURL.curl_easy_getinfo(handle, cURL.CURLINFO_HTTP_VERSION, &http_version) != cURL.CURLE_OK)
          return error.CURLGETINFO_FAILED;

      return .{
          .body = response_buffer.items,
          .status_code = status_code,
          .headers = headers_buffer.items,
          .http_version = http_version,
          .metrics = if (config.flags.return_metrics) try makeResponseMetrics(handle) else null,
      };
  }

  fn makeResponseMetrics(handle: *cURL.CURL) !ResponseMetrics {
      var total_time: f64 = 0;
      if (cURL.curl_easy_getinfo(handle, cURL.CURLINFO_TOTAL_TIME_T, &total_time) != cURL.CURLE_OK)
          return error.CURLGETINFO_FAILED;

      var namelookup_time: f64 = 0;
      if (cURL.curl_easy_getinfo(handle, cURL.CURLINFO_NAMELOOKUP_TIME_T, &namelookup_time) != cURL.CURLE_OK)
          return error.CURLGETINFO_FAILED;

      var connect_time: f64 = 0;
      if (cURL.curl_easy_getinfo(handle, cURL.CURLINFO_CONNECT_TIME_T, &connect_time) != cURL.CURLE_OK)
          return error.CURLGETINFO_FAILED;

      var appconnect_time: f64 = 0;
      if (cURL.curl_easy_getinfo(handle, cURL.CURLINFO_APPCONNECT_TIME_T, &appconnect_time) != cURL.CURLE_OK)
          return error.CURLGETINFO_FAILED;

      var pretransfer_time: f64 = 0;
      if (cURL.curl_easy_getinfo(handle, cURL.CURLINFO_PRETRANSFER_TIME_T, &pretransfer_time) != cURL.CURLE_OK)
          return error.CURLGETINFO_FAILED;

      var starttransfer_time: f64 = 0;
      if (cURL.curl_easy_getinfo(handle, cURL.CURLINFO_STARTTRANSFER_TIME_T, &starttransfer_time) != cURL.CURLE_OK)
          return error.CURLGETINFO_FAILED;

      return .{
          .namelookup_time = namelookup_time,
          .connect_time = connect_time,
          .appconnect_time = appconnect_time,
          .pretransfer_time = pretransfer_time,
          .starttransfer_time = starttransfer_time,
          .total_time = total_time,
      };
  }

  const long_opts = .{
      .{ "http2_no_priority", cURL.CURLOPT_HTTP2_NO_PRIORITY },
      .{ "http2_window_update", cURL.CURLOPT_HTTP2_WINDOW_UPDATE },
      .{ "http3_ssl_permute_extensions", cURL.CURLOPT_HTTP3_SSL_PERMUTE_EXTENSIONS },
      .{ "proxy_credential_no_reuse", cURL.CURLOPT_PROXY_CREDENTIAL_NO_REUSE },
      .{ "quic_initial_packet_number", cURL.CURLOPT_QUIC_INITIAL_PACKET_NUMBER },
      .{ "split_cookies", cURL.CURLOPT_SPLIT_COOKIES },
      .{ "ssl_enable_alps", cURL.CURLOPT_SSL_ENABLE_ALPS },
      .{ "ssl_enable_ticket", cURL.CURLOPT_SSL_ENABLE_TICKET },
      .{ "ssl_permute_extensions", cURL.CURLOPT_SSL_PERMUTE_EXTENSIONS },
      .{ "stream_exclusive", cURL.CURLOPT_STREAM_EXCLUSIVE },
      .{ "tls_grease", cURL.CURLOPT_TLS_GREASE },
      .{ "tls_key_shares_limit", cURL.CURLOPT_TLS_KEY_SHARES_LIMIT },
      .{ "tls_key_usage_no_check", cURL.CURLOPT_TLS_KEY_USAGE_NO_CHECK },
      .{ "tls_record_size_limit", cURL.CURLOPT_TLS_RECORD_SIZE_LIMIT },
      .{ "tls_signed_cert_timestamps", cURL.CURLOPT_TLS_SIGNED_CERT_TIMESTAMPS },
      .{ "tls_status_request", cURL.CURLOPT_TLS_STATUS_REQUEST },
      .{ "tls_use_new_alps_codepoint", cURL.CURLOPT_TLS_USE_NEW_ALPS_CODEPOINT },
      .{ "ws_ssl_disable_ticket", cURL.CURLOPT_WS_SSL_DISABLE_TICKET },
  };

  const string_opts = .{
      .{ "form_boundary", cURL.CURLOPT_FORM_BOUNDARY },
      .{ "http2_pseudo_headers_order", cURL.CURLOPT_HTTP2_PSEUDO_HEADERS_ORDER },
      .{ "http2_settings", cURL.CURLOPT_HTTP2_SETTINGS },
      .{ "http2_streams", cURL.CURLOPT_HTTP2_STREAMS },
      .{ "http3_httpheader_order", cURL.CURLOPT_HTTP3_HTTPHEADER_ORDER },
      .{ "http3_pseudo_headers_order", cURL.CURLOPT_HTTP3_PSEUDO_HEADERS_ORDER },
      .{ "http3_settings", cURL.CURLOPT_HTTP3_SETTINGS },
      .{ "http3_sig_hash_algs", cURL.CURLOPT_HTTP3_SIG_HASH_ALGS },
      .{ "http3_ssl_ec_curves", cURL.CURLOPT_HTTP3_SSL_EC_CURVES },
      .{ "http3_tls_extension_order", cURL.CURLOPT_HTTP3_TLS_EXTENSION_ORDER },
      .{ "httpheader_order", cURL.CURLOPT_HTTPHEADER_ORDER },
      .{ "quic_cid_length", cURL.CURLOPT_QUIC_CID_LENGTH },
      .{ "quic_transport_parameters", cURL.CURLOPT_QUIC_TRANSPORT_PARAMETERS },
      .{ "ssl_cert_compression", cURL.CURLOPT_SSL_CERT_COMPRESSION },
      .{ "ssl_sig_hash_algs", cURL.CURLOPT_SSL_SIG_HASH_ALGS },
      .{ "tls_delegated_credentials", cURL.CURLOPT_TLS_DELEGATED_CREDENTIALS },
      .{ "tls_extension_order", cURL.CURLOPT_TLS_EXTENSION_ORDER },
      .{ "tls_trust_anchors", cURL.CURLOPT_TLS_TRUST_ANCHORS },
      .{ "ws_httpheader_order", cURL.CURLOPT_WS_HTTPHEADER_ORDER },
      .{ "ws_ssl_cert_compression", cURL.CURLOPT_WS_SSL_CERT_COMPRESSION },
  };

  const slist_opts = .{
      .{ "httpbaseheader", cURL.CURLOPT_HTTPBASEHEADER },
      .{ "http3_httpheader", cURL.CURLOPT_HTTP3_HTTPHEADER },
      .{ "ws_httpheader", cURL.CURLOPT_WS_HTTPHEADER },
  };

  const bool_flag_opts = .{
      .{ "verbose", cURL.CURLOPT_VERBOSE },
      .{ "follow_location", cURL.CURLOPT_FOLLOWLOCATION },
      .{ "ssl_verifypeer", cURL.CURLOPT_SSL_VERIFYPEER },
      .{ "ssl_verifyhost", cURL.CURLOPT_SSL_VERIFYHOST },
  };

  fn setCurlOpts(allocator: std.mem.Allocator, handle: *cURL.CURL, config: RequestConfiguration, slists: *[slist_opts.len][*c]cURL.curl_slist) !cURL.CURLcode {
      if (config.flags.impersonate) |target| {
          const c_target = try allocator.dupeZ(u8, target);
          defer allocator.free(c_target);
          const default_headers: c_int = if (config.flags.impersonate_default_headers) 1 else 0;
          const rc = cURL.curl_easy_impersonate(handle, c_target.ptr, default_headers);
          if (rc != cURL.CURLE_OK) return rc;
      }

      inline for (bool_flag_opts) |flag| {
          const value: c_long = if (@field(config.flags, flag[0])) 1 else 0;
          if (cURL.curl_easy_setopt(handle, flag[1], value) != cURL.CURLE_OK)
              unreachable;
      }

      // HTTP Method
      if (std.mem.eql(u8, config.method, "POST")) {
          if (cURL.curl_easy_setopt(handle, cURL.CURLOPT_POST, @as(c_long, 1)) != cURL.CURLE_OK)
              unreachable;
          if (cURL.curl_easy_setopt(handle, cURL.CURLOPT_POSTFIELDSIZE, @as(c_long, @intCast(config.body.len))) != cURL.CURLE_OK)
              unreachable;
      } else if (!std.mem.eql(u8, config.method, "GET")) {
          setStringOpt(allocator, handle, cURL.CURLOPT_CUSTOMREQUEST, config.method);
      }

      setStringOpt(allocator, handle, cURL.CURLOPT_URL, config.url);

      if (config.flags.proxy) |proxy| {
          setStringOpt(allocator, handle, cURL.CURLOPT_PROXY, proxy);
      }

      if (config.flags.http_version) |version| {
          const rc = cURL.curl_easy_setopt(handle, cURL.CURLOPT_HTTP_VERSION, @as(c_long, @intCast(version)));
          if (rc != cURL.CURLE_OK) return rc;
      }

      inline for (long_opts) |opt| {
          if (@field(config.long_opts, opt[0])) |value| {
              const rc = cURL.curl_easy_setopt(handle, opt[1], @as(c_long, @intCast(value)));
              if (rc != cURL.CURLE_OK) return rc;
          }
      }

      inline for (string_opts) |opt| {
          if (@field(config.string_opts, opt[0])) |value| {
              const c_string = try allocator.dupeZ(u8, value);
              defer allocator.free(c_string);
              const rc = cURL.curl_easy_setopt(handle, opt[1], c_string.ptr);
              if (rc != cURL.CURLE_OK) return rc;
          }
      }

      inline for (0..slist_opts.len) |i| {
          const opt = slist_opts[i];
          if (@field(config.slist_opts, opt[0])) |items| {
              for (items) |item| {
                  const c_item = try allocator.dupeZ(u8, item);
                  defer allocator.free(c_item);
                  slists[i] = cURL.curl_slist_append(slists[i], c_item.ptr);
              }
              // an empty list sets NULL, clearing e.g. the impersonate base headers
              const rc = cURL.curl_easy_setopt(handle, opt[1], slists[i]);
              if (rc != cURL.CURLE_OK) return rc;
          }
      }

      return cURL.CURLE_OK;
  }

  fn setStringOpt(allocator: std.mem.Allocator, handle: *cURL.CURL, opt: cURL.CURLoption, value: []const u8) void {
      const c_string = allocator.dupeZ(u8, value) catch unreachable;
      defer allocator.free(c_string);
      if (cURL.curl_easy_setopt(handle, opt, c_string.ptr) != cURL.CURLE_OK)
          unreachable;
  }

  fn readFn(dest: [*c]u8, size: usize, nmemb: usize, config: *RequestConfiguration) callconv(.c) usize {
      const bufferSize = size * nmemb;

      if (config.body.len == 0) {
          return 0; // nothing to read
      }

      const n = @min(config.body.len, bufferSize);
      std.mem.copyForwards(u8, dest[0..n], config.body[0..n]);
      config.body = config.body[n..];
      return n;
  }

  fn writeToArrayListCallback(data: *anyopaque, size: c_uint, nmemb: c_uint, user_data: *anyopaque) callconv(.c) c_uint {
      var buffer: *std.array_list.Managed(u8) = @ptrCast(@alignCast(user_data));
      var typed_data: [*]u8 = @ptrCast(data);
      buffer.appendSlice(typed_data[0 .. nmemb * size]) catch return 0;
      return nmemb * size;
  }
  """
end
