defmodule FactorialHR.Config do
  @moduledoc """
  Configuration normalization for `FactorialHR`.

  The library accepts explicit keyword options and has a small environment
  fallback for scripts. Host applications should normally pass credentials from
  their own configuration layer instead of relying on process environment.
  """

  alias FactorialHR.Error

  @default_base_url "https://api.factorialhr.com"
  @default_api_version "2026-04-01"
  @default_timeout 300_000

  @type auth_mode :: :api_key | :bearer

  @type t :: %__MODULE__{
          base_url: String.t(),
          api_version: String.t(),
          auth_mode: auth_mode(),
          token: String.t(),
          company_id: integer() | String.t() | nil,
          author_id: integer() | String.t() | nil,
          req_options: keyword(),
          receive_timeout: pos_integer()
        }

  defstruct base_url: @default_base_url,
            api_version: @default_api_version,
            auth_mode: :api_key,
            token: nil,
            company_id: nil,
            author_id: nil,
            req_options: [],
            receive_timeout: @default_timeout

  @doc """
  Builds a normalized configuration struct from keyword options or a map.

  Supported options:

    * `:api_key`, `:access_token` or `:token`
    * `:auth_mode` / `:auth` as `:api_key`, `"api_key"`, `:bearer`, or `"bearer"`
    * `:base_url` or `:api_url`
    * `:api_version`
    * `:company_id`, `:author_id`
    * `:req_options`
    * `:receive_timeout`

  If no token is supplied, `FACTORIAL_API_KEY`, `FACTORIAL_ACCESS_TOKEN`, and
  `FACTORIAL_API_TOKEN` are checked in that order.
  """
  @spec new(keyword() | map() | t()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{} = config), do: validate(config)

  def new(opts) when is_list(opts) or is_map(opts) do
    opts = normalize_opts(opts)

    with {:ok, base_url, api_version} <- normalize_api_location(opts) do
      auth_mode = normalize_auth_mode(get_opt(opts, :auth_mode) || get_opt(opts, :auth))
      token = token_for(auth_mode, opts)

      %__MODULE__{
        base_url: base_url,
        api_version: api_version,
        auth_mode: auth_mode,
        token: token,
        company_id: get_opt(opts, :company_id),
        author_id: get_opt(opts, :author_id),
        req_options: normalize_req_options(get_opt(opts, :req_options)),
        receive_timeout: get_opt(opts, :receive_timeout) || @default_timeout
      }
      |> validate()
    end
  end

  @doc false
  @spec parse_int(integer() | String.t() | nil) :: integer() | String.t() | nil
  def parse_int(value) when is_integer(value), do: value
  def parse_int(nil), do: nil

  def parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _other -> value
    end
  end

  def parse_int(value), do: value

  defp validate(%__MODULE__{} = config) do
    with :ok <- validate_binary(:base_url, config.base_url),
         :ok <- validate_binary(:api_version, config.api_version),
         :ok <- validate_token(config.token) do
      {:ok, config}
    end
  end

  defp validate_token(token) when is_binary(token) and token != "", do: :ok

  defp validate_token(_token) do
    {:error,
     Error.new(:config_missing,
       reason: :token_missing,
       request: %{credential: "api_key or bearer token"}
     )}
  end

  defp normalize_opts(opts) when is_list(opts), do: opts
  defp normalize_opts(opts) when is_map(opts), do: Map.to_list(opts)

  defp normalize_api_location(opts) do
    api_url = get_opt(opts, :api_url)
    api_version = get_opt(opts, :api_version)

    {url_source, base_url} =
      cond do
        not is_nil(get_opt(opts, :base_url)) -> {:base_url, get_opt(opts, :base_url)}
        not is_nil(api_url) -> {:api_url, api_url}
        env_url = env("FACTORIAL_API_URL") -> {:api_url, env_url}
        true -> {:base_url, @default_base_url}
      end

    with :ok <- validate_binary(url_source, base_url),
         :ok <- validate_optional_binary(:api_version, api_version) do
      case split_versioned_api_url(base_url) do
        {:ok, parsed_base_url, parsed_version} ->
          {:ok, parsed_base_url, api_version || parsed_version}

        :error ->
          {:ok, String.trim_trailing(base_url, "/"),
           api_version || env("FACTORIAL_API_VERSION") || @default_api_version}
      end
    end
  end

  defp validate_binary(_field, value) when is_binary(value) and value != "", do: :ok

  defp validate_binary(field, _value) do
    {:error, Error.new(:invalid_config, reason: invalid_reason(field))}
  end

  defp validate_optional_binary(_field, nil), do: :ok
  defp validate_optional_binary(field, value), do: validate_binary(field, value)

  defp invalid_reason(:base_url), do: :base_url_invalid
  defp invalid_reason(:api_url), do: :api_url_invalid
  defp invalid_reason(:api_version), do: :api_version_invalid

  defp split_versioned_api_url(url) when is_binary(url) do
    case Regex.run(
           ~r/^(?<base>https?:\/\/[^\/]+)\/api\/(?<version>\d{4}-\d{2}-\d{2})(?:\/resources.*)?$/,
           url,
           capture: :all_names
         ) do
      [base, version] -> {:ok, String.trim_trailing(base, "/"), version}
      _other -> :error
    end
  end

  defp split_versioned_api_url(_url), do: :error

  defp normalize_auth_mode(mode) when mode in [:bearer, "bearer"], do: :bearer

  defp normalize_auth_mode(mode) when mode in [:api_key, "api_key", "apikey", "x-api-key"],
    do: :api_key

  defp normalize_auth_mode(_mode), do: :api_key

  defp token_for(:bearer, opts) do
    get_opt(opts, :access_token) || get_opt(opts, :token) || env("FACTORIAL_ACCESS_TOKEN") ||
      env("FACTORIAL_API_TOKEN")
  end

  defp token_for(:api_key, opts) do
    get_opt(opts, :api_key) || get_opt(opts, :token) || env("FACTORIAL_API_KEY") ||
      env("FACTORIAL_API_TOKEN")
  end

  defp normalize_req_options(nil), do: []
  defp normalize_req_options(opts) when is_list(opts), do: opts
  defp normalize_req_options(_opts), do: []

  defp get_opt(opts, key) do
    string_key = Atom.to_string(key)

    case List.keyfind(opts, key, 0) || List.keyfind(opts, string_key, 0) do
      {_key, value} -> value
      nil -> nil
    end
  end

  defp env(name), do: System.get_env(name)
end
