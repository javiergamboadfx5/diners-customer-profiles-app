## Connect SDK integration (authorization workaround)

### What the SDK is

Amazon Connect lets you embed third-party applications inside the Agent Workspace as an iframe. To give those apps access to agent and contact context, AWS provides the **Amazon Connect SDK**:

- `@amazon-connect/app`: initializes the app inside the workspace (`AmazonConnectApp.init`) and sets up communication with Connect.
- `@amazon-connect/contact`: exposes `AgentClient` and `ContactClient` to request agent and contact data, or subscribe to their events.

### What we use

When the app loads, `AgentClient` requests the logged-in agent's data from the workspace:

- `getARN()` and `getName()`: the agent's identity. Require the `User.Details.View` permission.
- `getRoutingProfile()`: the agent's routing profile. Requires the `User.Configuration.View` permission.

These permissions are assigned to the app when it is registered in Connect. Without them, the SDK does not return the data.

### The workaround

We use the routing profile to decide what the agent can see or do in the app. If needed, this value can be sent to the backend to enforce the same rules there.

We rely on this because Connect does not give third-party apps a verifiable identity token. All it exposes is the context of the agent who is already logged in to Connect. We lean on that login and use the context to segment access.

### Why it is not authentication

The app reads the value in the browser and has no way to verify that it is legitimate. It works for deciding what to allow (authorization), but it does not prove the agent's identity. That guarantee still comes from the Connect login.


Example:

dependencies:
```bash
"@amazon-connect/app": "^1.0.11",
"@amazon-connect/contact": "^1.0.11",
"@amazon-connect/user": "^1.0.11",
```

```ts
'use client';

import { AmazonConnectApp } from '@amazon-connect/app';
import { AgentClient, ContactClient } from '@amazon-connect/contact';

let providerPromise: Promise<AmazonConnectApp> | null = null;

export function getProvider(): Promise<AmazonConnectApp> {
  if (providerPromise) return providerPromise;

  providerPromise = new Promise((resolve, reject) => {
    try {
      const { provider } = AmazonConnectApp.init({
        onCreate: async () => {
          resolve(provider);
        },
        onDestroy: async () => {
          providerPromise = null;
        },
      });
    } catch (err) {
      providerPromise = null;
      reject(err);
    }
  });

  return providerPromise;
}

export async function getAgentARN(): Promise<string> {
  const provider = await getProvider();
  const client = new AgentClient(provider);
  return client.getARN();
}
export async function getAgentName(): Promise<string> {
  const provider = await getProvider();
  const client = new AgentClient(provider);
  return client.getName();
}

/** Agent's routing profile — segmentation key per work queue. */
export async function getAgentRoutingProfile(): Promise<{
  arn: string | null;
  id: string | null;
  name: string | null;
}> {
  const provider = await getProvider();
  const client = new AgentClient(provider);
  const rp = await client.getRoutingProfile();
  return {
    arn: rp?.routingProfileARN ?? null,
    id: rp?.routingProfileId ?? null,
    name: rp?.name ?? null,
  };
}

export async function getContactClient(): Promise<ContactClient> {
  const provider = await getProvider();
  return new ContactClient(provider);
}
```

### Links

- [SDK events and requests (developer guide)](https://docs.aws.amazon.com/agentworkspace/latest/devguide/getting-started-events-and-requests.html)
- [Integrate your app with agent data](https://docs.aws.amazon.com/agentworkspace/latest/devguide/integrate-with-agent-data.html)
- [`AgentClient` API reference](https://docs.aws.amazon.com/agentworkspace/latest/devguide/api-reference-3P-apps-agent-client.html)
- [Permissions, events and requests available to third-party apps](https://docs.aws.amazon.com/connect/latest/adminguide/3p-apps-events-requests.html)
- [AWS blog: getting started with third-party apps](https://aws.amazon.com/blogs/contact-center/getting-started-with-third-party-applications-in-the-agent-workspace/)
