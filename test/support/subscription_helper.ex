defmodule Absinthe.Test.SubscriptionHelper do
  @moduledoc """
  A Subscription requires a few moving parts to test,
  but for the most part you should be able to use this module
  along with your existing GraphQL schema and be able to run
  queries as if you're a Client using your GraphQL endpoint. 
  """

  defmodule PubSub do
    @behaviour Absinthe.Subscription.Pubsub

    def start_link do
      Registry.start_link(keys: :unique, name: __MODULE__)
    end

    def node_name do
      node()
    end

    def subscribe(topic) do
      Registry.register(__MODULE__, topic, [])
      :ok
    end

    def publish_subscription(topic, data) do
      message = %{
        topic: topic,
        event: "subscription:data",
        result: data
      }

      Registry.dispatch(__MODULE__, topic, fn entries ->
        for {pid, _} <- entries, do: send(pid, {:broadcast, message})
      end)
    end

    def publish_mutation(_proxy_topic, _mutation_result, _subscribed_fields) do
      # this pubsub is local and doesn't support clusters
      :ok
    end
  end

  @doc """
  Start our PubSub and use it in place of an Endpoint
  for managing Subscription events.
  """
  def start do
    {:ok, _} = PubSub.start_link()
    Absinthe.Subscription.start_link(PubSub)
  end

  @doc """
  Run an Absinthe query with PubSub added to context.
  We also want to subscribe to the topic at the PubSub level
  so that when a publish event happens, our PubSub receives
  a message.
  """
  def run(query, schema, opts \\ []) do
    opts = Keyword.update(opts, :context, %{pubsub: PubSub}, &Map.put(&1, :pubsub, PubSub))

    case Absinthe.run(query, schema, opts) do
      {:ok, %{"subscribed" => topic}} = val ->
        PubSub.subscribe(topic)
        val

      val ->
        val
    end
  end

  @doc "Publish the result of a mutation to a list of topics"
  def publish(mutation_result, topic_list) do
    :ok = Absinthe.Subscription.publish(PubSub, mutation_result, topic_list)
  end

  def get_pubsub, do: PubSub
