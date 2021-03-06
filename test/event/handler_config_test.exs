defmodule Commanded.Event.HandlerConfigTest do
  use Commanded.StorageCase

  defmodule DefaultConfigHandler do
    use Commanded.Event.Handler,
      name: __MODULE__
  end

  test "should default to `:eventual` consistency and start from `:origin`" do
    {:ok, handler} = DefaultConfigHandler.start_link()

    assert_config handler, [consistency: :eventual, start_from: :origin]
  end

  describe "global config change to default consistency" do
    test "should default to `:eventual` consistency and start from `:origin`" do
      Mix.Config.persist(commanded: [default_consistency: :strong])
      {:ok, handler} = DefaultConfigHandler.start_link()

      assert_config handler, [consistency: :strong, start_from: :origin]

      Mix.Config.persist(commanded: [default_consistency: :eventual])
    end
  end

  defmodule ExampleHandler do
    use Commanded.Event.Handler,
      name: __MODULE__,
      consistency: :strong,
      start_from: :current
  end

  describe "config provided to `start_link/1`" do
    test "should use config defined in handler" do
      {:ok, handler} = ExampleHandler.start_link()

      assert_config handler, [consistency: :strong, start_from: :current]
    end

    test "should use overriden config when provided" do
      {:ok, handler} = ExampleHandler.start_link(consistency: :eventual, start_from: :origin)

      assert_config handler, [consistency: :eventual, start_from: :origin]
    end

    test "should use default config when not provided" do
      {:ok, handler} = ExampleHandler.start_link(start_from: :origin)

      assert_config handler, [consistency: :strong, start_from: :origin]
    end
  end

  describe "config provided to `child_spec`" do
    test "should use config defined in handler" do
      {:ok, sup} = Supervisor.start_link([
        ExampleHandler,
      ], strategy: :one_for_one)

      [{_, handler, _, _}] = Supervisor.which_children(sup)

      assert_config handler, [consistency: :strong, start_from: :current]
    end

    test "should use overriden config when provided" do
      {:ok, sup} = Supervisor.start_link([
        {ExampleHandler, [consistency: :eventual, start_from: :origin]},
      ], strategy: :one_for_one)

      [{_, handler, _, _}] = Supervisor.which_children(sup)

      assert_config handler, [consistency: :eventual, start_from: :origin]
    end
  end

  defmodule InvalidConfiguredHandler do
    use Commanded.Event.Handler,
      name: __MODULE__,
      invalid_config_option: "invalid"
  end

  test "should validate provided config" do
    assert_raise RuntimeError, "Commanded.Event.HandlerConfigTest.InvalidConfiguredHandler specifies invalid options: [:invalid_config_option]", fn ->
      Code.eval_string """
        alias Commanded.Event.HandlerConfigTest.InvalidConfiguredHandler

        {:ok, _pid} = InvalidConfiguredHandler.start_link()
      """
    end
  end

  defp assert_config(handler, expected_config) do
    actual_config = GenServer.call(handler, :config)

    assert actual_config == expected_config
  end
end
