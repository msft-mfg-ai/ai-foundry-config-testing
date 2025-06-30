# AI Foundry landing zone options

## Option 1 - nothing shared
 ![Nothing shared approach](./Resources/1-nothing_shared.png)
 
## Option 2 - shared AOAI

Each team deploys their own AI Foundry with a connection to shared Azure OpenAI.

 ![Shared AOAI](./Resources/2-shared-models.png)

> [!NOTE]
> OpenAI can use the [spillover feature (preview) for provisioned deployments](https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/spillover-traffic-management
)

> [!WARNING]
> Azure OpenAI resource and Azure AI Foundry account and project must be in the same region.

### Tutorials and materials

* [Using existing OpenAI resource](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/how-to/use-your-own-resources#basic-agent-setup-use-an-existing-azure-openai-resource)

## Option 3 - using AI Gateway (APIM)

Azure API Management can be use as [AI Gateway](https://learn.microsoft.com/en-us/azure/api-management/genai-gateway-capabilities) for AI Foundry.

> [!WARNING]
> AI Gateway for Foundry is currently in private preview supporting Foundry Hub (ML) deployment model.

 ![AI Gateway](./Resources/3-shared-apim.png)

### Tutorials and materials

* [AI Gateway Workshop](https://azure-samples.github.io/AI-Gateway/)
* [AI Gateway Samples](https://github.com/Azure-Samples/ai-gateway)
 
## Option 4 - Shared Azure Open AI and Agent Service resources

Using Foundry with own resources:
 
* **Cosmos DB** for thread management
* **Azure OpenAI** for models
* **Storage** for file storage
* **AI Search** for agent indexes

> [!WARNING]
> Your existing Azure Cosmos DB for NoSQL account used in a standard setup must have a total throughput limit of at least 3000 RU/s. Both provisioned throughput and serverless are supported.
> Three containers will be provisioned in your existing Cosmos DB account, each requiring 1000 RU/s

> [!NOTE]
> Currently there's no way to manage cost of shared resources (Cosmos, Search) in order to execute chargback to application teams.

![Shared Foundry Connections](./Resources/4-shared-foundry-connections.png)


 ## Agent VNET

 Azure AI Foundry Agent Service offers Standard Setup with private networking environment setup, allowing you to bring your own [(BYO) private virtual network](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/how-to/virtual-networks).
