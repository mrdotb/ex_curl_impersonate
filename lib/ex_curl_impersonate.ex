defmodule ExCurlImpersonate do
  @moduledoc """
  Documentation for `ExCurlImpersonate`.

  ## Shared options

    * `:headers` - a map of headers to include in the request, defaults to `%{"user-agent" => "ex_curl_impersonate/0.1.0"}` (not added when `:impersonate` is set)
    * `:body` - a string to send as the request body, defaults to `""`
    * `:follow_location` - if redirects should be followed, defaults to `true`
    * `:ssl_verifyhost` - if SSL certificates should be verified, defaults to `true`
    * `:ssl_verifypeer` - if SSL certificates should be verified, defaults to `true`
    * `:return_metrics` - if request timing metrics should be included in the returned results, defaults to `false`
    * `:verbose` - if curl should output verbose logs to stdout, useful for debugging. Defaults to `false`
    * `:proxy` - proxy to use for transfers. Can be hostname or IP address with optional port number. Supports various proxy types (http, https, socks4, socks5). Defaults to `nil`
    * `:impersonate` - browser to impersonate (TLS, HTTP/2 fingerprint and default headers), e.g. `"chrome136"`, `"safari18_0"`, `"firefox135"`. See the [curl-impersonate targets](https://github.com/lexiforest/curl-impersonate#supported-browsers). When set, the default `user-agent` header is not added. Defaults to `nil`
    * `:impersonate_default_headers` - whether `:impersonate` also sends the browser's default headers. Defaults to `true`
    * `:http_version` - one of `:http1_0`, `:http1_1`, `:http2`, `:http2_tls`, `:http2_prior_knowledge`, `:http3` (falls back if HTTP/3 fails) or `:http3_only`. Defaults to `nil` (curl's default, or the impersonated browser's)

  ## Error messages

  Error messages refer to error codes on the [libcurl error codes documentation page](https://curl.se/libcurl/c/libcurl-errors.html).

  For example, when we try to send a request to an invalid url:


        iex> ExCurlImpersonate.get("https://")
        {:error, "URL_MALFORMAT"}

  The returned error tuple includes the error message `"URL_MALFORMAT"`. This corresponds to the `CURLE_URL_MALFORMAT` (error code 3) error listed
  in the [libcurl error codes documentation](https://curl.se/libcurl/c/libcurl-errors.html).
  """

  alias ExCurlImpersonate.{CurlErrorCodes, Request, RequestConfiguration, Response}

  @doc """
  Sends a GET request to the given `url`. Similar to `get/2` but raises `ExCurlImpersonate.CurlError` if the request fails.

  See the ["Shared options"](#module-shared-options) section at the module documentation for available options and their defaults.

  ## Examples
      
      iex> %ExCurlImpersonate.Response{status_code: status_code} = ExCurlImpersonate.get!("https://google.com")
      iex> status_code
      200
  """
  def get!(url, opts \\ []), do: request!("GET", url, opts)

  @doc """
  Sends a POST request to the given `url`. Similar to `post/2` but raises `ExCurlImpersonate.CurlError` if the request fails.

  See the ["Shared options"](#module-shared-options) section at the module documentation for available options and their defaults.

  ## Examples
      
      iex> ExCurlImpersonate.post!("https://httpbin.org/post", body: "some-value=true")
  """
  def post!(url, opts \\ []), do: request!("POST", url, opts)

  @doc """
  Sends a PUT request to the given `url`. Similar to `put/2` but raises `ExCurlImpersonate.CurlError` if the request fails.

  See the ["Shared options"](#module-shared-options) section at the module documentation for available options and their defaults.

  ## Examples
      
      iex> ExCurlImpersonate.put!("https://httpbin.org/put", headers: %{"content-type" => "application/json"}, body: "{}")
  """
  def put!(url, opts \\ []), do: request!("PUT", url, opts)

  @doc """
  Sends a PATCH request to the given `url`. Similar to `patch/2` but raises `ExCurlImpersonate.CurlError` if the request fails.

  See the ["Shared options"](#module-shared-options) section at the module documentation for available options and their defaults.

  ## Examples
      
      iex> ExCurlImpersonate.patch!("https://httpbin.org/patch", body: Jason.encode!(%{"some-value" => true}), headers: %{"content-type" => "application/json"})
  """
  def patch!(url, opts \\ []), do: request!("PATCH", url, opts)

  @doc """
  Sends a DELETE request to the given `url`. Similar to `delete/2` but raises `ExCurlImpersonate.CurlError` if the request fails.

  See the ["Shared options"](#module-shared-options) section at the module documentation for available options and their defaults.

  ## Examples
      
      iex> ExCurlImpersonate.delete!("https://httpbin.org/delete")
  """
  def delete!(url, opts \\ []), do: request!("DELETE", url, opts)

  @doc """
  Sends a GET request to the given `url`.

  Returns either `{:ok, %ExCurlImpersonate.Response{}}` or `{:error, "CURL_ERROR_MESSAGE"}`.

  See the ["Shared options"](#module-shared-options) section at the module documentation for available options and their defaults.

  See the ["Error messages"](#module-error-messages) section for details on error messages.

  ## Examples
     
       iex> {:ok, %ExCurlImpersonate.Response{status_code: status_code}} = ExCurlImpersonate.get("https://google.com", follow_location: false)
       iex> status_code
       301
  """
  def get(url, opts \\ []), do: request("GET", url, opts)

  @doc """
  Sends a POST request to the given `url`.

  Returns either `{:ok, %ExCurlImpersonate.Response{}}` or `{:error, "CURL_ERROR_MESSAGE"}`.

  See the ["Shared options"](#module-shared-options) section at the module documentation for available options and their defaults.

  See the ["Error messages"](#module-error-messages) section for details on error messages.

  ## Examples
     
       iex> {:ok, %ExCurlImpersonate.Response{}} = ExCurlImpersonate.post("https://httpbin.org/post", body: "some-value=true")
  """
  def post(url, opts \\ []), do: request("POST", url, opts)

  @doc """
  Sends a PUT request to the given `url`.

  Returns either `{:ok, %ExCurlImpersonate.Response{}}` or `{:error, "CURL_ERROR_MESSAGE"}`.

  See the ["Shared options"](#module-shared-options) section at the module documentation for available options and their defaults.

  See the ["Error messages"](#module-error-messages) section for details on error messages.

  ## Examples


       iex> ExCurlImpersonate.put("https://httpbin.org/put", body: "some-value=true")

  """
  def put(url, opts \\ []), do: request("PUT", url, opts)

  @doc """
  Sends a PATCH request to the given `url`.

  Returns either `{:ok, %ExCurlImpersonate.Response{}}` or `{:error, "CURL_ERROR_MESSAGE"}`.

  See the ["Shared options"](#module-shared-options) section at the module documentation for available options and their defaults.

  See the ["Error messages"](#module-error-messages) section for details on error messages.

  ## Examples


      iex> ExCurlImpersonate.patch("https://httpbin.org/patch", headers: %{"user-agent" => "custom-user-agent"})
  """
  def patch(url, opts \\ []), do: request("PATCH", url, opts)

  @doc """
  Sends a DELETE request to the given `url`.

  Returns either `{:ok, %ExCurlImpersonate.Response{}}` or `{:error, "CURL_ERROR_MESSAGE"}`.

  See the ["Shared options"](#module-shared-options) section at the module documentation for available options and their defaults.

  See the ["Error messages"](#module-error-messages) section for details on error messages.

  ## Examples


      iex> ExCurlImpersonate.delete("https://httpbin.org/delete", headers: %{"Authorization" => "bearer secret"})
  """
  def delete(url, opts \\ []), do: request("DELETE", url, opts)

  @doc """
  Send a request to the `url` using the provided `method` and options

  Returns either `{:ok, %ExCurlImpersonate.Response{}}` or `{:error, "CURL_ERROR_MESSAGE"}`.

  See the ["Shared options"](#module-shared-options) section at the module documentation for available options and their defaults.

  See the ["Error messages"](#module-error-messages) section for details on error messages.

  ## Examples


      iex> ExCurlImpersonate.request("GET", "https://google.com")
  """
  def request(method, url, opts \\ []) do
    RequestConfiguration.build(method, url, opts)
    |> do_request(opts)
    |> case do
      {:ok, resp} ->
        {:ok, Response.parse(resp)}

      {:error, error_code} ->
        {:error, CurlErrorCodes.get_message(error_code)}
    end
  end

  @doc """
  Sends a request to the given `url` using the provided `method` and options. Similar to `request/3` but raises `ExCurlImpersonate.CurlError` if the request fails.


  See the ["Shared options"](#module-shared-options) section at the module documentation for available options and their defaults.
  """
  def request!(method, url, opts \\ []) do
    case request(method, url, opts) do
      {:ok, %Response{} = res} ->
        res

      {:error, error_message} when is_binary(error_message) ->
        raise ExCurlImpersonate.CurlError,
          message: """
          CURL Error: CURLE_#{error_message} (#{CurlErrorCodes.get_code(error_message)})

          For more details, search for 'CURLE_#{error_message}' on https://curl.se/libcurl/c/libcurl-errors.html
          """
    end
  end

  @doc """
  Returns the version string of the linked libcurl, e.g. `"libcurl/8.22.0-IMPERSONATE BoringSSL/..."`.
  """
  def curl_version, do: Request.curl_version()

  defp do_request(%RequestConfiguration{} = config, _opts) do
    Request.request(config)
  end
end
