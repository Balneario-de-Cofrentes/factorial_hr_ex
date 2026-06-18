defmodule FactorialHREx do
  @moduledoc """
  Generic Elixir client for the public Factorial HR REST API.

  This package intentionally stays below any product/domain mapping layer. It
  knows how to authenticate, build versioned resource URLs, follow Factorial's
  cursor pagination and call common HR endpoints, returning Factorial payloads
  as maps.
  """

  alias FactorialHREx.Config
  alias FactorialHREx.Error

  @employee_filter_batch_size 50
  @user_agent "factorial_hr_ex/0.1.0"

  @type params :: keyword() | map()
  @type client_opts :: keyword() | map() | Config.t()
  @type result :: {:ok, term()} | {:error, Error.t()}
  @type response_result :: {:ok, Req.Response.t()} | {:error, Error.t()}

  @doc """
  Executes a GET request against a versioned Factorial resource path.

  Pass a resource path such as `"/employees/employees"`. The client adds the
  `/api/:version/resources` prefix from the configured API version.

  Returns the raw `%Req.Response{}` for successful 2xx responses and a
  structured `%FactorialHREx.Error{}` for non-2xx HTTP responses or request
  failures.
  """
  @spec get(String.t(), params(), client_opts()) :: response_result()
  def get(path, params \\ [], opts \\ []) do
    :get
    |> request(path, nil, params, opts)
    |> normalize_public_response(:get, path)
  end

  @doc """
  Executes a POST request against a versioned Factorial resource path.
  """
  @spec post(String.t(), map(), client_opts()) :: response_result()
  def post(path, body, opts \\ []) when is_map(body) do
    :post
    |> request(path, body, [], opts)
    |> normalize_public_response(:post, path)
  end

  @doc """
  Executes a DELETE request against a versioned Factorial resource path.
  """
  @spec delete(String.t(), client_opts()) :: response_result()
  def delete(path, opts \\ []) do
    :delete
    |> request(path, nil, [], opts)
    |> normalize_public_response(:delete, path)
  end

  @doc """
  Fetches every page from a cursor-paginated Factorial collection.
  """
  @spec all(String.t(), params(), String.t() | nil, client_opts()) ::
          {:ok, list(map())} | {:error, Error.t()}
  def all(path, params \\ [], collection_name \\ nil, opts \\ []) do
    with {:ok, config} <- Config.new(opts) do
      fetch_all_pages(path, normalize_params(params), collection_name, config, [], nil)
    end
  end

  @doc "Lists Factorial employees."
  @spec list_employees(params(), client_opts()) :: {:ok, list(map())} | {:error, Error.t()}
  def list_employees(params \\ [], opts \\ []) do
    all("/employees/employees", params, "employees", opts)
  end

  @doc "Lists Factorial workplace locations."
  @spec list_locations(params(), client_opts()) :: {:ok, list(map())} | {:error, Error.t()}
  def list_locations(params \\ [], opts \\ []) do
    all("/locations/locations", params, "locations", opts)
  end

  @doc "Lists Factorial work areas."
  @spec list_work_areas(params(), client_opts()) :: {:ok, list(map())} | {:error, Error.t()}
  def list_work_areas(params \\ [], opts \\ []) do
    all("/locations/work_areas", params, "work_areas", opts)
  end

  @doc "Lists Factorial teams."
  @spec list_teams(params(), client_opts()) :: {:ok, list(map())} | {:error, Error.t()}
  def list_teams(params \\ [], opts \\ []) do
    all("/teams/teams", params, "teams", opts)
  end

  @doc """
  Lists unique employee IDs from the Factorial teams endpoint.

  Factorial team payloads can expose `employee_ids` or expanded `employees`.
  This helper is generic and performs no tenant-specific filtering.
  """
  @spec list_team_employee_ids(client_opts()) :: {:ok, list(integer())} | {:error, Error.t()}
  def list_team_employee_ids(opts \\ []) do
    case list_teams([], opts) do
      {:ok, teams} ->
        {:ok, teams |> Enum.flat_map(&team_employee_ids/1) |> Enum.uniq() |> Enum.sort()}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists Factorial shift-management shifts.

  Recognized convenience params include `:employee_ids`, `:location_ids`,
  `:start_at`, `:end_at`, `:only_published`, `:only_states` and
  `:split_overnight_shifts`. Other params are passed through unchanged.
  """
  @spec list_shifts(params(), client_opts()) :: {:ok, list(map())} | {:error, Error.t()}
  def list_shifts(params \\ [], opts \\ []) do
    params = normalize_shift_management_params(params)
    fetch_batched_collection("/shift_management/shifts", params, "shifts", opts)
  end

  @doc """
  Lists Factorial attendance shifts for a date range.
  """
  @spec list_attendance_shifts(
          Date.t() | String.t(),
          Date.t() | String.t(),
          params(),
          client_opts()
        ) ::
          {:ok, list(map())} | {:error, Error.t()}
  def list_attendance_shifts(start_on, end_on, params \\ [], opts \\ []) do
    params =
      params
      |> normalize_params()
      |> put_param("start_on", format_date(start_on))
      |> put_param("end_on", format_date(end_on))

    fetch_batched_collection("/attendance/shifts", params, "shifts", opts)
  end

  @doc """
  Lists Factorial contract versions.
  """
  @spec list_contract_versions(params(), client_opts()) ::
          {:ok, list(map())} | {:error, Error.t()}
  def list_contract_versions(params \\ [], opts \\ []) do
    all("/contracts/contract_versions", params, "contract_versions", opts)
  end

  @doc """
  Lists Factorial contract compensations.
  """
  @spec list_compensations(params(), client_opts()) :: {:ok, list(map())} | {:error, Error.t()}
  def list_compensations(params \\ [], opts \\ []) do
    all("/contracts/compensations", params, "compensations", opts)
  end

  @doc """
  Creates one shift in Factorial shift management.
  """
  @spec create_shift(map(), client_opts()) :: {:ok, map()} | {:error, Error.t()}
  def create_shift(params, opts \\ []) when is_map(params) do
    with {:ok, config} <- Config.new(opts),
         {:ok, body} <- build_shift_body(params, config) do
      case request(:post, "/shift_management/shifts", body, [], config) do
        {:ok, %{status: status, body: body}} when status in [200, 201] ->
          {:ok, body}

        {:ok, %{status: status, body: body}} ->
          http_error(status, body, :post, "/shift_management/shifts")

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Creates several shifts in Factorial shift management.
  """
  @spec bulk_create_shifts([map()], client_opts()) :: {:ok, list(map())} | {:error, Error.t()}
  def bulk_create_shifts(shifts, opts \\ []) when is_list(shifts) do
    with {:ok, config} <- Config.new(opts),
         {:ok, bodies} <- build_shift_bodies(shifts, config) do
      body = %{"shifts" => bodies}

      case request(:post, "/shift_management/shifts/bulk_create", body, [], config) do
        {:ok, %{status: status, body: body}} when status in [200, 201] ->
          {:ok, created_shifts(body)}

        {:ok, %{status: status, body: body}} ->
          http_error(status, body, :post, "/shift_management/shifts/bulk_create")

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Deletes one shift by Factorial shift-management ID.

  A `404` is treated as success to make delete operations idempotent.
  """
  @spec delete_shift(integer() | String.t(), client_opts()) :: :ok | {:error, Error.t()}
  def delete_shift(shift_id, opts \\ []) do
    path = "/shift_management/shifts/#{shift_id}"

    case request(:delete, path, nil, [], opts) do
      {:ok, %{status: status}} when status in [200, 204, 404] -> :ok
      {:ok, %{status: status, body: body}} -> http_error(status, body, :delete, path)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Bulk-deletes shifts.

  Pass a list of IDs or a map/keyword list matching Factorial's bulk delete
  filters. `author_id` is read from params first, then from client config.
  """
  @spec bulk_delete_shifts([integer()] | params(), client_opts()) :: :ok | {:error, Error.t()}
  def bulk_delete_shifts(ids_or_params, opts \\ []) do
    with {:ok, config} <- Config.new(opts),
         {:ok, body} <- build_bulk_delete_body(ids_or_params, config) do
      path = "/shift_management/shifts/bulk_delete"

      case request(:post, path, body, [], config) do
        {:ok, %{status: status}} when status in [200, 204] -> :ok
        {:ok, %{status: status, body: body}} -> http_error(status, body, :post, path)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp request(method, path, body, params, opts) do
    with {:ok, config} <- Config.new(opts) do
      url = resource_url(config, path)
      req_opts = build_req_options(method, url, body, params, config)
      meta = %{method: method, path: path, url: url}
      start_time = System.monotonic_time()

      telemetry([:factorial_hr_ex, :request, :start], %{system_time: System.system_time()}, meta)

      case Req.request(req_opts) do
        {:ok, %Req.Response{} = response} ->
          telemetry(
            [:factorial_hr_ex, :request, :stop],
            %{duration: System.monotonic_time() - start_time},
            Map.put(meta, :status, response.status)
          )

          {:ok, response}

        {:error, %Req.TransportError{reason: reason}} ->
          error = Error.new(:transport_error, reason: reason, request: meta)

          telemetry(
            [:factorial_hr_ex, :request, :exception],
            %{duration: System.monotonic_time() - start_time},
            Map.merge(meta, %{kind: :transport_error, reason: reason})
          )

          {:error, error}

        {:error, reason} ->
          error = Error.new(:request_error, reason: reason, request: meta)

          telemetry(
            [:factorial_hr_ex, :request, :exception],
            %{duration: System.monotonic_time() - start_time},
            Map.merge(meta, %{kind: :request_error, reason: reason})
          )

          {:error, error}
      end
    end
  end

  defp normalize_public_response({:ok, %{status: status} = response}, _method, _path)
       when status >= 200 and status < 300 do
    {:ok, response}
  end

  defp normalize_public_response({:ok, %{status: status, body: body}}, method, path) do
    http_error(status, body, method, path)
  end

  defp normalize_public_response({:error, reason}, _method, _path), do: {:error, reason}

  defp build_req_options(method, url, body, params, config) do
    [
      method: method,
      url: url,
      headers: [
        auth_header(config),
        {"accept", "application/json"},
        {"content-type", "application/json"},
        {"user-agent", @user_agent}
      ],
      receive_timeout: config.receive_timeout,
      retry: false
    ]
    |> maybe_put_params(params)
    |> maybe_put_json(body)
    |> Keyword.merge(config.req_options)
  end

  defp maybe_put_params(opts, params) do
    params = normalize_params(params)

    if params == [] do
      opts
    else
      Keyword.put(opts, :params, params)
    end
  end

  defp maybe_put_json(opts, nil), do: opts
  defp maybe_put_json(opts, body), do: Keyword.put(opts, :json, body)

  defp auth_header(%Config{auth_mode: :bearer, token: token}),
    do: {"authorization", "Bearer #{token}"}

  defp auth_header(%Config{auth_mode: :api_key, token: token}), do: {"x-api-key", token}

  defp resource_url(%Config{} = config, path) when is_binary(path) do
    cond do
      String.starts_with?(path, "http://") or String.starts_with?(path, "https://") ->
        path

      String.starts_with?(path, "/api/") ->
        config.base_url <> path

      true ->
        config.base_url <> "/api/#{config.api_version}/resources" <> normalize_resource_path(path)
    end
  end

  defp normalize_resource_path(path) when is_binary(path) do
    if String.starts_with?(path, "/"), do: path, else: "/" <> path
  end

  defp fetch_batched_collection(path, params, collection_name, opts) do
    employee_ids = repeated_values(params, "employee_ids[]")

    if length(employee_ids) > @employee_filter_batch_size do
      employee_ids
      |> Enum.chunk_every(@employee_filter_batch_size)
      |> Enum.reduce_while({:ok, []}, fn batch, {:ok, acc} ->
        batch_params =
          params
          |> reject_param("employee_ids[]")
          |> put_repeated_param("employee_ids[]", batch)

        case all(path, batch_params, collection_name, opts) do
          {:ok, records} -> {:cont, {:ok, acc ++ records}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
      |> dedupe_collection()
    else
      all(path, params, collection_name, opts)
    end
  end

  defp dedupe_collection({:ok, records}) do
    {:ok,
     Enum.uniq_by(records, fn
       %{"id" => id} when not is_nil(id) -> {:id, id}
       record -> {:record, record}
     end)}
  end

  defp dedupe_collection(result), do: result

  defp fetch_all_pages(path, params, collection_name, config, accumulated, cursor) do
    params_with_cursor = put_param(params, "after_id", cursor)

    case request(:get, path, nil, params_with_cursor, config) do
      {:ok, %{status: 200, body: body}} ->
        with {:ok, records, meta} <- parse_collection_response(body, collection_name) do
          all_records = accumulated ++ records
          end_cursor = Map.get(meta, "end_cursor")

          if Map.get(meta, "has_next_page", false) and valid_next_cursor?(cursor, end_cursor) do
            fetch_all_pages(path, params, collection_name, config, all_records, end_cursor)
          else
            {:ok, all_records}
          end
        end

      {:ok, %{status: status, body: body}} ->
        http_error(status, body, :get, path)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_collection_response(body, _collection_name) when is_list(body), do: {:ok, body, %{}}

  defp parse_collection_response(%{"data" => records} = body, _collection_name)
       when is_list(records) do
    {:ok, records, Map.get(body, "meta", %{})}
  end

  defp parse_collection_response(body, collection_name)
       when is_binary(collection_name) and is_map(body) do
    case Map.get(body, collection_name) do
      records when is_list(records) -> {:ok, records, Map.get(body, "meta", %{})}
      _other -> unexpected_response(body)
    end
  end

  defp parse_collection_response(body, _collection_name), do: unexpected_response(body)

  defp unexpected_response(body) do
    {:error, Error.new(:unexpected_response, body: body)}
  end

  defp http_error(status, body, method, path) do
    {:error,
     Error.new(:http_error, status: status, body: body, request: %{method: method, path: path})}
  end

  defp normalize_shift_management_params(params) do
    params
    |> normalize_params()
    |> rename_repeated_param(:employee_ids, "employee_ids[]")
    |> rename_repeated_param("employee_ids", "employee_ids[]")
    |> rename_repeated_param(:location_ids, "location_ids[]")
    |> rename_repeated_param("location_ids", "location_ids[]")
    |> rename_repeated_param(:only_states, "only_states[]")
    |> rename_repeated_param("only_states", "only_states[]")
    |> rename_param(:start_at, "start_at")
    |> rename_param(:end_at, "end_at")
    |> rename_param(:only_published, "only_published")
    |> rename_param(:split_overnight_shifts, "split_overnight_shifts")
  end

  defp normalize_params(nil), do: []
  defp normalize_params(params) when is_list(params), do: params
  defp normalize_params(params) when is_map(params), do: Map.to_list(params)

  defp put_param(params, _key, nil), do: params
  defp put_param(params, key, value), do: [{key, value} | reject_param(params, key)]

  defp put_repeated_param(params, _key, nil), do: params

  defp put_repeated_param(params, key, values) when is_list(values) do
    Enum.reduce(values, params, fn value, acc -> [{key, value} | acc] end)
  end

  defp put_repeated_param(params, key, value), do: [{key, value} | params]

  defp reject_param(params, key) do
    Enum.reject(params, fn {param_key, _value} -> param_key == key end)
  end

  defp repeated_values(params, key) do
    params
    |> Enum.filter(fn {param_key, _value} -> param_key == key end)
    |> Enum.map(fn {_key, value} -> value end)
  end

  defp rename_repeated_param(params, source, target) do
    values =
      params
      |> Enum.filter(fn {key, _value} -> key == source end)
      |> Enum.flat_map(fn {_key, value} -> List.wrap(value) end)

    params
    |> reject_param(source)
    |> put_repeated_param(target, values)
  end

  defp rename_param(params, source, target) do
    case Enum.find(params, fn {key, _value} -> key == source end) do
      nil ->
        params

      {_key, value} ->
        params
        |> reject_param(source)
        |> put_param(target, value)
    end
  end

  defp build_shift_bodies(shifts, config) do
    shifts
    |> Enum.reduce_while({:ok, []}, fn shift, {:ok, acc} ->
      case build_shift_body(shift, config) do
        {:ok, body} -> {:cont, {:ok, [body | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, bodies} -> {:ok, Enum.reverse(bodies)}
      error -> error
    end
  end

  defp build_shift_body(params, config) do
    company_id = param_value(params, :company_id) || Config.parse_int(config.company_id)

    if is_nil(company_id) or company_id == "" do
      {:error, Error.new(:invalid_request, reason: :company_id_missing)}
    else
      {:ok,
       %{
         "employee_id" => param_value(params, :employee_id),
         "start_at" => param_value(params, :start_at),
         "end_at" => param_value(params, :end_at),
         "company_id" => company_id
       }
       |> maybe_put("name", param_value(params, :name))
       |> maybe_put("notes", param_value(params, :notes))
       |> maybe_put("location_id", param_value(params, :location_id))
       |> maybe_put("work_area_id", param_value(params, :work_area_id))}
    end
  end

  defp created_shifts(body) when is_list(body), do: body
  defp created_shifts(%{"shifts" => shifts}) when is_list(shifts), do: shifts
  defp created_shifts(%{"data" => shifts}) when is_list(shifts), do: shifts
  defp created_shifts(_body), do: []

  defp build_bulk_delete_body([], _config) do
    {:error, Error.new(:invalid_request, reason: :ids_missing)}
  end

  defp build_bulk_delete_body(ids_or_params, config) when is_list(ids_or_params) do
    if Keyword.keyword?(ids_or_params) do
      ids_or_params
      |> Map.new()
      |> build_bulk_delete_body(config)
    else
      build_ids_bulk_delete_body(ids_or_params, config)
    end
  end

  defp build_bulk_delete_body(params, config) when is_map(params) do
    body = params |> normalize_params() |> Map.new()

    author_id =
      Map.get(body, "author_id") || Map.get(body, :author_id) ||
        Config.parse_int(config.author_id)

    with :ok <- validate_bulk_delete_ids(body),
         :ok <- validate_author_id(author_id) do
      {:ok, body |> stringify_keys() |> Map.put("author_id", author_id)}
    end
  end

  defp build_ids_bulk_delete_body(ids, config) do
    if Enum.all?(ids, &is_integer/1) do
      build_bulk_delete_body(%{"ids" => ids}, config)
    else
      {:error, Error.new(:invalid_request, reason: :invalid_ids)}
    end
  end

  defp validate_bulk_delete_ids(body) do
    ids = Map.get(body, "ids") || Map.get(body, :ids)

    cond do
      is_nil(ids) ->
        :ok

      ids == [] ->
        {:error, Error.new(:invalid_request, reason: :ids_missing)}

      is_list(ids) and Enum.all?(ids, &is_integer/1) ->
        :ok

      true ->
        {:error, Error.new(:invalid_request, reason: :invalid_ids)}
    end
  end

  defp validate_author_id(author_id) do
    if is_nil(author_id) or author_id == "" do
      {:error, Error.new(:invalid_request, reason: :author_id_missing)}
    else
      :ok
    end
  end

  defp param_value(params, key) when is_map(params) do
    Map.get(params, key) || Map.get(params, Atom.to_string(key))
  end

  defp param_value(_params, _key), do: nil

  defp maybe_put(body, _key, nil), do: body
  defp maybe_put(body, key, value), do: Map.put(body, key, value)

  defp stringify_keys(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp team_employee_ids(%{"employee_ids" => ids}) when is_list(ids), do: ids

  defp team_employee_ids(%{"employees" => employees}) when is_list(employees) do
    Enum.flat_map(employees, fn
      %{"id" => id} -> [id]
      id when is_integer(id) -> [id]
      _other -> []
    end)
  end

  defp team_employee_ids(_team), do: []

  defp valid_next_cursor?(current_cursor, next_cursor) do
    is_binary(next_cursor) and next_cursor != "" and next_cursor != current_cursor
  end

  defp format_date(%Date{} = date), do: Date.to_iso8601(date)
  defp format_date(date) when is_binary(date), do: date

  defp telemetry(event, measurements, metadata) do
    if Code.ensure_loaded?(:telemetry) do
      :telemetry.execute(event, measurements, metadata)
    end
  end
end
