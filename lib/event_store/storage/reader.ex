defmodule EventStore.Storage.Reader do
  @moduledoc """
  Reads events for a given stream identity
  """

  require Logger

  alias EventStore.RecordedEvent
  alias EventStore.Sql.Statements
  alias EventStore.Storage.Reader

  @doc """
  Read events appended to a single stream forward from the given starting version
  """
  def read_forward(conn, stream_id, start_version, count) do
    case Reader.Query.read_events_forward(conn, stream_id, start_version, count) do
      {:ok, []} = reply -> reply
      {:ok, rows} -> map_rows_to_event_data(rows)
      {:error, reason} -> failed_to_read(stream_id, reason)
    end
  end

  @doc """
  Read events appended to all streams forward from the given start event id inclusive
  """
  def read_all_forward(conn, start_event_id, count) do
    case Reader.Query.read_all_events_forward(conn, start_event_id, count) do
      {:ok, []} = reply -> reply
      {:ok, rows} -> map_rows_to_event_data(rows)
      {:error, reason} -> failed_to_read_all_stream(reason)
    end
  end

  defp map_rows_to_event_data(rows) do
    {:ok, Reader.EventAdapter.to_event_data(rows)}
  end

  defp failed_to_read(stream_id, reason) do
    _ = Logger.warn(fn -> "failed to read events from stream id #{stream_id} due to #{inspect reason}" end)
    {:error, reason}
  end

  defp failed_to_read_all_stream(reason) do
    _ = Logger.warn(fn -> "failed to read events from all streams due to #{inspect reason}" end)
    {:error, reason}
  end

  defmodule EventAdapter do
    @moduledoc """
    Map event data from the database to `RecordedEvent` struct
    """

    def to_event_data(rows) do
      rows
      |> Enum.map(&to_event_data_from_row/1)
    end

    def to_event_data_from_row([event_id, stream_id, stream_version, event_type, correlation_id, causation_id, data, metadata, created_at]) do
      %RecordedEvent{
        event_id: event_id,
        stream_id: stream_id,
        stream_version: stream_version,
        event_type: event_type,
        correlation_id: correlation_id,
        causation_id: causation_id,
        data: data,
        metadata: metadata,
        created_at: to_naive(created_at),
      }
    end

    defp to_naive(%NaiveDateTime{} = naive), do: naive
    defp to_naive(%Postgrex.Timestamp{year: year, month: month, day: day, hour: hour, min: minute, sec: second, usec: microsecond}) do
      {:ok, naive} = NaiveDateTime.new(year, month, day, hour, minute, second, {microsecond,  6})
      naive
    end
  end

  defmodule Query do
    def read_events_forward(conn, stream_id, start_version, count) do
      conn
      |> Postgrex.query(Statements.read_events_forward, [stream_id, start_version, count], pool: DBConnection.Poolboy)
      |> handle_response
    end

    def read_all_events_forward(conn, start_event_id, count) do
      conn
      |> Postgrex.query(Statements.read_all_events_forward, [start_event_id, count], pool: DBConnection.Poolboy)
      |> handle_response
    end

    defp handle_response({:ok, %Postgrex.Result{num_rows: 0}}) do
      {:ok, []}
    end

    defp handle_response({:ok, %Postgrex.Result{rows: rows}}) do
      {:ok, rows}
    end

    defp handle_response({:error, %Postgrex.Error{postgres: %{message: reason}}}) do
      _ = Logger.warn(fn -> "failed to read events from stream due to: #{inspect reason}" end)
      {:error, reason}
    end
  end
end
