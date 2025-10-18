import { DiscordSDK } from '@discord/embedded-app-sdk';


// Will eventually store the authenticated user's access_token
let auth;

let discordSdk; 


getClientId().then((client_id) => {
  console.debug(client_id)
  discordSdk = new DiscordSDK(client_id);
  setupDiscordSdk(client_id).then(() => {
    console.log("Discord SDK is authenticated");
  })
});

async function getClientId() {
  const response = await fetch("api/client-id");
  const { client_id } = await response.json();
  return client_id;
}

async function setupDiscordSdk(clientId) {
  await discordSdk.ready();
  console.log("Discord SDK is ready");

  // Authorize with Discord Client
  const { code } = await discordSdk.commands.authorize({
    client_id: clientId,
    response_type: "code",
    state: "",
    prompt: "none",
    scope: [
      "identify",
      "guilds",
      "applications.commands"
    ],
  });

  // Retrieve an access_token from your activity's server
  const response = await fetch("api/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      code,
    }),
  });
  const { access_token } = await response.json();

  // Authenticate with Discord client (using the access_token)
  auth = await discordSdk.commands.authenticate({
    access_token,
  });

  if (auth == null) {
    throw new Error("Authenticate command failed");
  }
}

document.querySelector('#app').innerHTML = `
  <div>
    <h1>Hello, World!</h1>
  </div>
`;

