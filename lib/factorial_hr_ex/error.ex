defmodule FactorialHREx.Error do
  @moduledoc """
  Structured error returned by `FactorialHREx` operations.

  The client returns errors as `{:error, %FactorialHREx.Error{}}` so callers can
  branch on stable fields without parsing log messages or response bodies.
  """

  @type t :: %__MODULE__{
          type: atom(),
          message: String.t(),
          status: pos_integer() | nil,
          body: term(),
          reason: term(),
          request: map()
        }

  defexception [:type, :message, :status, :body, :reason, :request]

  @doc false
  @spec new(atom(), keyword()) :: t()
  def new(type, attrs \\ []) do
    %__MODULE__{
      type: type,
      message: Keyword.get(attrs, :message) || default_message(type, attrs),
      status: Keyword.get(attrs, :status),
      body: Keyword.get(attrs, :body),
      reason: Keyword.get(attrs, :reason),
      request: Keyword.get(attrs, :request, %{})
    }
  end

  defp default_message(:config_missing, _attrs), do: "Factorial API configuration is missing"

  defp default_message(:http_error, attrs) do
    "Factorial API request failed with status #{Keyword.get(attrs, :status)}"
  end

  defp default_message(:transport_error, attrs) do
    "Factorial API transport error: #{inspect(Keyword.get(attrs, :reason))}"
  end

  defp default_message(:unexpected_response, _attrs),
    do: "Factorial API returned an unexpected response"

  defp default_message(:invalid_request, attrs), do: inspect(Keyword.get(attrs, :reason))
  defp default_message(type, _attrs), do: "Factorial API error: #{type}"
end
