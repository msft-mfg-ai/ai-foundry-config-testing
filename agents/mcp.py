from datetime import date
import os
import logging
from azure.identity import DefaultAzureCredential, AzureDeveloperCliCredential
from semantic_kernel.contents.chat_message_content import ChatMessageContent
from azure.ai.agents.models import McpTool, ToolDefinition
from semantic_kernel.contents import FunctionCallContent, FunctionResultContent
import asyncio
from semantic_kernel.agents import (
    AzureAIAgent,
    AzureAIAgentThread,
    AzureAIAgentSettings,
)
from dotenv import load_dotenv

# Configure logging for debug
logging.basicConfig(
    level=logging.DEBUG, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)

# Set specific loggers to debug level
logging.getLogger("semantic_kernel").setLevel(logging.DEBUG)
logging.getLogger("azure.ai.agents").setLevel(logging.DEBUG)
logging.getLogger("azure.core.pipeline").setLevel(logging.WARNING)

# Load environment variables from the .env file
load_dotenv(override=True)

endpoint = os.environ.get("AZURE_AI_FOUNDRY_CONNECTION_STRING")
deployment_name = os.environ.get("AZURE_OPENAI_CHAT_DEPLOYMENT_NAME")
api_version = os.environ.get("AZURE_OPENAI_API_VERSION", None)
tenant_id = os.environ.get("AZURE_TENANT_ID", None)

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


async def create_agent(
    agent_name: str, agent_instructions: str, tools: list[ToolDefinition]
) -> AzureAIAgent:

    agent_definition = None
    async for agent in client.agents.list_agents():
        if agent.name == agent_name and agent_definition is None:
            agent_definition = agent
            break

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


async def on_intermediate_message(agent_response: ChatMessageContent):
    print(f"Intermediate response from MCP Agent: {agent_response}")
    for item in agent_response.items or []:
        if isinstance(item, FunctionResultContent):
            print(f"Function Result:> {item.result} for function: {item.name}")
        elif isinstance(item, FunctionCallContent):
            print(f"Function Call:> {item.name} with arguments: {item.arguments}")
        else:
            print(f"{item}")


async def test_mcp_agent():
    mcp_server_url = os.environ.get("MCP_SERVER_URL", None)
    mcp_server_label = os.environ.get("MCP_SERVER_LABEL", "tool")

    mcp_tool = McpTool(
        server_label=mcp_server_label,
        server_url=mcp_server_url,
    )
    mcp_tool.set_approval_mode("never")
    agent_tools: list[ToolDefinition] = [] + mcp_tool.definitions

    agent = await create_agent(
        agent_name="MCP-Agent",
        agent_instructions="you are a helpful assistant",
        tools=agent_tools,
    )

    mcp_thread = AzureAIAgentThread(client=client)
    async for agent_response in agent.invoke(
        messages="what's the weather in Cary,NC?",
        thread=mcp_thread,
        additional_instructions="Today is " + date.today().strftime("%Y-%m-%d"),
        tools=mcp_tool.resources,
        on_intermediate_message=on_intermediate_message,
    ):
        print(f"MCP Agent: {agent_response}")
        mcp_thread = agent_response.thread


asyncio.run(test_mcp_agent())
