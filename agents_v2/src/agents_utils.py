import os
from azure.ai.projects.models import (
    PromptAgentDefinition,
    Tool,
)
import logging

default_deployment_name = os.environ.get("AZURE_OPENAI_CHAT_DEPLOYMENT_NAME")


class agents_utils:
    def __init__(self, client):
        self.client = client
        pass

    async def get_agents(self):
        logging.info("Getting list of agents")
        all_agents = []
        async for agent in self.client.agents.list():
            all_agents.append(agent)
        return all_agents

    async def create_agent(
        self,
        name: str,
        model_gateway_connection: str = None,
        instructions="You are a helpful assistant that answers general questions",
        deployment_name: str = default_deployment_name,
        delete_before_create: bool = True,
        tools: list[Tool] = [],
    ):
        model = (
            f"{model_gateway_connection}/{deployment_name}"
            if model_gateway_connection
            else deployment_name
        )

        # check if agent "MyV2Agent" exists
        all_agents = await self.get_agents()
        agent_names = [agent.name for agent in all_agents]
        agent = None

        # this is temporary?
        if name in agent_names and delete_before_create:
            # delete the agent because of a bug?
            print(f"Deleting existing agent {name} before creating a new one")
            await self.client.agents.delete(agent_name=name)
            agent_names.remove(name)

        if name not in agent_names:
            agent = await self.client.agents.create(
                name=name,
                definition=PromptAgentDefinition(
                    model=model, instructions=instructions, tools=tools
                ),
            )
            print(
                f"Agent created (id: {agent.id}, name: {agent.name}, version: {agent.versions.latest.version} using model {agent.versions.latest.definition.model})"
            )
        else:
            agent = await self.client.agents.update(
                agent_name=name,
                definition=PromptAgentDefinition(
                    model=model, instructions=instructions, tools=tools
                ),
            )
            print(
                f"Agent updated (id: {agent.id}, name: {agent.name}, version: {agent.versions.latest.version} using model {agent.versions.latest.definition.model})"
            )
        return agent
