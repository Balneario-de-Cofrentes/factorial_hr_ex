defmodule FactorialHRTest do
  use ExUnit.Case, async: false

  alias FactorialHR.Error

  @opts [
    api_key: "test-key",
    api_version: "2026-04-01",
    req_options: [plug: {Req.Test, __MODULE__}, retry: false]
  ]

  test "sends x-api-key auth by default" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert Plug.Conn.get_req_header(conn, "x-api-key") == ["test-key"]
      assert Plug.Conn.get_req_header(conn, "authorization") == []
      assert conn.request_path == "/api/2026-04-01/resources/employees/employees"

      Req.Test.json(conn, %{"data" => []})
    end)

    assert {:ok, []} = FactorialHR.list_employees([], @opts)
  end

  test "sends bearer auth when configured" do
    opts =
      Keyword.merge(@opts,
        auth_mode: :bearer,
        access_token: "bearer-token"
      )

    Req.Test.stub(__MODULE__, fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer bearer-token"]
      assert Plug.Conn.get_req_header(conn, "x-api-key") == []

      Req.Test.json(conn, %{"data" => []})
    end)

    assert {:ok, []} = FactorialHR.list_locations([], opts)
  end

  test "preserves required headers when req options include custom headers" do
    req_options =
      @opts
      |> Keyword.fetch!(:req_options)
      |> Keyword.put(:headers, [
        {"x-extra", "1"},
        {"x-api-key", "wrong"},
        {"accept", "text/plain"}
      ])

    opts = Keyword.put(@opts, :req_options, req_options)

    Req.Test.stub(__MODULE__, fn conn ->
      assert Plug.Conn.get_req_header(conn, "x-extra") == ["1"]
      assert Plug.Conn.get_req_header(conn, "x-api-key") == ["test-key"]
      assert Plug.Conn.get_req_header(conn, "accept") == ["application/json"]

      Req.Test.json(conn, %{"data" => []})
    end)

    assert {:ok, []} = FactorialHR.list_employees([], opts)
  end

  test "low-level get returns raw response for successful requests" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/2026-04-01/resources/employees/employees"

      Req.Test.json(conn, %{"data" => [%{"id" => 1}]})
    end)

    assert {:ok, response} = FactorialHR.get("/employees/employees", [], @opts)
    assert response.status == 200
    assert response.body == %{"data" => [%{"id" => 1}]}
  end

  test "low-level get returns structured errors for non-success responses" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(403)
      |> Req.Test.json(%{"error" => "forbidden"})
    end)

    assert {:error, %Error{type: :http_error, status: 403, body: %{"error" => "forbidden"}}} =
             FactorialHR.get("/employees/employees", [], @opts)
  end

  test "infers base URL and version from a full Factorial API URL" do
    opts =
      @opts
      |> Keyword.delete(:api_version)
      |> Keyword.put(:api_url, "https://factorial.test/api/2025-10-01/resources/shift_management")

    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/2025-10-01/resources/locations/work_areas"

      Req.Test.json(conn, %{"data" => []})
    end)

    assert {:ok, []} = FactorialHR.list_work_areas([], opts)
  end

  test "returns structured config errors for invalid URLs and versions" do
    assert {:error, %Error{type: :invalid_config, reason: :base_url_invalid}} =
             FactorialHR.list_employees([], Keyword.put(@opts, :base_url, 123))

    assert {:error, %Error{type: :invalid_config, reason: :api_url_invalid}} =
             FactorialHR.list_employees([], Keyword.put(@opts, :api_url, 123))

    assert {:error, %Error{type: :invalid_config, reason: :api_version_invalid}} =
             FactorialHR.list_employees([], Keyword.put(@opts, :api_version, 123))
  end

  test "follows cursor pagination" do
    Req.Test.stub(__MODULE__, fn conn ->
      case Plug.Conn.Query.decode(conn.query_string)["after_id"] do
        nil ->
          Req.Test.json(conn, %{
            "data" => [%{"id" => 1}],
            "meta" => %{"has_next_page" => true, "end_cursor" => "cursor-1"}
          })

        "cursor-1" ->
          Req.Test.json(conn, %{
            "data" => [%{"id" => 2}],
            "meta" => %{"has_next_page" => false}
          })
      end
    end)

    assert {:ok, records} = FactorialHR.list_employees([limit: 1], @opts)
    assert Enum.map(records, & &1["id"]) == [1, 2]
  end

  test "lists shift-management shifts with repeated array parameters" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/2026-04-01/resources/shift_management/shifts"
      assert conn.query_string =~ "employee_ids%5B%5D=42"
      assert conn.query_string =~ "location_ids%5B%5D=7"
      assert conn.query_string =~ "only_states%5B%5D=draft"
      assert conn.query_string =~ "only_states%5B%5D=published"
      assert conn.query_string =~ "only_published=false"
      assert conn.query_string =~ "split_overnight_shifts=true"

      Req.Test.json(conn, %{"data" => [%{"id" => 1}]})
    end)

    assert {:ok, [%{"id" => 1}]} =
             FactorialHR.list_shifts(
               [
                 employee_ids: [42],
                 location_ids: [7],
                 start_at: "2026-06-01",
                 end_at: "2026-06-30",
                 only_states: ["draft", "published"],
                 only_published: false,
                 split_overnight_shifts: true
               ],
               @opts
             )
  end

  test "batches large employee filters and deduplicates by id" do
    {:ok, agent} = Agent.start(fn -> [] end)
    on_exit(fn -> Agent.stop(agent) end)

    Req.Test.stub(__MODULE__, fn conn ->
      Agent.update(agent, &[conn.query_string | &1])
      Req.Test.json(conn, %{"data" => [%{"id" => 1}]})
    end)

    assert {:ok, [%{"id" => 1}]} =
             FactorialHR.list_shifts([employee_ids: Enum.to_list(1..101)], @opts)

    queries = Agent.get(agent, & &1)
    assert length(queries) == 3

    assert Enum.all?(queries, fn query ->
             query
             |> String.split("employee_ids%5B%5D=", trim: true)
             |> length()
             |> Kernel.<=(51)
           end)
  end

  test "lists attendance shifts with start_on and end_on" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/2026-04-01/resources/attendance/shifts"

      query = Plug.Conn.Query.decode(conn.query_string)
      assert query["start_on"] == "2026-06-01"
      assert query["end_on"] == "2026-06-30"

      Req.Test.json(conn, %{"data" => [%{"id" => 10}]})
    end)

    assert {:ok, [%{"id" => 10}]} =
             FactorialHR.list_attendance_shifts(~D[2026-06-01], ~D[2026-06-30], [], @opts)
  end

  test "creates a shift with company id from config" do
    opts = Keyword.put(@opts, :company_id, "12345")

    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)

      assert conn.method == "POST"
      assert conn.request_path == "/api/2026-04-01/resources/shift_management/shifts"
      assert decoded["company_id"] == 12_345
      assert decoded["employee_id"] == 42
      assert decoded["location_id"] == 7
      assert decoded["work_area_id"] == 8

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{"id" => 999})
    end)

    assert {:ok, %{"id" => 999}} =
             FactorialHR.create_shift(
               %{
                 employee_id: 42,
                 start_at: "2026-06-01T08:00:00Z",
                 end_at: "2026-06-01T16:00:00Z",
                 location_id: 7,
                 work_area_id: 8
               },
               opts
             )
  end

  test "creates a shift with company id from params" do
    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)

      assert decoded["company_id"] == 12_345
      assert decoded["employee_id"] == 42
      assert decoded["location_id"] == 7
      assert decoded["work_area_id"] == 8

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{"id" => 999})
    end)

    assert {:ok, %{"id" => 999}} =
             FactorialHR.create_shift(
               %{
                 employee_id: "42",
                 start_at: "2026-06-01T08:00:00Z",
                 end_at: "2026-06-01T16:00:00Z",
                 company_id: "12345",
                 location_id: "7",
                 work_area_id: "8"
               },
               @opts
             )
  end

  test "returns structured invalid request errors when required shift fields are missing" do
    valid_shift = %{
      employee_id: 42,
      start_at: "2026-06-01T08:00:00Z",
      end_at: "2026-06-01T16:00:00Z"
    }

    opts = Keyword.put(@opts, :company_id, "12345")

    assert {:error, %Error{type: :invalid_request, reason: :employee_id_missing}} =
             valid_shift
             |> Map.delete(:employee_id)
             |> FactorialHR.create_shift(opts)

    assert {:error, %Error{type: :invalid_request, reason: :start_at_missing}} =
             valid_shift
             |> Map.delete(:start_at)
             |> FactorialHR.create_shift(opts)

    assert {:error, %Error{type: :invalid_request, reason: :end_at_missing}} =
             valid_shift
             |> Map.delete(:end_at)
             |> FactorialHR.create_shift(opts)
  end

  test "returns structured invalid request error when company id is missing" do
    assert {:error, %Error{type: :invalid_request, reason: :company_id_missing}} =
             FactorialHR.create_shift(
               %{
                 employee_id: 42,
                 start_at: "2026-06-01T08:00:00Z",
                 end_at: "2026-06-01T16:00:00Z"
               },
               @opts
             )
  end

  test "bulk create returns an unexpected response error for unknown success payloads" do
    opts = Keyword.put(@opts, :company_id, "12345")

    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{"unexpected" => []})
    end)

    assert {:error, %Error{type: :unexpected_response, body: %{"unexpected" => []}}} =
             FactorialHR.bulk_create_shifts(
               [
                 %{
                   employee_id: 42,
                   start_at: "2026-06-01T08:00:00Z",
                   end_at: "2026-06-01T16:00:00Z"
                 }
               ],
               opts
             )
  end

  test "bulk deletes shifts with author id from config" do
    opts = Keyword.put(@opts, :author_id, "456")

    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)

      assert conn.request_path == "/api/2026-04-01/resources/shift_management/shifts/bulk_delete"
      assert decoded["ids"] == [100, 101]
      assert decoded["author_id"] == 456

      conn
      |> Plug.Conn.put_status(200)
      |> Req.Test.json(%{})
    end)

    assert :ok = FactorialHR.bulk_delete_shifts([100, 101], opts)
  end

  test "bulk delete rejects an empty id list" do
    opts = Keyword.put(@opts, :author_id, "456")

    assert {:error, %Error{type: :invalid_request, reason: :ids_missing}} =
             FactorialHR.bulk_delete_shifts([], opts)
  end

  test "bulk delete rejects invalid ids" do
    opts = Keyword.put(@opts, :author_id, "456")

    assert {:error, %Error{type: :invalid_request, reason: :invalid_ids}} =
             FactorialHR.bulk_delete_shifts([100, "101"], opts)
  end

  test "bulk delete rejects requests without ids or filter selectors" do
    opts = Keyword.put(@opts, :author_id, "456")

    assert {:error, %Error{type: :invalid_request, reason: :bulk_delete_selector_missing}} =
             FactorialHR.bulk_delete_shifts(%{}, opts)

    assert {:error, %Error{type: :invalid_request, reason: :bulk_delete_selector_missing}} =
             FactorialHR.bulk_delete_shifts([author_id: 456], opts)
  end

  test "bulk delete accepts filter params without ids" do
    opts = Keyword.put(@opts, :author_id, "456")

    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)

      assert decoded["employee_ids"] == [42]
      assert decoded["start_at"] == "2026-06-01T00:00:00Z"
      assert decoded["end_at"] == "2026-06-30T23:59:59Z"
      assert decoded["author_id"] == 456

      conn
      |> Plug.Conn.put_status(204)
      |> Req.Test.json(%{})
    end)

    assert :ok =
             FactorialHR.bulk_delete_shifts(
               [
                 employee_ids: [42],
                 start_at: "2026-06-01T00:00:00Z",
                 end_at: "2026-06-30T23:59:59Z"
               ],
               opts
             )
  end

  test "returns structured http errors" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(401)
      |> Req.Test.json(%{"error" => "unauthorized"})
    end)

    assert {:error, %Error{type: :http_error, status: 401, body: %{"error" => "unauthorized"}}} =
             FactorialHR.list_contract_versions([], @opts)
  end
end
