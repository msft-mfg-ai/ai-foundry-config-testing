# sample code to create an Azure AI Agent using OpenAPI tools
# This code uses the Azure AI Agents SDK to create an agent that can interact with OpenAPI
# services, such as a weather API. It demonstrates how to set up the agent, define tools,
# and invoke the agent with a user message to get a response.
# Make sure to have the necessary environment variables.

# This code can be executed in on a VM running in the same VNET as the Azure AI Foundry
# SSH to VM and copy contents of agents directory to the VM
# Then:
# 1. Install uv: curl -LsSf https://astral.sh/uv/install.sh | sh
# 2. Get python: uv python install
# 3. Install dependencies: uv sync
# 4. Run the script: uv run agent.py


import asyncio
from datetime import date
import os
from azure.identity import DefaultAzureCredential, AzureDeveloperCliCredential
from azure.ai.agents.models import (
    ToolDefinition,
)
from azure.ai.agents.models import (
    OpenApiTool,
    OpenApiAnonymousAuthDetails,
)
import jsonref
from typing import Optional
from azure.ai.agents.models import Agent

from semantic_kernel.agents import (
    AzureAIAgent,
    AzureAIAgentThread,
    AzureAIAgentSettings,
)

from dotenv import load_dotenv

# Load environment variables from the .env file
load_dotenv(override=True)

endpoint = os.environ.get("AZURE_AI_FOUNDRY_CONNECTION_STRING")
deployment_name = os.environ.get("AZURE_OPENAI_CHAT_DEPLOYMENT_NAME")
api_version = os.environ.get("AZURE_OPENAI_API_VERSION", None)
tenant_id = os.environ.get("AZURE_TENANT_ID", None)
openapi_server_url = os.environ.get("OPENAPI_SERVER_URL", None)

ai_agent_settings = AzureAIAgentSettings(
    endpoint=endpoint,
    model_deployment_name=deployment_name,
    api_version=api_version,
)
print(ai_agent_settings)

creds = (
    AzureDeveloperCliCredential(tenant_id=tenant_id)
    if os.environ.get("USE_AZURE_DEV_CLI") == "true"
    else DefaultAzureCredential()
)
# uncomment to test token aquisition
# token_test  = creds.get_token("https://ai.azure.com")
# print(f"Token for https://ai.azure.com: {token_test.token[:10]}...")

client = AzureAIAgent.create_client(
    credential=creds,
    endpoint=ai_agent_settings.endpoint,
    api_version=ai_agent_settings.api_version,
)

agent_instructions = (
    "You are a reliable, funny and amusing weather forecaster named Jonny Weather. "
    "You provide weather forecasts in a humorous and engaging manner. "
    "You like to use puns and jokes to make the weather more entertaining. "
    "You love to use emojis to make your forecasts more colorful and fun. "
    "You provide weather forecasts in table format, for the next 2 days, including temperature, humidity, precipitation, and wind speed. "
    "If you don't know the forecast, say 'I don't know' or 'I don't have that information'."
)


async def create_agent(
    agent_name: str,
    agent_instructions: str,
    agent_definition: Optional[Agent],
    tools: list[ToolDefinition],
) -> AzureAIAgent:
    if agent_definition:
        print(
            f"Found existing agent with ID: {agent_definition.id} and name: {agent_definition.name}"
        )
        agent_definition = await client.agents.update_agent(
            agent_id=agent_definition.id,
            instructions=agent_instructions,
            model=ai_agent_settings.model_deployment_name,
            tools=tools,
            temperature=0.2,
        )
        print(
            f"Updated agent with id {agent_definition.id} name: {agent_name} with model {ai_agent_settings.model_deployment_name}"
        )
    else:
        agent_definition = await client.agents.create_agent(
            model=ai_agent_settings.model_deployment_name,
            name=agent_name,
            instructions=agent_instructions,
            tools=tools,
            temperature=0.2,
        )
        print(
            f"Created agent with id {agent_definition.id} name: {agent_name} with model {ai_agent_settings.model_deployment_name}"
        )

    agent = AzureAIAgent(
        client=client,
        definition=agent_definition,
    )
    return agent


async def run():
    agent_definition_openapi = None
    agent_name_openapi = "Jonny_Weather_openapi"

    # List agents
    print("\n --- Agents ---")
    async for agent in client.agents.list_agents():
        print(
            f"Agent ID: {agent.id}, Name: {agent.name}, Description: {agent.description}, Deployment Name: {agent.model}"
        )
        if agent.name == agent_name_openapi and agent_definition_openapi is None:
            agent_definition_openapi = agent

    print("\n --- Connections ---")
    # List connections
    async for connection in client.connections.list():
        print(
            f"Connection ID: {connection.id}, Name: {connection.name}, Type: {connection.type} Default: {connection.is_default}"
        )

    openapi_tools: list[ToolDefinition] = []

    if openapi_server_url:
        with open("weather.json", "r") as f:
            openapi_weather = jsonref.loads(f.read())
            openapi_weather["servers"] = [{"url": openapi_server_url}]

        openapi_tool = OpenApiTool(
            name="WeatherAPI",
            spec=openapi_weather,
            auth=OpenApiAnonymousAuthDetails(),
            description="Retrieve weather information for a location",
            # allowed_tools=[],  # Optional: specify allowed tools
        )
        print(f"Using OpenAPI Tool with server URL: {openapi_server_url}")
        openapi_tools = openapi_tools + openapi_tool.definitions

    agent = await create_agent(
        agent_name=agent_name_openapi,
        agent_instructions=agent_instructions,
        agent_definition=agent_definition_openapi,
        tools=[],
    )

    user_message = "What is the weather forecast for today and tomorrow in Seattle?"

    thread = AzureAIAgentThread(client=client)
    async for agent_response in agent.invoke(
        messages=user_message,
        thread=thread,
        additional_instructions="Today is " + date.today().strftime("%Y-%m-%d"),
    ):
        print(f"OpenAPI Agent: {agent_response}")


asyncio.run(run())
