import { env, runInDurableObject, SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { TradeDatabase } from "./index";

type Registration = { id: string; trainerName: string; friendCode: string; agreementPublicKey: string; token: string };
type FriendState = { id: string; status: string };
type Invite = { id: string; tradeId: string };
type Receipt = { tradeId: string; trainerAId: string; manifestDigest: string; offerA?: { ciphertext: string }; offerB?: { ciphertext: string } };
let registrationNumber = 0;

const publicKey = (): string => {
  const bytes = new Uint8Array(65);
  bytes[0] = 4;
  bytes[1] = registrationNumber++;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
};

const post = async <T>(path: string, token: string | undefined, value: unknown): Promise<{ status: number; data: T }> => {
  const headers = new Headers({ "content-type": "application/json" });
  if (token) headers.set("authorization", `Bearer ${token}`);
  const response = await SELF.fetch(`https://trade.test${path}`, { method: "POST", headers, body: JSON.stringify(value) });
  return { status: response.status, data: (await response.json()) as T };
};

const get = async <T>(path: string, token: string): Promise<{ status: number; data: T }> => {
  const response = await SELF.fetch(`https://trade.test${path}`, { headers: { authorization: `Bearer ${token}` } });
  return { status: response.status, data: (await response.json()) as T };
};

const register = async (trainerName: string): Promise<Registration> => {
  const token = `${trainerName.toLowerCase()}-${registrationNumber}-${"t".repeat(40)}`;
  const result = await post<Omit<Registration, "token">>("/v1/trainers/register", undefined, {
    trainerName,
    token,
    agreementPublicKey: publicKey(),
  });
  expect(result.status).toBe(201);
  return { ...result.data, token };
};

const nextMessage = (socket: WebSocket, type: string): Promise<Record<string, unknown>> => new Promise((resolve) => {
  const listener = (event: MessageEvent) => {
    const message = JSON.parse(String(event.data)) as Record<string, unknown>;
    if (message.type === type) {
      socket.removeEventListener("message", listener);
      resolve(message);
    }
  };
  socket.addEventListener("message", listener);
});

const connect = async (tradeId: string, token: string): Promise<WebSocket> => {
  const response = await SELF.fetch(`https://trade.test/v1/trades/${tradeId}/ws`, {
    headers: { authorization: `Bearer ${token}`, Upgrade: "websocket" },
  });
  expect(response.status).toBe(101);
  if (!response.webSocket) throw new Error("websocket missing");
  response.webSocket.accept();
  return response.webSocket;
};

const frame = (type: string, body: Record<string, unknown>): string => JSON.stringify({
  v: 1,
  messageId: crypto.randomUUID(),
  type,
  body,
});

describe("lean trade server", () => {
  it("registers two trainers, gates friendship, and lists state", async () => {
    const alice = await register("Alice");
    const bob = await register("Bob");
    const gated = await runInDurableObject(env.TRADE_DB.getByName("global"), async (instance: TradeDatabase) => {
      try {
        await instance.invite(alice.id, { friendCode: bob.friendCode });
        return "";
      } catch (error) {
        return error instanceof Error ? error.message : "";
      }
    });
    expect(gated).toBe("friendship_required");
    const replay = await post<Omit<Registration, "token">>("/v1/trainers/register", undefined, {
      trainerName: alice.trainerName,
      agreementPublicKey: alice.agreementPublicKey,
      token: alice.token,
    });
    expect(replay.status).toBe(201);
    expect(replay.data.id).toBe(alice.id);
    expect("token" in replay.data).toBe(false);
    expect(alice.agreementPublicKey.length).toBeGreaterThanOrEqual(80);
    const decoded = Uint8Array.from(atob(alice.agreementPublicKey), (character) => character.charCodeAt(0));
    const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", decoded));
    let binary = "";
    for (const byte of hash) binary += String.fromCharCode(byte);
    expect(alice.id).toBe(`ptb-trainer-${btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/u, "")}`);

    const request = await post<FriendState>("/v1/friends/requests", alice.token, { friendCode: bob.friendCode });
    expect(request.status).toBe(201);
    const pending = await get<{ requests: FriendState[] }>("/v1/friends", bob.token);
    expect(pending.data.requests[0].status).toBe("pending");

    const accepted = await post<FriendState>(`/v1/friends/requests/${pending.data.requests[0].id}/accept`, bob.token, {});
    expect(accepted.status).toBe(200);
    const friends = await get<{ friends: Array<{ id: string; agreementPublicKey: string }> }>("/v1/friends", alice.token);
    expect(friends.data.friends.map((friend) => friend.id)).toContain(bob.id);
    expect(friends.data.friends[0].agreementPublicKey).toBe(bob.agreementPublicKey);
  });

  it("uses the accepted friendship WebSocket for encrypted offers and one receipt", async () => {
    const alice = await register("Alice");
    const bob = await register("Bob");
    const request = await post<FriendState>("/v1/friends/requests", alice.token, { friendCode: bob.friendCode });
    await post(`/v1/friends/requests/${request.data.id}/accept`, bob.token, {});
    const invite = await post<Invite>("/v1/trades/invite", alice.token, { friendCode: bob.friendCode });
    expect(invite.status).toBe(201);
    const beforeAccept = await SELF.fetch(`https://trade.test/v1/trades/${invite.data.tradeId}/ws`, { headers: { authorization: `Bearer ${alice.token}`, Upgrade: "websocket" } });
    expect(beforeAccept.status).toBe(403);
    const accepted = await post<{ tradeId: string }>(`/v1/trades/invites/${invite.data.id}/accept`, bob.token, {});
    expect(accepted.data.tradeId).toBe(invite.data.tradeId);

    let aliceSocket = await connect(invite.data.tradeId, alice.token);
    await nextMessage(aliceSocket, "trade.ready");
    const bobSocket = await connect(invite.data.tradeId, bob.token);
    await nextMessage(bobSocket, "trade.ready");
    const aliceOfferSeen = nextMessage(bobSocket, "trade.offer");
    aliceSocket.send(frame("trade.offer", { recipientId: bob.id, nonce: "nonce-a1", ciphertext: "cipher-a", tag: "tag-a" }));
    await aliceOfferSeen;
    const manifestSeen = nextMessage(aliceSocket, "trade.manifest");
    bobSocket.send(frame("trade.offer", { recipientId: alice.id, nonce: "nonce-b1", ciphertext: "cipher-b", tag: "tag-b" }));
    const manifest = await manifestSeen;
    const manifestDigest = (manifest.body as { manifestDigest: string }).manifestDigest;
    expect(manifestDigest).toMatch(/^[A-Za-z0-9_-]+$/u);
    aliceSocket.close();
    aliceSocket = await connect(invite.data.tradeId, alice.token);
    const replayed = nextMessage(aliceSocket, "trade.offer");
    const readyAgain = await nextMessage(aliceSocket, "trade.ready");
    expect((readyAgain.body as { manifestDigest: string }).manifestDigest).toBe(manifestDigest);
    expect((await replayed).body).toMatchObject({ senderId: bob.id, recipientId: alice.id, nonce: "nonce-b1", ciphertext: "cipher-b", tag: "tag-b" });
    const confirmed = nextMessage(bobSocket, "trade.confirmed");
    aliceSocket.send(frame("trade.confirm", { manifestDigest }));
    await confirmed;
    const committedSeen = nextMessage(aliceSocket, "trade.committed");
    bobSocket.send(frame("trade.confirm", { manifestDigest }));
    const committed = await committedSeen;
    expect((committed.body as Receipt).manifestDigest).toBe(manifestDigest);
    const replaySeen = nextMessage(bobSocket, "trade.committed");
    aliceSocket.send(frame("trade.confirm", { manifestDigest }));
    expect((await replaySeen).body).toEqual(committed.body);

    const fetched = await get<Receipt>(`/v1/trades/${invite.data.tradeId}/receipt`, alice.token);
    expect(fetched.data.manifestDigest).toBe(manifestDigest);
    await post(`/v1/trades/${invite.data.tradeId}/ack`, alice.token, { manifestDigest });
    const clean = await post<{ cleaned: boolean }>(`/v1/trades/${invite.data.tradeId}/ack`, bob.token, { manifestDigest });
    expect(clean.data.cleaned).toBe(true);
    const after = await get<Receipt>(`/v1/trades/${invite.data.tradeId}/receipt`, alice.token);
    expect(after.data.offerA).toBeUndefined();
    aliceSocket.close();
    bobSocket.close();
  });

  it("stores only a token digest and rejects plaintext offer fields", async () => {
    const alice = await register("Alice");
    const bob = await register("Bob");
    const request = await post<FriendState>("/v1/friends/requests", alice.token, { friendCode: bob.friendCode });
    await post(`/v1/friends/requests/${request.data.id}/accept`, bob.token, {});
    const invite = await post<Invite>("/v1/trades/invite", alice.token, { friendCode: bob.friendCode });
    await post(`/v1/trades/invites/${invite.data.id}/accept`, bob.token, {});
    const socket = await connect(invite.data.tradeId, alice.token);
    await nextMessage(socket, "trade.ready");
    const error = nextMessage(socket, "error");
    socket.send(frame("trade.offer", { recipientId: bob.id, nonce: "nonce-a1", ciphertext: "cipher-a", tag: "tag-a", species: "not accepted" }));
    expect((await error).body).toEqual({ error: "invalid_body" });
    socket.close();
    const rows = await runInDurableObject(env.TRADE_DB.getByName("global"), async (_instance: TradeDatabase, state) =>
      state.storage.sql.exec<{ token_hash: string; offer_a: string | null }>("SELECT t.token_hash, r.offer_a FROM trainers t LEFT JOIN trades r ON r.trainer_a_id = t.id").toArray(),
    );
    expect(JSON.stringify(rows)).not.toContain(alice.token);
    expect(JSON.stringify(rows)).not.toContain("species");
  });
});
